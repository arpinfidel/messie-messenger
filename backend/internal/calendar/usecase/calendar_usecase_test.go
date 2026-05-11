package usecase

import (
	"context"
	"strings"
	"testing"
	"time"

	"messenger/backend/internal/calendar/entity"
)

type fakeCalendarSourceRepo struct {
	sources map[string]entity.CalendarSource
}

func newFakeCalendarSourceRepo() *fakeCalendarSourceRepo {
	return &fakeCalendarSourceRepo{sources: map[string]entity.CalendarSource{}}
}

func (r *fakeCalendarSourceRepo) CreateCalendarSource(ctx context.Context, source *entity.CalendarSource) error {
	r.sources[source.ID] = *source
	return nil
}

func (r *fakeCalendarSourceRepo) GetCalendarSourceByID(ctx context.Context, id string) (*entity.CalendarSource, error) {
	source, ok := r.sources[id]
	if !ok {
		return nil, entity.ErrNotFound
	}
	return &source, nil
}

func (r *fakeCalendarSourceRepo) GetCalendarSourcesByUserID(ctx context.Context, userID string) ([]entity.CalendarSource, error) {
	var result []entity.CalendarSource
	for _, source := range r.sources {
		if source.UserID == userID {
			result = append(result, source)
		}
	}
	return result, nil
}

func (r *fakeCalendarSourceRepo) GetCalendarSourcesDueForRefresh(ctx context.Context, before time.Time, limit int) ([]entity.CalendarSource, error) {
	var result []entity.CalendarSource
	for _, source := range r.sources {
		if source.ImportMode != entity.CalendarImportModeLink {
			continue
		}
		if source.NextRefreshAt == nil || !source.NextRefreshAt.After(before) {
			result = append(result, source)
		}
		if limit > 0 && len(result) >= limit {
			break
		}
	}
	return result, nil
}

func (r *fakeCalendarSourceRepo) UpdateCalendarSource(ctx context.Context, source *entity.CalendarSource) error {
	r.sources[source.ID] = *source
	return nil
}

func (r *fakeCalendarSourceRepo) DeleteCalendarSource(ctx context.Context, id string) error {
	delete(r.sources, id)
	return nil
}

type fakeCalendarEventRepo struct {
	sourceRepo       *fakeCalendarSourceRepo
	events           map[string]entity.CalendarEvent
	lastLimit        int
	lastUpcomingFrom time.Time
}

func newFakeCalendarEventRepo(sourceRepo *fakeCalendarSourceRepo) *fakeCalendarEventRepo {
	return &fakeCalendarEventRepo{
		sourceRepo: sourceRepo,
		events:     map[string]entity.CalendarEvent{},
	}
}

func (r *fakeCalendarEventRepo) CreateCalendarEvents(ctx context.Context, events []entity.CalendarEvent) error {
	for _, event := range events {
		source := r.sourceRepo.sources[event.SourceID]
		event.Source = source
		r.events[event.ID] = event
	}
	return nil
}

func (r *fakeCalendarEventRepo) DeleteCalendarEventsBySourceID(ctx context.Context, sourceID string) error {
	for id, event := range r.events {
		if event.SourceID == sourceID {
			delete(r.events, id)
		}
	}
	return nil
}

func (r *fakeCalendarEventRepo) GetCalendarEventByID(ctx context.Context, id string, userID string) (*entity.CalendarEvent, error) {
	event, ok := r.events[id]
	if !ok {
		return nil, entity.ErrNotFound
	}
	if event.Source.UserID != userID {
		return nil, entity.ErrNotFound
	}
	return &event, nil
}

func (r *fakeCalendarEventRepo) GetCalendarEvents(
	ctx context.Context,
	userID string,
	from *time.Time,
	to *time.Time,
	sourceID *string,
	cursor *time.Time,
	direction *string,
	limit *int,
) ([]entity.CalendarEvent, error) {
	var result []entity.CalendarEvent
	for _, event := range r.events {
		if event.Source.UserID != userID {
			continue
		}
		if sourceID != nil && *sourceID != "" && event.SourceID != *sourceID {
			continue
		}
		if from != nil && event.EndsAt.Before(*from) {
			continue
		}
		if to != nil && event.StartsAt.After(*to) {
			continue
		}
		result = append(result, event)
	}
	return result, nil
}

