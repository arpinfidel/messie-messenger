package repository

import (
	"context"
	"testing"
	"time"

	"messenger/backend/internal/calendar/entity"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestCalendarEventRepositoryGetCalendarEventsCursorLimit(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatalf("gorm.Open() error = %v", err)
	}
	for _, statement := range []string{
		`CREATE TABLE calendar_sources (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL,
			kind TEXT NOT NULL,
			display_name TEXT NOT NULL,
			category TEXT NOT NULL,
			import_mode TEXT NOT NULL,
			source_url TEXT,
			refresh_state TEXT NOT NULL,
			last_synced_at DATETIME,
			last_refresh_attempt_at DATETIME,
			last_refresh_error TEXT,
			e_tag TEXT,
			last_modified DATETIME,
			next_refresh_at DATETIME,
			created_at DATETIME,
			updated_at DATETIME
		)`,
		`CREATE TABLE calendar_events (
			id TEXT PRIMARY KEY,
			source_id TEXT NOT NULL,
			external_uid TEXT NOT NULL,
			title TEXT NOT NULL,
			description TEXT NOT NULL,
			location TEXT NOT NULL,
			starts_at DATETIME NOT NULL,
			ends_at DATETIME NOT NULL,
			all_day BOOLEAN,
			status TEXT NOT NULL,
			timezone TEXT NOT NULL,
			recurrence_raw TEXT,
			raw_ics_blob TEXT,
			created_at DATETIME,
			updated_at DATETIME
		)`,
		`CREATE INDEX idx_calendar_events_starts_at ON calendar_events(starts_at)`,
		`CREATE INDEX idx_calendar_events_ends_at ON calendar_events(ends_at)`,
		`CREATE INDEX idx_calendar_events_source_id ON calendar_events(source_id)`,
	} {
		if err := db.Exec(statement).Error; err != nil {
			t.Fatalf("Exec(%q) error = %v", statement, err)
		}
	}

	source := entity.CalendarSource{
		ID:           "11111111-1111-1111-1111-111111111111",
		UserID:       "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
		Kind:         entity.CalendarSourceKindICSFile,
		DisplayName:  "Work",
		Category:     "Work",
		ImportMode:   entity.CalendarImportModeUpload,
		RefreshState: entity.CalendarRefreshStateImported,
	}
	if err := db.Create(&source).Error; err != nil {
		t.Fatalf("Create(source) error = %v", err)
	}

	events := []entity.CalendarEvent{
		{
			ID:          "22222222-2222-2222-2222-222222222222",
			SourceID:    source.ID,
			ExternalUID: "uid-1",
			Title:       "Older",
			Description: "",
			Location:    "",
			StartsAt:    time.Date(2026, 4, 20, 15, 0, 0, 0, time.UTC),
			EndsAt:      time.Date(2026, 4, 20, 16, 0, 0, 0, time.UTC),
			Status:      "CONFIRMED",
			Timezone:    "UTC",
		},
		{
			ID:          "33333333-3333-3333-3333-333333333333",
			SourceID:    source.ID,
			ExternalUID: "uid-2",
			Title:       "Planning",
			Description: "",
			Location:    "",
			StartsAt:    time.Date(2026, 4, 22, 15, 0, 0, 0, time.UTC),
			EndsAt:      time.Date(2026, 4, 22, 16, 0, 0, 0, time.UTC),
			Status:      "CONFIRMED",
			Timezone:    "UTC",
		},
		{
			ID:          "44444444-4444-4444-4444-444444444444",
			SourceID:    source.ID,
			ExternalUID: "uid-3",
			Title:       "Retro",
			Description: "",
			Location:    "",
			StartsAt:    time.Date(2026, 4, 30, 15, 0, 0, 0, time.UTC),
			EndsAt:      time.Date(2026, 4, 30, 16, 0, 0, 0, time.UTC),
			Status:      "CONFIRMED",
			Timezone:    "UTC",
		},
	}
	if err := db.Create(&events).Error; err != nil {
		t.Fatalf("Create(events) error = %v", err)
	}

	repo := NewCalendarEventRepository(db)
	cursor := time.Date(2026, 4, 30, 0, 0, 0, 0, time.UTC)
	direction := "before"
	limit := 1
	result, err := repo.GetCalendarEvents(
		context.Background(),
		source.UserID,
		nil,
		nil,
		nil,
		&cursor,
		&direction,
		&limit,
	)
	if err != nil {
		t.Fatalf("GetCalendarEvents() error = %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("len(result) = %d, want 1", len(result))
	}
	if result[0].Title != "Planning" {
		t.Fatalf("result[0].Title = %q, want %q", result[0].Title, "Planning")
	}
}
