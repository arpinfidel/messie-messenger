package userusecase

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	userentity "messenger/backend/todo-service/internal/user/entity"
	userrepository "messenger/backend/todo-service/internal/user/repository"
	"messenger/backend/todo-service/pkg/auth"
)

type AuthUsecase interface {
	CreateUser(ctx context.Context, email, password string) (*userentity.User, string, error)
	LoginUser(ctx context.Context, email, password string) (*userentity.User, string, error)
	GetUserByID(ctx context.Context, id uuid.UUID) (*userentity.User, error)
	GetUserByEmail(ctx context.Context, email string) (*userentity.User, error)
}

type authUsecase struct {
	userRepo   userrepository.UserRepository
	jwtService auth.JWTService
}

func NewAuthUsecase(userRepo userrepository.UserRepository, jwtService auth.JWTService) AuthUsecase {
	return &authUsecase{userRepo: userRepo, jwtService: jwtService}
}

func (uc *authUsecase) CreateUser(ctx context.Context, email, password string) (*userentity.User, string, error) {
	existingUser, err := uc.userRepo.GetUserByEmail(ctx, email)
	if err != nil {
		return nil, "", fmt.Errorf("failed to check for existing user: %w", err)
	}
	if existingUser != nil {
		return nil, "", fmt.Errorf("user with email %s already exists", email)
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, "", fmt.Errorf("failed to hash password: %w", err)
	}

	user := &userentity.User{
		ID:           uuid.New(),
		Email:        email,
		PasswordHash: string(hashedPassword),
		CreatedAt:    time.Now().UTC(),
		UpdatedAt:    time.Now().UTC(),
	}

	if err := uc.userRepo.CreateUser(ctx, user); err != nil {
		return nil, "", fmt.Errorf("failed to create user in repository: %w", err)
	}

	token, err := uc.jwtService.GenerateToken(user.ID.String())
	if err != nil {
		return nil, "", fmt.Errorf("failed to generate JWT token: %w", err)
	}

	return user, token, nil
}

func (uc *authUsecase) LoginUser(ctx context.Context, email, password string) (*userentity.User, string, error) {
	user, err := uc.userRepo.GetUserByEmail(ctx, email)
	if err != nil {
		return nil, "", fmt.Errorf("failed to get user by email: %w", err)
	}
	if user == nil {
		return nil, "", fmt.Errorf("user not found")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return nil, "", fmt.Errorf("invalid credentials")
	}

	token, err := uc.jwtService.GenerateToken(user.ID.String())
	if err != nil {
		return nil, "", fmt.Errorf("failed to generate JWT token: %w", err)
	}

	return user, token, nil
}

func (uc *authUsecase) GetUserByID(ctx context.Context, id uuid.UUID) (*userentity.User, error) {
	user, err := uc.userRepo.GetUserByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("failed to get user by ID: %w", err)
	}
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	return user, nil
}

func (uc *authUsecase) GetUserByEmail(ctx context.Context, email string) (*userentity.User, error) {
	user, err := uc.userRepo.GetUserByEmail(ctx, email)
	if err != nil {
		return nil, fmt.Errorf("failed to get user by email: %w", err)
	}
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	return user, nil
}
