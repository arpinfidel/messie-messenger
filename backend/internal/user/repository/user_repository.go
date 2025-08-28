package userrepository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	userentity "messenger/backend/internal/user/entity"
)

// UserRepository defines the interface for user data operations.
type UserRepository interface {
	CreateUser(ctx context.Context, user *userentity.User) error
	GetUserByID(ctx context.Context, id uuid.UUID) (*userentity.User, error)
	GetUserByEmail(ctx context.Context, email string) (*userentity.User, error)
	GetUserByMatrixID(ctx context.Context, mxid string) (*userentity.User, error)
}

// postgresUserRepository implements UserRepository using PostgreSQL and sqlx.
type postgresUserRepository struct {
	db *sqlx.DB
}

// NewPostgresUserRepository creates a new instance of postgresUserRepository.
func NewPostgresUserRepository(db *sqlx.DB) UserRepository {
	return &postgresUserRepository{db: db}
}

// GetUserByMatrixID implements UserRepository.
func (r *postgresUserRepository) GetUserByMatrixID(ctx context.Context, mxid string) (*userentity.User, error) {
	var user userentity.User
	query := `SELECT id, email, matrix_id, password_hash, created_at, updated_at FROM users WHERE matrix_id = $1`
	err := r.db.GetContext(ctx, &user, query, mxid)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to get user by Matrix ID: %w", err)
	}
	return &user, nil
}

// CreateUser inserts a new user into the database.
func (r *postgresUserRepository) CreateUser(ctx context.Context, user *userentity.User) error {
	query := `
		INSERT INTO users (id, email, username, matrix_id, password_hash, created_at, updated_at)
		VALUES (:id, :email, :username, :matrix_id, :password_hash, :created_at, :updated_at)
	`
	// Use existing ID from usecase layer
	user.CreatedAt = time.Now().UTC()
	user.UpdatedAt = time.Now().UTC()

	_, err := r.db.NamedExecContext(ctx, query, user)
	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}
	return nil
}

// GetUserByID retrieves a user by their ID.
func (r *postgresUserRepository) GetUserByID(ctx context.Context, id uuid.UUID) (*userentity.User, error) {
	var user userentity.User
	query := `SELECT id, email, matrix_id, password_hash, created_at, updated_at FROM users WHERE id = $1`
	err := r.db.GetContext(ctx, &user, query, id)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // User not found
		}
		return nil, fmt.Errorf("failed to get user by ID: %w", err)
	}
	return &user, nil
}

// GetUserByEmail retrieves a user by their email address.
func (r *postgresUserRepository) GetUserByEmail(ctx context.Context, email string) (*userentity.User, error) {
	var user userentity.User
	query := `SELECT id, email, matrix_id, password_hash, created_at, updated_at FROM users WHERE email = $1`
	err := r.db.GetContext(ctx, &user, query, email)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // User not found
		}
		return nil, fmt.Errorf("failed to get user by email: %w", err)
	}
	return &user, nil
}
