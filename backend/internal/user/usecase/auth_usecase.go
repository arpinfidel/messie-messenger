package userusecase

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	userentity "messenger/backend/internal/user/entity"
	userrepository "messenger/backend/internal/user/repository"
	"messenger/backend/pkg/auth"
)

type AuthUsecase interface {
	GetUserByMatrixID(ctx context.Context, mxid string) (*userentity.User, error)
	CreateOrGetMatrixUser(ctx context.Context, mxid string) (*userentity.User, string, error)
}

type authUsecase struct {
	userRepo   userrepository.UserRepository
	jwtService auth.JWTService
}

func NewAuthUsecase(userRepo userrepository.UserRepository, jwtService auth.JWTService) AuthUsecase {
	return &authUsecase{userRepo: userRepo, jwtService: jwtService}
}

func (uc *authUsecase) GetUserByMatrixID(ctx context.Context, mxid string) (*userentity.User, error) {
	user, err := uc.userRepo.GetUserByMatrixID(ctx, mxid)
	if err != nil {
		return nil, fmt.Errorf("failed to get user by Matrix ID: %w", err)
	}
	if user == nil {
		return nil, fmt.Errorf("user not found")
	}
	return user, nil
}

func (uc *authUsecase) CreateOrGetMatrixUser(ctx context.Context, mxid string) (*userentity.User, string, error) {
	// Check for existing Matrix user
	user, err := uc.userRepo.GetUserByMatrixID(ctx, mxid)
	if err != nil && !errors.Is(err, userentity.ErrNotFound) {
		return nil, "", fmt.Errorf("failed to check for existing Matrix user: %w", err)
	}

	// Return existing user with new token
	if user != nil {
		token, err := uc.jwtService.GenerateToken(user.ID.String())
		if err != nil {
			return nil, "", fmt.Errorf("failed to generate token: %w", err)
		}
		return user, token, nil
	}

	// Create new Matrix user
	newUser := &userentity.User{
		ID:        uuid.New(),
		MatrixID:  mxid,
		Email:     matrixUserEmail(mxid),
		CreatedAt: time.Now().UTC(),
		UpdatedAt: time.Now().UTC(),
	}

	if err := uc.userRepo.CreateUser(ctx, newUser); err != nil {
		return nil, "", fmt.Errorf("failed to create Matrix user: %w", err)
	}

	token, err := uc.jwtService.GenerateToken(newUser.ID.String())
	if err != nil {
		return nil, "", fmt.Errorf("failed to generate token: %w", err)
	}

	return newUser, token, nil
}

func matrixUserEmail(mxid string) string {
	local := strings.TrimPrefix(mxid, "@")
	local = strings.ReplaceAll(local, ":", ".")
	local = strings.ReplaceAll(local, "/", ".")
	local = strings.ReplaceAll(local, "+", ".")
	if local == "" {
		local = "matrix-user"
	}
	return local + "@matrix.local"
}
