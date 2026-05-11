package repository

import (
	"context"
	"fmt"
	"time"

	"messenger/backend/internal/calendar/entity"

	"gorm.io/gorm"
)

const (
	calendarEventDirectionBefore = "before"
	calendarEventDirectionAfter  = "after"
)

type calendarEventRepository struct {
	db *gorm.DB
}

func NewCalendarEventRepository(db *gorm.DB) CalendarEventRepository {
	return &calendarEventRepository{db: db}
}

func (r *calendarEventRepository) CreateCalendarEvents(
	ctx context.Context,
	events []entity.CalendarEvent,
) error {
	if len(events) == 0 {
		return nil
	}
	if err := r.db.WithContext(ctx).Create(&events).Error; err != nil {
		return fmt.Errorf("failed to create calendar events: %w", err)
	}
	return nil
}

func (r *calendarEventRepository) DeleteCalendarEventsBySourceID(
	ctx context.Context,
	sourceID string,
) error {
	if err := r.db.WithContext(ctx).
		Where("source_id = ?", sourceID).
		Delete(&entity.CalendarEvent{}).Error; err != nil {
		return fmt.Errorf("failed to delete calendar events by source ID: %w", err)
	}
	return nil
}

func (r *calendarEventRepository) GetCalendarEventByID(
	ctx context.Context,
	id string,
	userID string,
) (*entity.CalendarEvent, error) {
	var event entity.CalendarEvent
	if err := r.db.WithContext(ctx).
		Joins("JOIN calendar_sources ON calendar_sources.id = calendar_events.source_id").
		Where("calendar_events.id = ? AND calendar_sources.user_id = ?", id, userID).
		Preload("Source").
		First(&event).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, entity.ErrNotFound
		}
		return nil, fmt.Errorf("failed to get calendar event by ID: %w", err)
	}
	return &event, nil
}

func (r *calendarEventRepository) GetCalendarEvents(
	ctx context.Context,
	userID string,
	from *time.Time,
	to *time.Time,
	sourceID *string,
	cursor *time.Time,
	direction *string,
	limit *int,
) ([]entity.CalendarEvent, error) {
	query := r.db.WithContext(ctx).
		Model(&entity.CalendarEvent{}).
		Joins("JOIN calendar_sources ON calendar_sources.id = calendar_events.source_id").
		Where("calendar_sources.user_id = ?", userID)

	if sourceID != nil && *sourceID != "" {
		query = query.Where("calendar_events.source_id = ?", *sourceID)
	}
	if from != nil {
		query = query.Where("calendar_events.ends_at >= ?", *from)
	}
	if to != nil {
		query = query.Where("calendar_events.starts_at <= ?", *to)
	}

	directionValue := calendarEventDirectionAfter
	if direction != nil && *direction != "" {
		directionValue = *direction
	}
	if cursor != nil {
		if directionValue == calendarEventDirectionBefore {
			query = query.Where("calendar_events.starts_at < ?", *cursor)
		} else {
			query = query.Where("calendar_events.starts_at >= ?", *cursor)
		}
	}

	var events []entity.CalendarEvent
	query = query.Preload("Source")
	if cursor != nil && directionValue == calendarEventDirectionBefore {
		query = query.
			Order("calendar_events.starts_at DESC").
			Order("calendar_events.created_at DESC")
	} else {
		query = query.
			Order("calendar_events.starts_at ASC").
			Order("calendar_events.created_at ASC")
	}
	if limit != nil && *limit > 0 {
		query = query.Limit(*limit)
	}
	if err := query.
		Find(&events).Error; err != nil {
		return nil, fmt.Errorf("failed to get calendar events: %w", err)
	}
	if cursor != nil && directionValue == calendarEventDirectionBefore {
		for left, right := 0, len(events)-1; left < right; left, right = left+1, right-1 {
			events[left], events[right] = events[right], events[left]
		}
	}
	return events, nil
}

func (r *calendarEventRepository) GetUpcomingCalendarEvents(
	ctx context.Context,
	userID string,
	from time.Time,
	limit int,
) ([]entity.CalendarEvent, error) {
	query := r.db.WithContext(ctx).
		Model(&entity.CalendarEvent{}).
		Joins("JOIN calendar_sources ON calendar_sources.id = calendar_events.source_id").
		Where("calendar_sources.user_id = ?", userID).
		Where("calendar_events.ends_at >= ?", from).
		Preload("Source").
		Order("calendar_events.starts_at ASC").
		Order("calendar_events.created_at ASC")

	if limit > 0 {
		query = query.Limit(limit)
	}

	var events []entity.CalendarEvent
	if err := query.Find(&events).Error; err != nil {
		return nil, fmt.Errorf("failed to get upcoming calendar events: %w", err)
	}
	return events, nil
}
