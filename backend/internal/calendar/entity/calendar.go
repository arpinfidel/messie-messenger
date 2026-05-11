package entity

import (
	"errors"
	"time"
)

var ErrNotFound = errors.New("not found")

const (
	CalendarSourceKindICSFile = "ics_file"
	CalendarSourceKindICSLink = "ics_link"

	CalendarImportModeUpload = "upload"
	CalendarImportModeLink   = "link"

	CalendarRefreshStateImported = "imported"
	CalendarRefreshStateSynced   = "synced"
	CalendarRefreshStateFailed   = "failed"
)

type CalendarSource struct {
	ID                   string          `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID               string          `gorm:"type:uuid;not null;index" json:"user_id"`
	Kind                 string          `gorm:"type:text;not null" json:"kind"`
	DisplayName          string          `gorm:"type:text;not null" json:"display_name"`
	Category             string          `gorm:"type:text;not null;default:'My Calendars'" json:"category"`
	ImportMode           string          `gorm:"type:text;not null" json:"import_mode"`
	SourceURL            *string         `gorm:"type:text" json:"source_url,omitempty"`
	RefreshState         string          `gorm:"type:text;not null" json:"refresh_state"`
	LastSyncedAt         *time.Time      `gorm:"type:timestamp with time zone" json:"last_synced_at,omitempty"`
	LastRefreshAttemptAt *time.Time      `gorm:"type:timestamp with time zone" json:"last_refresh_attempt_at,omitempty"`
	LastRefreshError     *string         `gorm:"type:text" json:"last_refresh_error,omitempty"`
	ETag                 *string         `gorm:"type:text" json:"etag,omitempty"`
	LastModified         *time.Time      `gorm:"type:timestamp with time zone" json:"last_modified,omitempty"`
	NextRefreshAt        *time.Time      `gorm:"type:timestamp with time zone;index" json:"next_refresh_at,omitempty"`
	CreatedAt            time.Time       `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt            time.Time       `gorm:"autoUpdateTime" json:"updated_at"`
	Events               []CalendarEvent `gorm:"foreignKey:SourceID;constraint:OnDelete:CASCADE;" json:"-"`
}

type CalendarEvent struct {
	ID            string         `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	SourceID      string         `gorm:"type:uuid;not null;index" json:"source_id"`
	ExternalUID   string         `gorm:"type:text;not null;index" json:"external_uid"`
	Title         string         `gorm:"type:text;not null" json:"title"`
	Description   string         `gorm:"type:text;not null" json:"description"`
	Location      string         `gorm:"type:text;not null" json:"location"`
	StartsAt      time.Time      `gorm:"type:timestamp with time zone;not null;index" json:"starts_at"`
	EndsAt        time.Time      `gorm:"type:timestamp with time zone;not null;index" json:"ends_at"`
	AllDay        bool           `gorm:"type:boolean;default:false" json:"all_day"`
	Status        string         `gorm:"type:text;not null" json:"status"`
	Timezone      string         `gorm:"type:text;not null" json:"timezone"`
	RecurrenceRaw *string        `gorm:"type:text" json:"recurrence_raw,omitempty"`
	RawICSBlob    *string        `gorm:"type:text" json:"raw_ics_blob,omitempty"`
	CreatedAt     time.Time      `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt     time.Time      `gorm:"autoUpdateTime" json:"updated_at"`
	Source        CalendarSource `gorm:"foreignKey:SourceID;constraint:OnDelete:CASCADE;" json:"-"`
}
