package main

import (
	"log"
	"net/http"
	"os"

	"messenger/backend/api/generated"
	"messenger/backend/pkg/auth"
	"messenger/backend/pkg/database"
	middlewarePkg "messenger/backend/pkg/middleware"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	// Added for uuid.Parse
	"messenger/backend/internal/todo/repository"
	"messenger/backend/internal/todo/todohandler"
	"messenger/backend/internal/todo/usecase"
	authHandler "messenger/backend/internal/user/handler"
	userRepo "messenger/backend/internal/user/repository"
	authUsecase "messenger/backend/internal/user/usecase"
)

func main() {
	// Initialize database connection
	db, err := database.InitDB()
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// Initialize JWT Service
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Fatal("JWT_SECRET environment variable not set")
	}
	jwtService := auth.NewJWTService(jwtSecret) // Token valid for 24 hours

	// Initialize User Repository
	userRepository := userRepo.NewPostgresUserRepository(db)

	// Initialize Auth Usecase
	authUsecase := authUsecase.NewAuthUsecase(userRepository, jwtService)

	// Initialize Auth Handler
	authH := authHandler.NewAuthHandler(authUsecase)

	// Initialize repositories for todo service
	todoListRepository := repository.NewTodoListRepository(db)
	todoItemRepository := repository.NewTodoItemRepository(db)
	todoListCollaboratorRepository := repository.NewTodoListCollaboratorRepository(db)

	// Initialize usecases for todo service
	todoUsecase := usecase.NewUsecase(
		todoListRepository,
		todoItemRepository,
		todoListCollaboratorRepository,
	)

	// Initialize handler for todo service
	todoH := todohandler.NewHandler(todoUsecase)

	handlers := struct {
		*authHandler.AuthHandler
		*todohandler.TodoHandler
	}{
		AuthHandler: authH,
		TodoHandler: todoH,
	}

	// Setup Chi router
	r := chi.NewRouter()
	r.Use(middleware.Logger, middleware.Recoverer)

	h := generated.HandlerWithOptions(handlers, generated.ChiServerOptions{
		BaseRouter: r,
		Middlewares: []generated.MiddlewareFunc{
			middlewarePkg.AuthMiddleware(jwtService),
		},
	})

	r.Mount("/api/v1", h)

	// Start HTTP server
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080" // Default port
	}
	log.Printf("Todo Service starting on port %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
