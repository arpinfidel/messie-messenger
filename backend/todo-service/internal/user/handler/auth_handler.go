package userhandler

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/google/uuid"
	"github.com/oapi-codegen/runtime/types"

	"messenger/backend/todo-service/api/generated"
	userusecase "messenger/backend/todo-service/internal/user/usecase"
	middleware "messenger/backend/todo-service/pkg/middleware"
)

// AuthHandler implements the generated.ServerInterface.
type AuthHandler struct {
	authUsecase userusecase.AuthUsecase
}

// NewAuthHandler creates a new AuthHandler.
func NewAuthHandler(authUsecase userusecase.AuthUsecase) *AuthHandler {
	return &AuthHandler{
		authUsecase: authUsecase,
	}
}

// PostRegister handles user registration.
func (h *AuthHandler) PostRegister(w http.ResponseWriter, r *http.Request) {
	var req generated.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, generated.Error{Message: "Invalid request body"}.Message, http.StatusBadRequest)
		return
	}

	user, token, err := h.authUsecase.CreateUser(r.Context(), string(req.Email), req.Password)
	if err != nil {
		http.Error(w, generated.Error{Message: err.Error()}.Message, http.StatusConflict)
		return
	}

	res := generated.AuthResponse{
		User: generated.User{
			Id:        user.ID,
			Email:     types.Email(user.Email),
			CreatedAt: user.CreatedAt,
			UpdatedAt: user.UpdatedAt,
		},
		Token: token,
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(res)
}

// PostLogin handles user login.
func (h *AuthHandler) PostLogin(w http.ResponseWriter, r *http.Request) {
	var req generated.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, generated.Error{Message: "Invalid request body"}.Message, http.StatusBadRequest)
		return
	}

	user, token, err := h.authUsecase.LoginUser(r.Context(), string(req.Email), req.Password)
	if err != nil {
		http.Error(w, generated.Error{Message: err.Error()}.Message, http.StatusUnauthorized)
		return
	}

	res := generated.AuthResponse{
		User: generated.User{
			Id:        user.ID,
			Email:     types.Email(user.Email),
			CreatedAt: user.CreatedAt,
			UpdatedAt: user.UpdatedAt,
		},
		Token: token,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(res)
}

// GetUsersId handles getting a user by ID.
func (h *AuthHandler) GetUsersId(w http.ResponseWriter, r *http.Request, id uuid.UUID) {
	user, err := h.authUsecase.GetUserByID(r.Context(), id)
	if err != nil {
		log.Printf("Error getting user by ID: %v", err)
		http.Error(w, generated.Error{Message: err.Error()}.Message, http.StatusNotFound)
		return
	}

	res := generated.User{
		Id:        user.ID,
		Email:     types.Email(user.Email),
		CreatedAt: user.CreatedAt,
		UpdatedAt: user.UpdatedAt,
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(res)
}

// GetUsersMe handles getting the current user's profile.
func (h *AuthHandler) GetUsersMe(w http.ResponseWriter, r *http.Request) {
	log.Printf("Attempting to get current user profile")
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok {
		log.Printf("Error: User ID not found in context")
		writeJSONError(w, "User ID not found in context", http.StatusInternalServerError)
		return
	}
	log.Printf("User ID from context: %s", userID)

	userUUID, err := uuid.Parse(userID)
	if err != nil {
		log.Printf("Error: Invalid user ID format in context: %v", err)
		writeJSONError(w, "Invalid user ID format in context", http.StatusInternalServerError)
		return
	}
	log.Printf("Parsed User UUID: %s", userUUID)

	user, err := h.authUsecase.GetUserByID(r.Context(), userUUID)
	if err != nil {
		log.Printf("Error getting user by ID: %v", err)
		writeJSONError(w, err.Error(), http.StatusNotFound)
		return
	}
	log.Printf("User retrieved: %+v", user)

	res := generated.User{
		Id:        user.ID,
		Email:     types.Email(user.Email),
		CreatedAt: user.CreatedAt,
		UpdatedAt: user.UpdatedAt,
	}

	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(res); err != nil {
		log.Printf("Error encoding response: %v", err)
		writeJSONError(w, "Failed to encode response", http.StatusInternalServerError)
		return
	}
	log.Printf("Successfully returned user profile for ID: %s", userID)
}

// Helper function to write JSON errors
func writeJSONError(w http.ResponseWriter, message string, statusCode int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(generated.Error{Message: message})
}
