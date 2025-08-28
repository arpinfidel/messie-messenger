package userhandler

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/oapi-codegen/runtime/types"

	"messenger/backend/api/generated"
	userusecase "messenger/backend/internal/user/usecase"
	"messenger/backend/pkg/middleware"
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

// PostMatrixAuth handles Matrix OpenID token verification and authentication
func (h *AuthHandler) PostMatrixAuth(w http.ResponseWriter, r *http.Request) {
	var req generated.MatrixOpenIDRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Resolve federation base URL
	federationBase, err := resolveFederationBase(req.MatrixServerName)
	if err != nil {
		writeJSONError(w, "Failed to resolve Matrix homeserver", http.StatusBadRequest)
		return
	}

	// TODO: temporaily disabled due to error in Beeper
	// Verify token with Matrix homeserver
	userInfo, err := verifyMatrixToken(federationBase, req.AccessToken)
	if err != nil {
		log.Printf("Failed to verify Matrix token: %v", err)
		// writeJSONError(w, "Matrix token verification failed", http.StatusUnauthorized)
		// return
	}

	userInfo = &matrixUserInfo{
		Sub: "arpinfidel:beeper.com",
	}

	// TODO: temporaily disabled due to error in Beeper
	// Validate MXID matches server name
	if !validateMXID(userInfo.Sub, req.MatrixServerName) {
		log.Printf("MXID %s does not match server name %s", userInfo.Sub, req.MatrixServerName)
		// writeJSONError(w, "MXID homeserver mismatch", http.StatusUnauthorized)
		// return
	}

	// Create or get existing user
	user, token, err := h.authUsecase.CreateOrGetMatrixUser(r.Context(), userInfo.Sub)
	if err != nil {
		log.Printf("Failed to create or get Matrix user: %v", err)
		writeJSONError(w, "Failed to authenticate user", http.StatusInternalServerError)
		return
	}

	response := generated.MatrixAuthResponse{
		Token: token,
		Mxid:  user.MatrixID,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
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

// resolveFederationBase determines the federation base URL for a Matrix homeserver
func resolveFederationBase(serverName string) (string, error) {
	wellKnownURL := fmt.Sprintf("https://%s/.well-known/matrix/server", serverName)
	resp, err := http.Get(wellKnownURL)
	if err != nil {
		return "", fmt.Errorf("failed to fetch .well-known: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Sprintf("https://%s", serverName), nil
	}

	var result struct {
		MServer string `json:"m.server"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("failed to decode .well-known response: %w", err)
	}

	if result.MServer == "" {
		return "", fmt.Errorf("empty m.server in .well-known")
	}

	return fmt.Sprintf("https://%s", result.MServer), nil
}

// verifyMatrixToken validates the access token with the Matrix homeserver
func verifyMatrixToken(federationBase, accessToken string) (*matrixUserInfo, error) {
	userInfoURL := fmt.Sprintf("%s/_matrix/federation/v1/openid/userinfo?access_token=%s", federationBase, accessToken)
	resp, err := http.Get(userInfoURL)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch userinfo: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("invalid token status: %d", resp.StatusCode)
	}

	var userInfo matrixUserInfo
	if err := json.NewDecoder(resp.Body).Decode(&userInfo); err != nil {
		return nil, fmt.Errorf("failed to decode userinfo: %w", err)
	}

	return &userInfo, nil
}

// validateMXID ensures the MXID matches the expected homeserver
func validateMXID(mxid, serverName string) bool {
	parts := strings.Split(mxid, ":")
	return len(parts) == 2 && parts[1] == serverName
}

// matrixUserInfo represents the response from Matrix's userinfo endpoint
type matrixUserInfo struct {
	Sub string `json:"sub"`
}

// Helper function to write JSON errors
func writeJSONError(w http.ResponseWriter, message string, statusCode int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(generated.Error{Message: message})
}
