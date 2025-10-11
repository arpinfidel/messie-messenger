package entity

import (
    "time"

    "github.com/google/uuid"
    "gorm.io/datatypes"
)

type Provider struct {
    ID           uuid.UUID      `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    Key          string         `gorm:"type:varchar(64);uniqueIndex;not null"`
    DisplayName  string         `gorm:"type:varchar(128);not null"`
    Status       string         `gorm:"type:varchar(32);not null;default:'active'"`
    Capabilities datatypes.JSON `gorm:"type:jsonb"`
    CreatedAt    time.Time      `gorm:"autoCreateTime"`
    UpdatedAt    time.Time      `gorm:"autoUpdateTime"`
}

type UserBridgeAccount struct {
    ID         uuid.UUID      `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    UserID     uuid.UUID      `gorm:"type:uuid;index;not null"`
    ProviderID uuid.UUID      `gorm:"type:uuid;index;not null"`
    ExternalID string         `gorm:"type:varchar(255);not null"`
    Status     string         `gorm:"type:varchar(32);not null;default:'connected'"`
    Metadata   datatypes.JSON `gorm:"type:jsonb"`
    CreatedAt  time.Time      `gorm:"autoCreateTime"`
    UpdatedAt  time.Time      `gorm:"autoUpdateTime"`
}

type BridgePairing struct {
    ID         uuid.UUID      `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    UserID     uuid.UUID      `gorm:"type:uuid;index;not null"`
    ProviderID uuid.UUID      `gorm:"type:uuid;index;not null"`
    PairingID  string         `gorm:"type:varchar(128);uniqueIndex;not null"`
    State      string         `gorm:"type:varchar(32);not null;default:'pending'"`
    Payload    datatypes.JSON `gorm:"type:jsonb"`
    ExpiresAt  time.Time      `gorm:"index"`
    CreatedAt  time.Time      `gorm:"autoCreateTime"`
}

type Plan struct {
    ID        uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    Key       string    `gorm:"type:varchar(64);uniqueIndex;not null"`
    Name      string    `gorm:"type:varchar(128);not null"`
    CreatedAt time.Time `gorm:"autoCreateTime"`
}

// Per-plan limits; provider_id may be null for global limits
type PlanLimit struct {
    ID         uuid.UUID  `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    PlanID     uuid.UUID  `gorm:"type:uuid;index;not null"`
    ProviderID *uuid.UUID `gorm:"type:uuid;index"`
    LimitKey   string     `gorm:"type:varchar(64);index;not null"`
    Value      int64      `gorm:"not null"`
}

// User overrides for limits; provider_id may be null for global overrides
type UserPlanOverride struct {
    ID         uuid.UUID  `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    UserID     uuid.UUID  `gorm:"type:uuid;index;not null"`
    ProviderID *uuid.UUID `gorm:"type:uuid;index"`
    LimitKey   string     `gorm:"type:varchar(64);index;not null"`
    Value      int64      `gorm:"not null"`
    UpdatedAt  time.Time  `gorm:"autoUpdateTime"`
}

// Tracks usage windows for enforcement/analytics
type UsageCounter struct {
    ID          uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    UserID      uuid.UUID `gorm:"type:uuid;index;not null"`
    ProviderID  uuid.UUID `gorm:"type:uuid;index;not null"`
    Key         string    `gorm:"type:varchar(64);index;not null"`
    Value       int64     `gorm:"not null"`
    WindowStart time.Time `gorm:"index;not null"`
    WindowEnd   time.Time `gorm:"index;not null"`
}

// One active plan per user
type UserPlan struct {
    ID        uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    UserID    uuid.UUID `gorm:"type:uuid;uniqueIndex;not null"`
    PlanID    uuid.UUID `gorm:"type:uuid;not null"`
    CreatedAt time.Time `gorm:"autoCreateTime"`
}

