package usecase

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/url"
	"path"
	"strings"
	"time"

	"messenger/backend/internal/calendar/entity"
	"messenger/backend/internal/calendar/repository"
)

type CalendarSourceUsecase interface {
	ImportCalendarSource(
		ctx context.Context,
		userID string,
		filename string,
		category string,
		displayName string,
		reader io.Reader,
	) (*entity.CalendarSource, int, error)
	ImportCalendarSourceFromURL(
		ctx context.Context,
		userID string,
		sourceURL string,
		category string,
		displayName string,
	) (*entity.CalendarSource, int, error)
	GetCalendarSources(ctx context.Context, userID string) ([]entity.CalendarSource, error)
	GetCalendarSourceByID(ctx context.Context, sourceID string, userID string) (*entity.CalendarSource, error)
	UpdateCalendarSource(ctx context.Context, sourceID string, userID string, category string, displayName string) (*entity.CalendarSource, error)
	RefreshCalendarSource(ctx context.Context, sourceID string, userID string) (*entity.CalendarSource, int, error)
	DeleteCalendarSource(ctx context.Context, sourceID string, userID string) error
}

type CalendarEventUsecase interface {
	GetCalendarEvents(
		ctx context.Context,
		userID string,
		from *time.Time,
		to *time.Time,
		sourceID *string,
		cursor *time.Time,
		direction *string,
		limit *int,
	) ([]entity.CalendarEvent, error)
	GetCalendarEventByID(ctx context.Context, userID string, eventID string) (*entity.CalendarEvent, error)
	GetUpcomingCalendarEvents(ctx context.Context, userID string, limit int) ([]entity.CalendarEvent, error)
}

type Usecase struct {
	SourceRepo repository.CalendarSourceRepository
	EventRepo  repository.CalendarEventRepository
	Parser     CalendarICSParser
	Fetcher    CalendarFeedFetcher
	Now        func() time.Time
}

const calendarSyncInterval = time.Hour
const defaultCalendarCategory = "My Calendars"

func NewUsecase(
	sourceRepo repository.CalendarSourceRepository,
	eventRepo repository.CalendarEventRepository,
	parser CalendarICSParser,
) *Usecase {
	return &Usecase{
		SourceRepo: sourceRepo,
		EventRepo:  eventRepo,
		Parser:     parser,
		Fetcher:    NewHTTPCalendarFeedFetcher(30 * time.Second),
		Now:        time.Now,
	}
}

func normalizeCalendarCategory(category string) string {
	trimmed := strings.TrimSpace(category)
	if trimmed == "" {
		return defaultCalendarCategory
	}
	return trimmed
}

func (uc *Usecase) ImportCalendarSource(
	ctx context.Context,
	userID string,
	filename string,
	category string,
	displayName string,
	reader io.Reader,
) (*entity.CalendarSource, int, error) {
	if strings.TrimSpace(userID) == "" {
		return nil, 0, fmt.Errorf("user ID is required")
	}

	parsedCalendar, err := uc.Parser.Parse(reader, filename)
	if err != nil {
		return nil, 0, err
	}

	name := strings.TrimSpace(displayName)
	if name == "" {
		name = parsedCalendar.DisplayName
	}

	now := uc.Now().UTC()
	source := &entity.CalendarSource{
		ID:           newCalendarSourceID(),
		UserID:       userID,
		Kind:         entity.CalendarSourceKindICSFile,
		DisplayName:  name,
		Category:     normalizeCalendarCategory(category),
		ImportMode:   entity.CalendarImportModeUpload,
		RefreshState: entity.CalendarRefreshStateImported,
		LastSyncedAt: &now,
	}

	if err := uc.SourceRepo.CreateCalendarSource(ctx, source); err != nil {
		return nil, 0, fmt.Errorf("failed to create calendar source: %w", err)
	}

	events := make([]entity.CalendarEvent, 0, len(parsedCalendar.Events))
	for _, parsedEvent := range parsedCalendar.Events {
		events = append(events, entity.CalendarEvent{
			ID:            newCalendarEventID(),
			SourceID:      source.ID,
			ExternalUID:   parsedEvent.ExternalUID,
			Title:         defaultCalendarTitle(parsedEvent.Title),
			Description:   parsedEvent.Description,
			Location:      parsedEvent.Location,
			StartsAt:      parsedEvent.StartsAt,
			EndsAt:        parsedEvent.EndsAt,
			AllDay:        parsedEvent.AllDay,
			Status:        parsedEvent.Status,
			Timezone:      parsedEvent.Timezone,
			RecurrenceRaw: parsedEvent.RecurrenceRaw,
			RawICSBlob:    parsedEvent.RawICSBlob,
		})
	}

	if err := uc.EventRepo.CreateCalendarEvents(ctx, events); err != nil {
		_ = uc.SourceRepo.DeleteCalendarSource(ctx, source.ID)
		return nil, 0, fmt.Errorf("failed to create calendar events: %w", err)
	}

	return source, len(events), nil
}

