package userhandler

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/mail"
	"os"
	"strings"

	"github.com/oapi-codegen/runtime/types"

	"messenger/backend/api/generated"
	userentity "messenger/backend/internal/user/entity"
	userusecase "messenger/backend/internal/user/usecase"
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

func userToResponse(user *userentity.User) generated.User {
	return generated.User{
		Id:        user.ID,
		Email:     types.Email(sanitizeUserEmail(user.Email, user.MatrixID)),
		MatrixId:  user.MatrixID,
		CreatedAt: &user.CreatedAt,
		UpdatedAt: &user.UpdatedAt,
	}
}

func sanitizeUserEmail(email, matrixID string) string {
	if _, err := mail.ParseAddress(email); err == nil {
		return email
	}

	local := strings.TrimPrefix(matrixID, "@")
	local = strings.ReplaceAll(local, ":", ".")
	local = strings.ReplaceAll(local, "/", ".")
	local = strings.ReplaceAll(local, "+", ".")
	if local == "" {
		local = "matrix-user"
	}
	return local + "@matrix.local"
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

	// Verify token with Matrix homeserver
	userInfo, err := verifyMatrixToken(federationBase, req.AccessToken)
	if err != nil {
		log.Printf("Failed to verify Matrix token: %v", err)
		writeJSONError(w, "Matrix token verification failed", http.StatusUnauthorized)
		return
	}

	// Validate MXID matches server name
	if !validateMXID(userInfo.Sub, req.MatrixServerName) {
		log.Printf("MXID %s does not match server name %s", userInfo.Sub, req.MatrixServerName)
		writeJSONError(w, "MXID homeserver mismatch", http.StatusUnauthorized)
		return
	}

	// Create or get existing user
	user, token, err := h.authUsecase.CreateOrGetMatrixUser(r.Context(), userInfo.Sub)
	if err != nil {
		log.Printf("Failed to create or get Matrix user: %v", err)
		writeJSONError(w, "Failed to authenticate user", http.StatusInternalServerError)
		return
	}

	response := generated.MatrixAuthResponse{
		Token:  token,
		Mxid:   user.MatrixID,
		UserId: user.ID,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// GetUserByMatrixId handles getting a user by Matrix ID.
func (h *AuthHandler) GetUserByMatrixId(
	w http.ResponseWriter,
	r *http.Request,
	params generated.GetUserByMatrixIdParams,
) {
	user, err := h.authUsecase.GetUserByMatrixID(r.Context(), params.MatrixId)
	if err != nil {
		log.Printf("Error getting user by Matrix ID: %v", err)
		http.Error(w, generated.Error{Message: err.Error()}.Message, http.StatusNotFound)
		return
	}

	res := userToResponse(user)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(res)
}

// resolveFederationBase determines the federation base URL for a Matrix homeserver
func resolveFederationBase(serverName string) (string, error) {
	// Dev override: allow targeting a known homeserver inside docker-compose
	if devSrv := os.Getenv("DEV_MATRIX_SERVER_NAME"); devSrv != "" && serverName == devSrv {
		if base := os.Getenv("DEV_MATRIX_FED_BASE"); base != "" {
			return base, nil
		}
		return "http://matrix:8008", nil
	}
	// Heuristic: local dev domains
	if strings.HasSuffix(serverName, ".localhost") {
		if base := os.Getenv("DEV_MATRIX_FED_BASE"); base != "" {
			return base, nil
		}
		return "http://matrix:8008", nil
	}
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