func (r *fakeCalendarEventRepo) GetUpcomingCalendarEvents(
	ctx context.Context,
	userID string,
	from time.Time,
	limit int,
) ([]entity.CalendarEvent, error) {
	r.lastLimit = limit
	r.lastUpcomingFrom = from
	var result []entity.CalendarEvent
	for _, event := range r.events {
		if event.Source.UserID == userID && !event.EndsAt.Before(from) {
			result = append(result, event)
		}
	}
	return result, nil
}

func TestUsecaseImportCalendarSource(t *testing.T) {
	sourceRepo := newFakeCalendarSourceRepo()
	eventRepo := newFakeCalendarEventRepo(sourceRepo)
	uc := NewUsecase(sourceRepo, eventRepo, NewCalendarICSParser())
	uc.Now = func() time.Time { return time.Date(2026, 4, 21, 12, 0, 0, 0, time.UTC) }

	const input = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nX-WR-CALNAME:Imported Work\r\nBEGIN:VEVENT\r\nUID:event-1@example.com\r\nDTSTAMP:20260421T100000Z\r\nDTSTART:20260422T150000Z\r\nDTEND:20260422T160000Z\r\nSUMMARY:Planning\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

	source, count, err := uc.ImportCalendarSource(
		context.Background(),
		"user-1",
		"work.ics",
		"Work",
		"",
		strings.NewReader(input),
	)
	if err != nil {
		t.Fatalf("ImportCalendarSource() error = %v", err)
	}

	if count != 1 {
		t.Fatalf("ImportedEventCount = %d, want 1", count)
	}
	if source.DisplayName != "Imported Work" {
		t.Fatalf("DisplayName = %q, want %q", source.DisplayName, "Imported Work")
	}
	if source.Category != "Work" {
		t.Fatalf("Category = %v, want %q", source.Category, "Work")
	}
	if sourceRepo.sources[source.ID].UserID != "user-1" {
		t.Fatalf("sourceRepo user ID = %q, want %q", sourceRepo.sources[source.ID].UserID, "user-1")
	}
	if len(eventRepo.events) != 1 {
		t.Fatalf("len(events) = %d, want 1", len(eventRepo.events))
	}
	for _, event := range eventRepo.events {
		if event.ExternalUID != "event-1@example.com" {
			t.Fatalf("ExternalUID = %q, want %q", event.ExternalUID, "event-1@example.com")
		}
	}
}

func TestUsecaseEnforcesPerUserIsolation(t *testing.T) {
	sourceRepo := newFakeCalendarSourceRepo()
	eventRepo := newFakeCalendarEventRepo(sourceRepo)
	uc := NewUsecase(sourceRepo, eventRepo, NewCalendarICSParser())

	sourceRepo.sources["source-1"] = entity.CalendarSource{ID: "source-1", UserID: "user-1", DisplayName: "Work"}
	eventRepo.events["event-1"] = entity.CalendarEvent{
		ID:       "event-1",
		SourceID: "source-1",
		StartsAt: time.Date(2026, 4, 22, 15, 0, 0, 0, time.UTC),
		EndsAt:   time.Date(2026, 4, 22, 16, 0, 0, 0, time.UTC),
		Source:   sourceRepo.sources["source-1"],
		Title:    "Planning",
		Status:   "CONFIRMED",
		Timezone: "UTC",
	}

	if _, err := uc.GetCalendarSourceByID(context.Background(), "source-1", "user-2"); err == nil {
		t.Fatal("GetCalendarSourceByID() error = nil, want non-nil")
	} else if err != entity.ErrNotFound {
		t.Fatalf("GetCalendarSourceByID() error = %v, want entity.ErrNotFound", err)
	}
	if _, err := uc.GetCalendarEventByID(context.Background(), "user-2", "event-1"); err == nil {
		t.Fatal("GetCalendarEventByID() error = nil, want non-nil")
	}
}

