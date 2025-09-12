package main

import (
	"log"
	"net/http"
	"os"

	"messenger/backend/api/generated"
	"messenger/backend/pkg/auth"
	middlewarePkg "messenger/backend/pkg/middleware"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	// Added for uuid.Parse

	emailHandler "messenger/backend/internal/email/handler"
	todoEntity "messenger/backend/internal/todo/entity"
	"messenger/backend/internal/todo/repository"
	"messenger/backend/internal/todo/todohandler"
	"messenger/backend/internal/todo/usecase"
	userEntity "messenger/backend/internal/user/entity"
	authHandler "messenger/backend/internal/user/handler"
	userRepo "messenger/backend/internal/user/repository"
	authUsecase "messenger/backend/internal/user/usecase"
)

func main() {
	log.Printf("Starting backend service initialization...")

	// Initialize GORM database connection
	log.Printf("Initializing GORM database connection...")
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL environment variable not set")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	log.Printf("GORM database connection initialized successfully.")

	// AutoMigrate GORM models
	log.Printf("Auto-migrating GORM models...")
	err = db.AutoMigrate(&todoEntity.TodoList{}, &todoEntity.TodoItem{}, &todoEntity.TodoListCollaborator{}, &userEntity.User{})
	if err != nil {
		log.Fatalf("Failed to auto-migrate GORM models: %v", err)
	}
	log.Printf("GORM models auto-migrated successfully.")

	// Initialize JWT Service
	log.Printf("Initializing JWT Service...")
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Fatal("JWT_SECRET environment variable not set")
	}
	jwtService := auth.NewJWTService(jwtSecret) // Token valid for 24 hours
	log.Printf("JWT Service initialized.")

	// Initialize User Repository
	log.Printf("Initializing User Repository...")
	userRepository := userRepo.NewPostgresUserRepository(db)
	log.Printf("User Repository initialized.")

	// Initialize Auth Usecase
	log.Printf("Initializing Auth Usecase...")
	authUsecase := authUsecase.NewAuthUsecase(userRepository, jwtService)
	log.Printf("Auth Usecase initialized.")

	// Initialize Auth Handler
	log.Printf("Initializing Auth Handler...")
	authH := authHandler.NewAuthHandler(authUsecase)
	log.Printf("Auth Handler initialized.")

	// Initialize repositories for todo service
	log.Printf("Initializing Todo Repositories...")
	todoListRepository := repository.NewTodoListRepository(db)
	todoItemRepository := repository.NewTodoItemRepository(db)
	todoListCollaboratorRepository := repository.NewTodoListCollaboratorRepository(db)
	log.Printf("Todo Repositories initialized.")

	// Initialize usecases for todo service
	log.Printf("Initializing Todo Usecase...")
	todoUsecase := usecase.NewUsecase(
		todoListRepository,
		todoItemRepository,
		todoListCollaboratorRepository,
	)
	log.Printf("Todo Usecase initialized.")

	// Initialize handler for todo service
	log.Printf("Initializing Todo Handler...")
	todoH := todohandler.NewHandler(todoUsecase)
	log.Printf("Todo Handler initialized.")

	// Initialize Email Handler
	log.Printf("Initializing Email Handler...")
	emailH := emailHandler.NewEmailHandler()
	log.Printf("Email Handler initialized.")

	handlers := struct {
		*authHandler.AuthHandler
		*todohandler.TodoHandler
		*emailHandler.EmailHandler
	}{
		AuthHandler:  authH,
		TodoHandler:  todoH,
		EmailHandler: emailH,
	}

	// Setup Chi router
	log.Printf("Setting up Chi router...")
	r := chi.NewRouter()
	r.Use(middleware.Logger, middleware.Recoverer)
	log.Printf("Chi router setup complete.")

	log.Printf("Registering API routes...")
	h := generated.HandlerWithOptions(handlers, generated.ChiServerOptions{
		BaseRouter: r,
		Middlewares: []generated.MiddlewareFunc{
			middlewarePkg.AuthMiddleware(jwtService),
		},
	})

	r.Mount("/api/v1", h)
	log.Printf("API routes registered at /api/v1.")

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