func (uc *Usecase) ImportCalendarSourceFromURL(
	ctx context.Context,
	userID string,
	sourceURL string,
	category string,
	displayName string,
) (*entity.CalendarSource, int, error) {
	if strings.TrimSpace(userID) == "" {
		return nil, 0, fmt.Errorf("user ID is required")
	}
	normalizedURL, err := validateCalendarSourceURL(sourceURL)
	if err != nil {
		return nil, 0, err
	}
	if uc.Fetcher == nil {
		return nil, 0, fmt.Errorf("calendar feed fetcher is not configured")
	}

	result, err := uc.Fetcher.Fetch(ctx, normalizedURL, nil, nil)
	if err != nil {
		return nil, 0, err
	}
	if result.NotModified {
		return nil, 0, fmt.Errorf("calendar URL returned not modified during initial import")
	}

	parsedCalendar, err := uc.Parser.Parse(
		bytes.NewReader(result.Body),
		filenameFromCalendarURL(normalizedURL),
	)
	if err != nil {
		return nil, 0, err
	}

	name := strings.TrimSpace(displayName)
	if name == "" {
		name = parsedCalendar.DisplayName
	}

	now := uc.Now().UTC()
	nextRefreshAt := now.Add(calendarSyncInterval)
	source := &entity.CalendarSource{
		ID:                   newCalendarSourceID(),
		UserID:               userID,
		Kind:                 entity.CalendarSourceKindICSLink,
		DisplayName:          name,
		Category:             normalizeCalendarCategory(category),
		ImportMode:           entity.CalendarImportModeLink,
		SourceURL:            &normalizedURL,
		RefreshState:         entity.CalendarRefreshStateSynced,
		LastSyncedAt:         &now,
		LastRefreshAttemptAt: &now,
		ETag:                 result.ETag,
		LastModified:         result.LastModified,
		NextRefreshAt:        &nextRefreshAt,
	}

	if err := uc.SourceRepo.CreateCalendarSource(ctx, source); err != nil {
		return nil, 0, fmt.Errorf("failed to create calendar source: %w", err)
	}

	events := uc.buildCalendarEvents(source.ID, parsedCalendar.Events)
	if err := uc.EventRepo.CreateCalendarEvents(ctx, events); err != nil {
		_ = uc.SourceRepo.DeleteCalendarSource(ctx, source.ID)
		return nil, 0, fmt.Errorf("failed to create calendar events: %w", err)
	}

	return source, len(events), nil
}

func (uc *Usecase) GetCalendarSources(
	ctx context.Context,
	userID string,
) ([]entity.CalendarSource, error) {
	sources, err := uc.SourceRepo.GetCalendarSourcesByUserID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get calendar sources: %w", err)
	}
	return sources, nil
}

func (uc *Usecase) GetCalendarSourceByID(
	ctx context.Context,
	sourceID string,
	userID string,
) (*entity.CalendarSource, error) {
	source, err := uc.SourceRepo.GetCalendarSourceByID(ctx, sourceID)
	if err != nil {
		return nil, fmt.Errorf("failed to get calendar source by ID: %w", err)
	}
	if source.UserID != userID {
		return nil, entity.ErrNotFound
	}
	return source, nil
}

func (uc *Usecase) UpdateCalendarSource(
	ctx context.Context,
	sourceID string,
	userID string,
	category string,
	displayName string,
) (*entity.CalendarSource, error) {
	source, err := uc.GetCalendarSourceByID(ctx, sourceID, userID)
	if err != nil {
		return nil, err
	}
	name := strings.TrimSpace(displayName)
	if name == "" {
		return nil, fmt.Errorf("display name is required")
	}
	source.DisplayName = name
	source.Category = normalizeCalendarCategory(category)
	if err := uc.SourceRepo.UpdateCalendarSource(ctx, source); err != nil {
		return nil, fmt.Errorf("failed to update calendar source: %w", err)
	}
	return source, nil
}