func TestUsecaseGetUpcomingCalendarEventsUsesLimit(t *testing.T) {
	sourceRepo := newFakeCalendarSourceRepo()
	eventRepo := newFakeCalendarEventRepo(sourceRepo)
	uc := NewUsecase(sourceRepo, eventRepo, NewCalendarICSParser())
	uc.Now = func() time.Time { return time.Date(2026, 4, 21, 12, 0, 0, 0, time.UTC) }

	sourceRepo.sources["source-1"] = entity.CalendarSource{ID: "source-1", UserID: "user-1", DisplayName: "Work"}
	eventRepo.events["event-1"] = entity.CalendarEvent{
		ID:       "event-1",
		SourceID: "source-1",
		StartsAt: time.Date(2026, 4, 22, 15, 0, 0, 0, time.UTC),
		EndsAt:   time.Date(2026, 4, 22, 16, 0, 0, 0, time.UTC),
		Source:   sourceRepo.sources["source-1"],
		Title:    "Planning",
		Status:   "CONFIRMED",
		Timezone: "UTC",
	}

	_, err := uc.GetUpcomingCalendarEvents(context.Background(), "user-1", 7)
	if err != nil {
		t.Fatalf("GetUpcomingCalendarEvents() error = %v", err)
	}
	if eventRepo.lastLimit != 7 {
		t.Fatalf("lastLimit = %d, want 7", eventRepo.lastLimit)
	}
	if !eventRepo.lastUpcomingFrom.Equal(time.Date(2026, 4, 21, 12, 0, 0, 0, time.UTC)) {
		t.Fatalf("lastUpcomingFrom = %v, want fixed now", eventRepo.lastUpcomingFrom)
	}
}

type fakeCalendarFetcher struct {
	result *CalendarFeedFetchResult
	err    error
	urls   []string
}

func (f *fakeCalendarFetcher) Fetch(
	ctx context.Context,
	sourceURL string,
	etag *string,
	lastModified *time.Time,
) (*CalendarFeedFetchResult, error) {
	f.urls = append(f.urls, sourceURL)
	if f.err != nil {
		return nil, f.err
	}
	return f.result, nil
}

func TestUsecaseImportCalendarSourceFromURL(t *testing.T) {
	sourceRepo := newFakeCalendarSourceRepo()
	eventRepo := newFakeCalendarEventRepo(sourceRepo)
	uc := NewUsecase(sourceRepo, eventRepo, NewCalendarICSParser())
	uc.Now = func() time.Time { return time.Date(2026, 4, 21, 12, 0, 0, 0, time.UTC) }
	uc.Fetcher = &fakeCalendarFetcher{
		result: &CalendarFeedFetchResult{
			Body: []byte("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nX-WR-CALNAME:Imported From Link\r\nBEGIN:VEVENT\r\nUID:event-1@example.com\r\nDTSTAMP:20260421T100000Z\r\nDTSTART:20260422T150000Z\r\nDTEND:20260422T160000Z\r\nSUMMARY:Planning\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"),
		},
	}

	source, count, err := uc.ImportCalendarSourceFromURL(
		context.Background(),
		"user-1",
		"https://calendar.example.com/feed.ics",
		"Work",
		"",
	)
	if err != nil {
		t.Fatalf("ImportCalendarSourceFromURL() error = %v", err)
	}
	if count != 1 {
		t.Fatalf("count = %d, want 1", count)
	}
	if source.ImportMode != entity.CalendarImportModeLink {
		t.Fatalf("ImportMode = %q, want %q", source.ImportMode, entity.CalendarImportModeLink)
	}
	if source.SourceURL == nil || *source.SourceURL != "https://calendar.example.com/feed.ics" {
		t.Fatalf("SourceURL = %v, want feed URL", source.SourceURL)
	}
	if source.Category != "Work" {
		t.Fatalf("Category = %v, want %q", source.Category, "Work")
	}
	if source.NextRefreshAt == nil {
		t.Fatal("NextRefreshAt = nil, want non-nil")
	}
}

