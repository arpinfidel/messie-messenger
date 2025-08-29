package userrepository

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"gorm.io/gorm"

	userentity "messenger/backend/internal/user/entity"
)

// UserRepository defines the interface for user data operations.
type UserRepository interface {
	CreateUser(ctx context.Context, user *userentity.User) error
	GetUserByID(ctx context.Context, id uuid.UUID) (*userentity.User, error)
	GetUserByEmail(ctx context.Context, email string) (*userentity.User, error)
	GetUserByMatrixID(ctx context.Context, mxid string) (*userentity.User, error)
	UpdateUser(ctx context.Context, user *userentity.User) error
	DeleteUser(ctx context.Context, id uuid.UUID) error
}

// postgresUserRepository implements UserRepository using PostgreSQL and GORM.
type postgresUserRepository struct {
	db *gorm.DB
}

// NewPostgresUserRepository creates a new instance of postgresUserRepository.
func NewPostgresUserRepository(db *gorm.DB) UserRepository {
	return &postgresUserRepository{db: db}
}

// GetUserByMatrixID implements UserRepository.
func (r *postgresUserRepository) GetUserByMatrixID(ctx context.Context, mxid string) (*userentity.User, error) {
	var user userentity.User
	err := r.db.WithContext(ctx).Where("matrix_id = ?", mxid).First(&user).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, userentity.ErrNotFound
		}
		return nil, fmt.Errorf("failed to get user by Matrix ID: %w", err)
	}
	return &user, nil
}

// CreateUser inserts a new user into the database.
func (r *postgresUserRepository) CreateUser(ctx context.Context, user *userentity.User) error {
	err := r.db.WithContext(ctx).Create(user).Error
	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}
	return nil
}

// GetUserByID retrieves a user by their ID.
func (r *postgresUserRepository) GetUserByID(ctx context.Context, id uuid.UUID) (*userentity.User, error) {
	var user userentity.User
	err := r.db.WithContext(ctx).First(&user, "id = ?", id).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, userentity.ErrNotFound
		}
		return nil, fmt.Errorf("failed to get user by ID: %w", err)
	}
	return &user, nil
}

// UpdateUser updates an existing user in the database.
func (r *postgresUserRepository) UpdateUser(ctx context.Context, user *userentity.User) error {
	err := r.db.WithContext(ctx).Save(user).Error
	if err != nil {
		return fmt.Errorf("failed to update user: %w", err)
	}
	return nil
}

// DeleteUser deletes a user from the database by ID.
func (r *postgresUserRepository) DeleteUser(ctx context.Context, id uuid.UUID) error {
	err := r.db.WithContext(ctx).Delete(&userentity.User{}, id).Error
	if err != nil {
		return fmt.Errorf("failed to delete user: %w", err)
	}
	return nil
}

// GetUserByEmail retrieves a user by their email address.
func (r *postgresUserRepository) GetUserByEmail(ctx context.Context, email string) (*userentity.User, error) {
	var user userentity.User
	err := r.db.WithContext(ctx).Where("email = ?", email).First(&user).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, userentity.ErrNotFound
		}
		return nil, fmt.Errorf("failed to get user by email: %w", err)
	}
	return &user, nil
}