func (uc *Usecase) RefreshCalendarSource(
	ctx context.Context,
	sourceID string,
	userID string,
) (*entity.CalendarSource, int, error) {
	source, err := uc.GetCalendarSourceByID(ctx, sourceID, userID)
	if err != nil {
		return nil, 0, err
	}
	importedCount, err := uc.refreshCalendarSource(ctx, source)
	return source, importedCount, err
}

func (uc *Usecase) DeleteCalendarSource(
	ctx context.Context,
	sourceID string,
	userID string,
) error {
	source, err := uc.GetCalendarSourceByID(ctx, sourceID, userID)
	if err != nil {
		return err
	}
	if err := uc.SourceRepo.DeleteCalendarSource(ctx, source.ID); err != nil {
		return fmt.Errorf("failed to delete calendar source: %w", err)
	}
	return nil
}

func (uc *Usecase) RefreshDueCalendarSources(
	ctx context.Context,
	limit int,
) (int, error) {
	if uc.Fetcher == nil {
		return 0, fmt.Errorf("calendar feed fetcher is not configured")
	}
	sources, err := uc.SourceRepo.GetCalendarSourcesDueForRefresh(
		ctx,
		uc.Now().UTC(),
		limit,
	)
	if err != nil {
		return 0, fmt.Errorf("failed to list calendar sources due for refresh: %w", err)
	}

	refreshed := 0
	for i := range sources {
		source := sources[i]
		if _, err := uc.refreshCalendarSource(ctx, &source); err != nil {
			continue
		}
		refreshed++
	}
	return refreshed, nil
}

func (uc *Usecase) GetCalendarEvents(
	ctx context.Context,
	userID string,
	from *time.Time,
	to *time.Time,
	sourceID *string,
	cursor *time.Time,
	direction *string,
	limit *int,
) ([]entity.CalendarEvent, error) {
	if sourceID != nil && *sourceID != "" {
		if _, err := uc.GetCalendarSourceByID(ctx, *sourceID, userID); err != nil {
			return nil, err
		}
	}
	events, err := uc.EventRepo.GetCalendarEvents(
		ctx,
		userID,
		from,
		to,
		sourceID,
		cursor,
		direction,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get calendar events: %w", err)
	}
	return events, nil
}

func (uc *Usecase) GetCalendarEventByID(
	ctx context.Context,
	userID string,
	eventID string,
) (*entity.CalendarEvent, error) {
	event, err := uc.EventRepo.GetCalendarEventByID(ctx, eventID, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get calendar event by ID: %w", err)
	}
	return event, nil
}

func (uc *Usecase) GetUpcomingCalendarEvents(
	ctx context.Context,
	userID string,
	limit int,
) ([]entity.CalendarEvent, error) {
	if limit <= 0 {
		limit = 50
	}
	events, err := uc.EventRepo.GetUpcomingCalendarEvents(
		ctx,
		userID,
		uc.Now().UTC(),
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to get upcoming calendar events: %w", err)
	}
	return events, nil
}

func defaultCalendarTitle(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "Untitled event"
	}
	return value
}

