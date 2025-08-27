package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"messenger/backend/todo-service/api/generated"
	"net/http"

	"github.com/golang-jwt/jwt/v5"
)

type contextKey string

const (
	ContextKeyUserID contextKey = "userID"
)

// JWTService defines the interface for JWT token validation.
type JWTService interface {
	ValidateToken(tokenString string) (*jwt.Token, error)
}

// AuthMiddleware extracts and validates the JWT token from the Authorization header.
func AuthMiddleware(jwtService JWTService) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if _, ok := r.Context().Value(generated.BearerAuthScopes).([]string); !ok {
				next.ServeHTTP(w, r)
				return
			}

			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				writeJSONError(w, "Authorization header required", http.StatusUnauthorized)
				return
			}

			tokenString := ""
			if len(authHeader) > 7 && authHeader[:7] == "Bearer " {
				tokenString = authHeader[7:]
			} else {
				writeJSONError(w, "Invalid Authorization header format", http.StatusUnauthorized)
				return
			}

			claims, err := jwtService.ValidateToken(tokenString)
			if err != nil {
				writeJSONError(w, fmt.Sprintf("Invalid or expired token: %v", err), http.StatusUnauthorized)
				return
			}

			// Add UserID to context
			claimsMap, ok := claims.Claims.(jwt.MapClaims)
			if !ok {
				writeJSONError(w, "Invalid token claims", http.StatusUnauthorized)
				return
			}
			userID, ok := claimsMap["user_id"].(string)
			if !ok {
				writeJSONError(w, "User ID not found in token claims", http.StatusUnauthorized)
				return
			}
			ctx := context.WithValue(r.Context(), ContextKeyUserID, userID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// Helper function to write JSON errors
func writeJSONError(w http.ResponseWriter, message string, statusCode int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(generated.Error{Message: message})
}