func TestUsecaseUpdateCalendarSource(t *testing.T) {
	sourceRepo := newFakeCalendarSourceRepo()
	eventRepo := newFakeCalendarEventRepo(sourceRepo)
	uc := NewUsecase(sourceRepo, eventRepo, NewCalendarICSParser())

	sourceRepo.sources["source-1"] = entity.CalendarSource{
		ID:          "source-1",
		UserID:      "user-1",
		DisplayName: "Work Calendar",
	}

	source, err := uc.UpdateCalendarSource(
		context.Background(),
		"source-1",
		"user-1",
		"Ops",
		"Renamed Calendar",
	)
	if err != nil {
		t.Fatalf("UpdateCalendarSource() error = %v", err)
	}
	if source.DisplayName != "Renamed Calendar" {
		t.Fatalf("DisplayName = %q, want %q", source.DisplayName, "Renamed Calendar")
	}
	if source.Category != "Ops" {
		t.Fatalf("Category = %v, want %q", source.Category, "Ops")
	}
}

func TestUsecaseNormalizesBlankCalendarCategory(t *testing.T) {
	sourceRepo := newFakeCalendarSourceRepo()
	eventRepo := newFakeCalendarEventRepo(sourceRepo)
	uc := NewUsecase(sourceRepo, eventRepo, NewCalendarICSParser())

	const input = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nX-WR-CALNAME:Imported Work\r\nBEGIN:VEVENT\r\nUID:event-1@example.com\r\nDTSTAMP:20260421T100000Z\r\nDTSTART:20260422T150000Z\r\nDTEND:20260422T160000Z\r\nSUMMARY:Planning\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

	source, _, err := uc.ImportCalendarSource(
		context.Background(),
		"user-1",
		"work.ics",
		"   ",
		"",
		strings.NewReader(input),
	)
	if err != nil {
		t.Fatalf("ImportCalendarSource() error = %v", err)
	}
	if source.Category != defaultCalendarCategory {
		t.Fatalf("Category = %q, want %q", source.Category, defaultCalendarCategory)
	}
}

func TestUsecaseRefreshCalendarSource(t *testing.T) {
	sourceRepo := newFakeCalendarSourceRepo()
	eventRepo := newFakeCalendarEventRepo(sourceRepo)
	uc := NewUsecase(sourceRepo, eventRepo, NewCalendarICSParser())
	now := time.Date(2026, 4, 21, 12, 0, 0, 0, time.UTC)
	uc.Now = func() time.Time { return now }
	uc.Fetcher = &fakeCalendarFetcher{
		result: &CalendarFeedFetchResult{
			Body: []byte("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:event-1@example.com\r\nDTSTAMP:20260421T100000Z\r\nDTSTART:20260422T170000Z\r\nDTEND:20260422T180000Z\r\nSUMMARY:Updated Planning\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"),
		},
	}

	sourceRepo.sources["source-1"] = entity.CalendarSource{
		ID:           "source-1",
		UserID:       "user-1",
		DisplayName:  "Linked",
		ImportMode:   entity.CalendarImportModeLink,
		Kind:         entity.CalendarSourceKindICSLink,
		SourceURL:    stringPtr("https://calendar.example.com/feed.ics"),
		RefreshState: entity.CalendarRefreshStateSynced,
	}
	eventRepo.events["event-old"] = entity.CalendarEvent{
		ID:          "event-old",
		SourceID:    "source-1",
		ExternalUID: "old",
		Title:       "Old event",
		StartsAt:    now,
		EndsAt:      now.Add(time.Hour),
		Status:      "CONFIRMED",
		Timezone:    "UTC",
		Source:      sourceRepo.sources["source-1"],
	}

	source, importedCount, err := uc.RefreshCalendarSource(context.Background(), "source-1", "user-1")
	if err != nil {
		t.Fatalf("RefreshCalendarSource() error = %v", err)
	}
	if importedCount != 1 {
		t.Fatalf("importedCount = %d, want 1", importedCount)
	}
	if source.LastSyncedAt == nil || !source.LastSyncedAt.Equal(now) {
		t.Fatalf("LastSyncedAt = %v, want %v", source.LastSyncedAt, now)
	}
	if len(eventRepo.events) != 1 {
		t.Fatalf("len(events) = %d, want 1", len(eventRepo.events))
	}
	for _, event := range eventRepo.events {
		if event.Title != "Updated Planning" {
			t.Fatalf("event.Title = %q, want %q", event.Title, "Updated Planning")
		}
	}
}
