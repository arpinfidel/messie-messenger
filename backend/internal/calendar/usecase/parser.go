package usecase

import (
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"io"
	"strings"
	"time"

	ical "github.com/emersion/go-ical"
	"github.com/google/uuid"
)

type parsedCalendar struct {
	DisplayName string
	Events      []parsedCalendarEvent
}

type parsedCalendarEvent struct {
	ExternalUID   string
	Title         string
	Description   string
	Location      string
	StartsAt      time.Time
	EndsAt        time.Time
	AllDay        bool
	Status        string
	Timezone      string
	RecurrenceRaw *string
	RawICSBlob    *string
}

type CalendarICSParser interface {
	Parse(r io.Reader, filename string) (*parsedCalendar, error)
}

type calendarICSParser struct{}

func NewCalendarICSParser() CalendarICSParser {
	return &calendarICSParser{}
}

func (p *calendarICSParser) Parse(
	r io.Reader,
	filename string,
) (*parsedCalendar, error) {
	dec := ical.NewDecoder(r)
	cal, err := dec.Decode()
	if err != nil {
		return nil, fmt.Errorf("failed to decode iCalendar data: %w", err)
	}

	displayName := parseCalendarDisplayName(cal, filename)
	events := make([]parsedCalendarEvent, 0, len(cal.Events()))
	for index, event := range cal.Events() {
		parsedEvent, err := parseCalendarEvent(event, index)
		if err != nil {
			return nil, err
		}
		events = append(events, parsedEvent)
	}

	if len(events) == 0 {
		return nil, fmt.Errorf("calendar file contains no VEVENT entries")
	}

	return &parsedCalendar{
		DisplayName: displayName,
		Events:      events,
	}, nil
}

func parseCalendarDisplayName(cal *ical.Calendar, filename string) string {
	if value, err := cal.Props.Text(ical.PropName); err == nil && strings.TrimSpace(value) != "" {
		return strings.TrimSpace(value)
	}
	if value, err := cal.Props.Text("X-WR-CALNAME"); err == nil && strings.TrimSpace(value) != "" {
		return strings.TrimSpace(value)
	}
	name := strings.TrimSpace(filename)
	name = strings.TrimSuffix(name, ".ics")
	name = strings.TrimSuffix(name, ".ICS")
	if name != "" {
		return name
	}
	return "Imported calendar"
}

func parseCalendarEvent(event ical.Event, index int) (parsedCalendarEvent, error) {
	startProp := event.Props.Get(ical.PropDateTimeStart)
	if startProp == nil {
		return parsedCalendarEvent{}, fmt.Errorf("calendar event %d is missing DTSTART", index)
	}
	startsAt, err := startProp.DateTime(nil)
	if err != nil {
		return parsedCalendarEvent{}, fmt.Errorf("failed to parse DTSTART for event %d: %w", index, err)
	}

	allDay := startProp.ValueType() == ical.ValueDate
	endsAt, err := resolveEventEnd(event, startsAt, allDay)
	if err != nil {
		return parsedCalendarEvent{}, err
	}

	title, _ := event.Props.Text(ical.PropSummary)
	description, _ := event.Props.Text(ical.PropDescription)
	location, _ := event.Props.Text(ical.PropLocation)
	uid, _ := event.Props.Text(ical.PropUID)
	uid = strings.TrimSpace(uid)
	if uid == "" {
		uid = fallbackExternalUID(event, index)
	}

	status := "CONFIRMED"
	if parsedStatus, err := event.Status(); err == nil && strings.TrimSpace(string(parsedStatus)) != "" {
		status = string(parsedStatus)
	}

	timezone := strings.TrimSpace(startProp.Params.Get("TZID"))
	if timezone == "" {
		timezone = startsAt.Location().String()
	}
	if timezone == "" {
		timezone = "UTC"
	}

	var recurrenceRaw *string
	if prop := event.Props.Get("RRULE"); prop != nil && strings.TrimSpace(prop.Value) != "" {
		value := strings.TrimSpace(prop.Value)
		recurrenceRaw = &value
	}

	rawICSBlob := encodeEventComponent(event)

	return parsedCalendarEvent{
		ExternalUID:   uid,
		Title:         strings.TrimSpace(title),
		Description:   strings.TrimSpace(description),
		Location:      strings.TrimSpace(location),
		StartsAt:      startsAt.UTC(),
		EndsAt:        endsAt.UTC(),
		AllDay:        allDay,
		Status:        status,
		Timezone:      timezone,
		RecurrenceRaw: recurrenceRaw,
		RawICSBlob:    rawICSBlob,
	}, nil
}

func resolveEventEnd(
	event ical.Event,
	startsAt time.Time,
	allDay bool,
) (time.Time, error) {
	endProp := event.Props.Get(ical.PropDateTimeEnd)
	if endProp != nil {
		endsAt, err := endProp.DateTime(nil)
		if err != nil {
			return time.Time{}, fmt.Errorf("failed to parse DTEND: %w", err)
		}
		return endsAt, nil
	}

	durationProp := event.Props.Get(ical.PropDuration)
	if durationProp != nil {
		duration, err := durationProp.Duration()
		if err != nil {
			return time.Time{}, fmt.Errorf("failed to parse DURATION: %w", err)
		}
		return startsAt.Add(duration), nil
	}

	if allDay {
		return startsAt.Add(24 * time.Hour), nil
	}
	return startsAt, nil
}

func fallbackExternalUID(event ical.Event, index int) string {
	var builder strings.Builder
	for _, prop := range event.Props.Values(ical.PropSummary) {
		builder.WriteString(prop.Value)
	}
	for _, prop := range event.Props.Values(ical.PropDateTimeStart) {
		builder.WriteString(prop.Value)
	}
	for _, prop := range event.Props.Values(ical.PropDateTimeEnd) {
		builder.WriteString(prop.Value)
	}
	builder.WriteString(fmt.Sprintf("#%d", index))
	hash := sha1.Sum([]byte(builder.String()))
	return fmt.Sprintf("imported-%s", hex.EncodeToString(hash[:]))
}

func encodeEventComponent(event ical.Event) *string {
	cal := ical.NewCalendar()
	cal.Props.SetText(ical.PropVersion, "2.0")
	cal.Props.SetText(ical.PropProductID, "-//Messie//Calendar Import//EN")
	cal.Children = append(cal.Children, event.Component)
	var buf bytes.Buffer
	if err := ical.NewEncoder(&buf).Encode(cal); err != nil {
		return nil
	}
	value := strings.TrimSpace(buf.String())
	if value == "" {
		return nil
	}
	return &value
}

func newCalendarSourceID() string {
	return uuid.New().String()
}

func newCalendarEventID() string {
	return uuid.New().String()
}

