package repository

import (
	"context"
	"time"

	"messenger/backend/internal/calendar/entity"

	"gorm.io/gorm"
)

type CalendarSourceRepository interface {
	CreateCalendarSource(ctx context.Context, source *entity.CalendarSource) error
	GetCalendarSourceByID(ctx context.Context, id string) (*entity.CalendarSource, error)
	GetCalendarSourcesByUserID(ctx context.Context, userID string) ([]entity.CalendarSource, error)
	GetCalendarSourcesDueForRefresh(ctx context.Context, before time.Time, limit int) ([]entity.CalendarSource, error)
	UpdateCalendarSource(ctx context.Context, source *entity.CalendarSource) error
	DeleteCalendarSource(ctx context.Context, id string) error
}

type CalendarEventRepository interface {
	CreateCalendarEvents(ctx context.Context, events []entity.CalendarEvent) error
	DeleteCalendarEventsBySourceID(ctx context.Context, sourceID string) error
	GetCalendarEventByID(ctx context.Context, id string, userID string) (*entity.CalendarEvent, error)
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
	GetUpcomingCalendarEvents(
		ctx context.Context,
		userID string,
		from time.Time,
		limit int,
	) ([]entity.CalendarEvent, error)
}

type Repository interface {
	CalendarSourceRepository
	CalendarEventRepository
}

type repository struct {
	CalendarSourceRepository
	CalendarEventRepository
}

func NewRepository(db *gorm.DB) Repository {
	return &repository{
		CalendarSourceRepository: NewCalendarSourceRepository(db),
		CalendarEventRepository:  NewCalendarEventRepository(db),
	}
}
