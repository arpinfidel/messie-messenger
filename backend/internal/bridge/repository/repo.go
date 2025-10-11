package repository

import (
    "context"

    "github.com/google/uuid"
    "messenger/backend/internal/bridge/entity"
    "gorm.io/gorm"
)

type Repo struct { db *gorm.DB }

func NewRepo(db *gorm.DB) *Repo { return &Repo{db: db} }

func (r *Repo) GetProviderByKey(ctx context.Context, key string) (*entity.Provider, error) {
    var p entity.Provider
    if err := r.db.WithContext(ctx).Where("key = ?", key).First(&p).Error; err != nil {
        return nil, err
    }
    return &p, nil
}

func (r *Repo) EnsureProvider(ctx context.Context, key, display string) (*entity.Provider, error) {
    var p entity.Provider
    if err := r.db.WithContext(ctx).Where("key = ?", key).First(&p).Error; err == nil {
        return &p, nil
    }
    p = entity.Provider{Key: key, DisplayName: display, Status: "active"}
    if err := r.db.WithContext(ctx).Create(&p).Error; err != nil {
        return nil, err
    }
    return &p, nil
}

func (r *Repo) CountUserAccounts(ctx context.Context, userID, providerID uuid.UUID) (int64, error) {
    var n int64
    err := r.db.WithContext(ctx).Model(&entity.UserBridgeAccount{}).
        Where("user_id = ? AND provider_id = ?", userID, providerID).Count(&n).Error
    return n, err
}

func (r *Repo) ListUserAccounts(ctx context.Context, userID uuid.UUID) ([]entity.UserBridgeAccount, error) {
    var rows []entity.UserBridgeAccount
    err := r.db.WithContext(ctx).Where("user_id = ?", userID).Find(&rows).Error
    return rows, err
}

func (r *Repo) CreatePairing(ctx context.Context, p *entity.BridgePairing) error {
    return r.db.WithContext(ctx).Create(p).Error
}

func (r *Repo) GetPairingByPairingID(ctx context.Context, pairingID string) (*entity.BridgePairing, error) {
    var p entity.BridgePairing
    if err := r.db.WithContext(ctx).Where("pairing_id = ?", pairingID).First(&p).Error; err != nil {
        return nil, err
    }
    return &p, nil
}

func (r *Repo) UpsertAccount(ctx context.Context, a *entity.UserBridgeAccount) error {
    return r.db.WithContext(ctx).Save(a).Error
}

func (r *Repo) DeleteAccountsForUserProvider(ctx context.Context, userID, providerID uuid.UUID) error {
    return r.db.WithContext(ctx).Where("user_id = ? AND provider_id = ?", userID, providerID).Delete(&entity.UserBridgeAccount{}).Error
}

func (r *Repo) GetEffectiveLimit(ctx context.Context, userID uuid.UUID, providerID *uuid.UUID, key string, defaultValue int64) (int64, error) {
    // 1) User override (provider-specific)
    var o entity.UserPlanOverride
    if providerID != nil {
        if err := r.db.WithContext(ctx).Where("user_id = ? AND provider_id = ? AND limit_key = ?", userID, *providerID, key).First(&o).Error; err == nil {
            return o.Value, nil
        }
    }
    // 2) User override (global)
    if err := r.db.WithContext(ctx).Where("user_id = ? AND provider_id IS NULL AND limit_key = ?", userID, key).First(&o).Error; err == nil {
        return o.Value, nil
    }
    // 3) Plan limits
    var up entity.UserPlan
    if err := r.db.WithContext(ctx).Where("user_id = ?", userID).First(&up).Error; err == nil {
        var pl entity.PlanLimit
        if providerID != nil {
            if err := r.db.WithContext(ctx).Where("plan_id = ? AND provider_id = ? AND limit_key = ?", up.PlanID, *providerID, key).First(&pl).Error; err == nil {
                return pl.Value, nil
            }
        }
        if err := r.db.WithContext(ctx).Where("plan_id = ? AND provider_id IS NULL AND limit_key = ?", up.PlanID, key).First(&pl).Error; err == nil {
            return pl.Value, nil
        }
    }
    return defaultValue, nil
}
