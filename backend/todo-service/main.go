package main

import (
	"log"
	"net/http"
	"os"

	"messenger/backend/todo-service/api/generated"
	"messenger/backend/todo-service/pkg/auth"
	"messenger/backend/todo-service/pkg/database"
	middlewarePkg "messenger/backend/todo-service/pkg/middleware"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	// Added for uuid.Parse
	"messenger/backend/todo-service/internal/todo/repository"
	"messenger/backend/todo-service/internal/todo/todohandler"
	"messenger/backend/todo-service/internal/todo/usecase"
	authHandler "messenger/backend/todo-service/internal/user/handler"
	userRepo "messenger/backend/todo-service/internal/user/repository"
	authUsecase "messenger/backend/todo-service/internal/user/usecase"
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

	r.Mount("/", h)
	// // versioned API router
	// api := chi.NewRouter()

	// // --- Protected (with auth) ---
	// api.Group(func(pr chi.Router) {
	// 	pr.Use(middlewarePkg.AuthMiddleware(jwtService))

	// 	todoHandler.RegisterRoutes(pr)

	// 	pr.Get("/users/{id}", func(w http.ResponseWriter, r *http.Request) {
	// 		idStr := chi.URLParam(r, "id")
	// 		id, err := uuid.Parse(idStr)
	// 		if err != nil {
	// 			http.Error(w, "Invalid user ID format", http.StatusBadRequest)
	// 			return
	// 		}
	// 		authHandler.GetUserById(w, r, id)
	// 	})
	// 	pr.Get("/users/me", authHandler.GetUsersMe)

	// 	// Mount todo routes here so they're protected
	// })

	// // --- Public (no auth) ---
	// api.Post("/register", authHandler.RegisterUser)
	// api.Post("/login", authHandler.LoginUser)

	// r.Mount("/", api)

	// Start HTTP server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080" // Default port
	}
	log.Printf("Todo Service starting on port %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
