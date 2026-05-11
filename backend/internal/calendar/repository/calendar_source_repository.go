package repository

import (
	"context"
	"fmt"
	"time"

	"messenger/backend/internal/calendar/entity"

	"gorm.io/gorm"
)

const defaultCalendarCategory = "My Calendars"

type calendarSourceRepository struct {
	db *gorm.DB
}

func EnsureCalendarSourceCategoryConstraint(db *gorm.DB) error {
	statements := []string{
		`UPDATE calendar_sources
		 SET category = ?
		 WHERE category IS NULL OR btrim(category) = ''`,
		`ALTER TABLE calendar_sources
		 ALTER COLUMN category SET DEFAULT 'My Calendars'`,
		`ALTER TABLE calendar_sources
		 ALTER COLUMN category SET NOT NULL`,
	}

	if err := db.Exec(statements[0], defaultCalendarCategory).Error; err != nil {
		return fmt.Errorf("failed to backfill calendar source categories: %w", err)
	}
	for _, statement := range statements[1:] {
		if err := db.Exec(statement).Error; err != nil {
			return fmt.Errorf("failed to enforce calendar source category constraint: %w", err)
		}
	}
	return nil
}

func NewCalendarSourceRepository(db *gorm.DB) CalendarSourceRepository {
	return &calendarSourceRepository{db: db}
}

func (r *calendarSourceRepository) CreateCalendarSource(
	ctx context.Context,
	source *entity.CalendarSource,
) error {
	if err := r.db.WithContext(ctx).Create(source).Error; err != nil {
		return fmt.Errorf("failed to create calendar source: %w", err)
	}
	return nil
}

func (r *calendarSourceRepository) GetCalendarSourceByID(
	ctx context.Context,
	id string,
) (*entity.CalendarSource, error) {
	var source entity.CalendarSource
	if err := r.db.WithContext(ctx).First(&source, "id = ?", id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, entity.ErrNotFound
		}
		return nil, fmt.Errorf("failed to get calendar source by ID: %w", err)
	}
	return &source, nil
}

func (r *calendarSourceRepository) GetCalendarSourcesByUserID(
	ctx context.Context,
	userID string,
) ([]entity.CalendarSource, error) {
	var sources []entity.CalendarSource
	if err := r.db.WithContext(ctx).
		Where("user_id = ?", userID).
		Order("created_at DESC").
		Find(&sources).Error; err != nil {
		return nil, fmt.Errorf("failed to get calendar sources by user ID: %w", err)
	}
	return sources, nil
}

func (r *calendarSourceRepository) GetCalendarSourcesDueForRefresh(
	ctx context.Context,
	before time.Time,
	limit int,
) ([]entity.CalendarSource, error) {
	query := r.db.WithContext(ctx).
		Where("import_mode = ?", entity.CalendarImportModeLink).
		Where("source_url IS NOT NULL").
		Where("next_refresh_at IS NULL OR next_refresh_at <= ?", before).
		Order("next_refresh_at ASC NULLS FIRST").
		Order("updated_at ASC")

	if limit > 0 {
		query = query.Limit(limit)
	}

	var sources []entity.CalendarSource
	if err := query.Find(&sources).Error; err != nil {
		return nil, fmt.Errorf("failed to get calendar sources due for refresh: %w", err)
	}
	return sources, nil
}

func (r *calendarSourceRepository) UpdateCalendarSource(
	ctx context.Context,
	source *entity.CalendarSource,
) error {
	if err := r.db.WithContext(ctx).Save(source).Error; err != nil {
		return fmt.Errorf("failed to update calendar source: %w", err)
	}
	return nil
}

func (r *calendarSourceRepository) DeleteCalendarSource(
	ctx context.Context,
	id string,
) error {
	if err := r.db.WithContext(ctx).
		Delete(&entity.CalendarSource{}, "id = ?", id).Error; err != nil {
		return fmt.Errorf("failed to delete calendar source: %w", err)
	}
	return nil
}
