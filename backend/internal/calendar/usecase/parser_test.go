package usecase

import (
	"strings"
	"testing"

	ical "github.com/emersion/go-ical"
)

func TestCalendarICSParserParsesSingleEvent(t *testing.T) {
	parser := NewCalendarICSParser()

	const input = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nX-WR-CALNAME:Team Calendar\r\nBEGIN:VEVENT\r\nUID:event-1@example.com\r\nDTSTAMP:20260421T100000Z\r\nDTSTART:20260422T150000Z\r\nDTEND:20260422T160000Z\r\nSUMMARY:Planning\r\nDESCRIPTION:Sprint planning\r\nLOCATION:Room 1\r\nSTATUS:CONFIRMED\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

	parsed, err := parser.Parse(strings.NewReader(input), "team.ics")
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}

	if parsed.DisplayName != "Team Calendar" {
		t.Fatalf("DisplayName = %q, want %q", parsed.DisplayName, "Team Calendar")
	}
	if len(parsed.Events) != 1 {
		t.Fatalf("len(Events) = %d, want 1", len(parsed.Events))
	}
	event := parsed.Events[0]
	if event.ExternalUID != "event-1@example.com" {
		t.Fatalf("ExternalUID = %q, want %q", event.ExternalUID, "event-1@example.com")
	}
	if event.Title != "Planning" {
		t.Fatalf("Title = %q, want %q", event.Title, "Planning")
	}
	if event.Timezone != "UTC" {
		t.Fatalf("Timezone = %q, want %q", event.Timezone, "UTC")
	}
	if event.AllDay {
		t.Fatal("AllDay = true, want false")
	}
	if event.RawICSBlob == nil || !strings.Contains(*event.RawICSBlob, "BEGIN:VEVENT") {
		t.Fatalf("RawICSBlob = %v, want encoded VEVENT", event.RawICSBlob)
	}
}

func TestCalendarICSParserParsesAllDayRecurringTimezoneEvent(t *testing.T) {
	parser := NewCalendarICSParser()

	const input = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nDTSTAMP:20260421T100000Z\r\nDTSTART;VALUE=DATE:20260424\r\nRRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:Conference\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:event-2@example.com\r\nDTSTAMP:20260421T100000Z\r\nDTSTART;TZID=America/New_York:20260425T090000\r\nDTEND;TZID=America/New_York:20260425T100000\r\nSUMMARY:Breakfast\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

	parsed, err := parser.Parse(strings.NewReader(input), "conference.ics")
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}

	if len(parsed.Events) != 2 {
		t.Fatalf("len(Events) = %d, want 2", len(parsed.Events))
	}

	allDay := parsed.Events[0]
	if !allDay.AllDay {
		t.Fatal("AllDay = false, want true")
	}
	if allDay.RecurrenceRaw == nil || *allDay.RecurrenceRaw != "FREQ=DAILY;COUNT=3" {
		t.Fatalf("RecurrenceRaw = %v, want RRULE", allDay.RecurrenceRaw)
	}
	if allDay.EndsAt.Sub(allDay.StartsAt).Hours() != 24 {
		t.Fatalf("All-day duration = %v, want 24h", allDay.EndsAt.Sub(allDay.StartsAt))
	}

	tzEvent := parsed.Events[1]
	if tzEvent.Timezone != "America/New_York" {
		t.Fatalf("Timezone = %q, want %q", tzEvent.Timezone, "America/New_York")
	}
}

func TestCalendarICSParserRejectsMalformedInput(t *testing.T) {
	parser := NewCalendarICSParser()

	if _, err := parser.Parse(strings.NewReader("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY"), "bad.ics"); err == nil {
		t.Fatal("Parse() error = nil, want non-nil")
	}
}

func TestCalendarICSParserGeneratesStableFallbackUID(t *testing.T) {
	parser := NewCalendarICSParser()

	const input = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nDTSTAMP:20260421T100000Z\r\nDTSTART:20260426T080000Z\r\nDTEND:20260426T090000Z\r\nSUMMARY:No UID Event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

	first, err := parser.Parse(strings.NewReader(input), "first.ics")
	if err != nil {
		t.Fatalf("Parse() first error = %v", err)
	}
	second, err := parser.Parse(strings.NewReader(input), "second.ics")
	if err != nil {
		t.Fatalf("Parse() second error = %v", err)
	}

	if got, want := first.Events[0].ExternalUID, second.Events[0].ExternalUID; got != want {
		t.Fatalf("ExternalUID mismatch = %q vs %q", got, want)
	}
	if first.Events[0].Timezone != string(ical.ValueDateTime) && first.Events[0].Timezone == "" {
		t.Fatal("Timezone should not be empty")
	}
}