func (uc *Usecase) refreshCalendarSource(
	ctx context.Context,
	source *entity.CalendarSource,
) (int, error) {
	if source.ImportMode != entity.CalendarImportModeLink || source.SourceURL == nil || strings.TrimSpace(*source.SourceURL) == "" {
		return 0, fmt.Errorf("calendar source is not refreshable")
	}
	if uc.Fetcher == nil {
		return 0, fmt.Errorf("calendar feed fetcher is not configured")
	}

	now := uc.Now().UTC()
	source.LastRefreshAttemptAt = &now
	source.NextRefreshAt = timePtr(now.Add(calendarSyncInterval))

	result, err := uc.Fetcher.Fetch(ctx, *source.SourceURL, source.ETag, source.LastModified)
	if err != nil {
		source.RefreshState = entity.CalendarRefreshStateFailed
		source.LastRefreshError = stringPtr(err.Error())
		_ = uc.SourceRepo.UpdateCalendarSource(ctx, source)
		return 0, err
	}

	if result.NotModified {
		source.RefreshState = entity.CalendarRefreshStateSynced
		source.LastRefreshError = nil
		source.LastSyncedAt = &now
		if result.ETag != nil {
			source.ETag = result.ETag
		}
		if result.LastModified != nil {
			source.LastModified = result.LastModified
		}
		if err := uc.SourceRepo.UpdateCalendarSource(ctx, source); err != nil {
			return 0, fmt.Errorf("failed to update calendar source after not-modified refresh: %w", err)
		}
		return 0, nil
	}

	parsedCalendar, err := uc.Parser.Parse(
		bytes.NewReader(result.Body),
		filenameFromCalendarURL(*source.SourceURL),
	)
	if err != nil {
		source.RefreshState = entity.CalendarRefreshStateFailed
		source.LastRefreshError = stringPtr(err.Error())
		_ = uc.SourceRepo.UpdateCalendarSource(ctx, source)
		return 0, err
	}

	if err := uc.EventRepo.DeleteCalendarEventsBySourceID(ctx, source.ID); err != nil {
		source.RefreshState = entity.CalendarRefreshStateFailed
		source.LastRefreshError = stringPtr(err.Error())
		_ = uc.SourceRepo.UpdateCalendarSource(ctx, source)
		return 0, fmt.Errorf("failed to clear old calendar events: %w", err)
	}

	events := uc.buildCalendarEvents(source.ID, parsedCalendar.Events)
	if err := uc.EventRepo.CreateCalendarEvents(ctx, events); err != nil {
		source.RefreshState = entity.CalendarRefreshStateFailed
		source.LastRefreshError = stringPtr(err.Error())
		_ = uc.SourceRepo.UpdateCalendarSource(ctx, source)
		return 0, fmt.Errorf("failed to create refreshed calendar events: %w", err)
	}

	source.RefreshState = entity.CalendarRefreshStateSynced
	source.LastRefreshError = nil
	source.LastSyncedAt = &now
	source.ETag = result.ETag
	source.LastModified = result.LastModified
	if err := uc.SourceRepo.UpdateCalendarSource(ctx, source); err != nil {
		return 0, fmt.Errorf("failed to update refreshed calendar source: %w", err)
	}
	return len(events), nil
}

func (uc *Usecase) buildCalendarEvents(
	sourceID string,
	parsedEvents []parsedCalendarEvent,
) []entity.CalendarEvent {
	events := make([]entity.CalendarEvent, 0, len(parsedEvents))
	for _, parsedEvent := range parsedEvents {
		events = append(events, entity.CalendarEvent{
			ID:            newCalendarEventID(),
			SourceID:      sourceID,
			ExternalUID:   parsedEvent.ExternalUID,
			Title:         defaultCalendarTitle(parsedEvent.Title),
			Description:   parsedEvent.Description,
			Location:      parsedEvent.Location,
			StartsAt:      parsedEvent.StartsAt,
			EndsAt:        parsedEvent.EndsAt,
			AllDay:        parsedEvent.AllDay,
			Status:        parsedEvent.Status,
			Timezone:      parsedEvent.Timezone,
			RecurrenceRaw: parsedEvent.RecurrenceRaw,
			RawICSBlob:    parsedEvent.RawICSBlob,
		})
	}
	return events
}

func validateCalendarSourceURL(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", fmt.Errorf("calendar URL is required")
	}
	parsed, err := url.Parse(value)
	if err != nil {
		return "", fmt.Errorf("invalid calendar URL: %w", err)
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", fmt.Errorf("calendar URL must use http or https")
	}
	if parsed.Host == "" {
		return "", fmt.Errorf("calendar URL must include a host")
	}
	return parsed.String(), nil
}

func filenameFromCalendarURL(sourceURL string) string {
	parsed, err := url.Parse(sourceURL)
	if err != nil {
		return "calendar.ics"
	}
	name := path.Base(parsed.Path)
	name = strings.TrimSpace(name)
	if name == "" || name == "." || name == "/" {
		return "calendar.ics"
	}
	return name
}

func timePtr(value time.Time) *time.Time {
	return &value
}

func stringPtr(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return &value
}
