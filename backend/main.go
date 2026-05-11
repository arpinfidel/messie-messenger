package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"

	"messenger/backend/api/generated"
	calendarEntity "messenger/backend/internal/calendar/entity"
	calendarHandler "messenger/backend/internal/calendar/handler"
	calendarRepo "messenger/backend/internal/calendar/repository"
	calendarUsecase "messenger/backend/internal/calendar/usecase"
	"messenger/backend/pkg/auth"
	middlewarePkg "messenger/backend/pkg/middleware"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/google/uuid"

	bridgeEntity "messenger/backend/internal/bridge/entity"
	bridgeRepo "messenger/backend/internal/bridge/repository"
	emailHandler "messenger/backend/internal/email/handler"
	todoEntity "messenger/backend/internal/todo/entity"
	"messenger/backend/internal/todo/repository"
	"messenger/backend/internal/todo/todohandler"
	"messenger/backend/internal/todo/usecase"
	userEntity "messenger/backend/internal/user/entity"
	authHandler "messenger/backend/internal/user/handler"
	userRepo "messenger/backend/internal/user/repository"
	authUsecase "messenger/backend/internal/user/usecase"
	waHandler "messenger/backend/internal/wa/handler"
	waProvider "messenger/backend/internal/wa/provider"
	waRoomMap "messenger/backend/internal/wa/roommap"
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
	err = db.AutoMigrate(
		&todoEntity.TodoList{},
		&todoEntity.TodoItem{},
		&todoEntity.TodoListCollaborator{},
		&userEntity.User{},
		&calendarEntity.CalendarSource{},
		&calendarEntity.CalendarEvent{},
	)
	if err != nil {
		log.Fatalf("Failed to auto-migrate GORM models: %v", err)
	}
	if err := calendarRepo.EnsureCalendarSourceCategoryConstraint(db); err != nil {
		log.Fatalf("Failed to enforce calendar source category constraint: %v", err)
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

	log.Printf("Initializing Calendar Repositories...")
	calendarSourceRepository := calendarRepo.NewCalendarSourceRepository(db)
	calendarEventRepository := calendarRepo.NewCalendarEventRepository(db)
	log.Printf("Calendar Repositories initialized.")

	log.Printf("Initializing Calendar Usecase...")
	calendarUC := calendarUsecase.NewUsecase(
		calendarSourceRepository,
		calendarEventRepository,
		calendarUsecase.NewCalendarICSParser(),
	)
	log.Printf("Calendar Usecase initialized.")

	log.Printf("Initializing Calendar Handler...")
	calendarH := calendarHandler.NewCalendarHandler(calendarUC)
	log.Printf("Calendar Handler initialized.")

	calendarSyncCoordinator := &calendarUsecase.SyncCoordinator{
		Usecase:  calendarUC,
		Interval: time.Minute,
		Limit:    25,
		Logger:   log.Default(),
	}

	// Initialize Email Handler
	log.Printf("Initializing Email Handler...")
	emailH := emailHandler.NewEmailHandler()
	log.Printf("Email Handler initialized.")

	// AutoMigrate bridge-related models
	log.Printf("Auto-migrating bridge models...")
	if err := db.AutoMigrate(&bridgeEntity.Provider{}, &bridgeEntity.UserBridgeAccount{}, &bridgeEntity.BridgePairing{}, &bridgeEntity.Plan{}, &bridgeEntity.PlanLimit{}, &bridgeEntity.UserPlanOverride{}, &bridgeEntity.UsageCounter{}, &bridgeEntity.UserPlan{}); err != nil {
		log.Fatalf("Failed to auto-migrate bridge models: %v", err)
	}
	log.Printf("Bridge models migrated.")

	// Ensure WA provider exists
	brepo := bridgeRepo.NewRepo(db)
	waProv, err := brepo.EnsureProvider(context.Background(), "whatsapp", "WhatsApp")
	if err != nil {
		log.Fatalf("Failed to ensure WA provider: %v", err)
	}

	// Seed default plan and limits (dev defaults): free plan with WA max_accounts=1
	if err := seedDefaultPlans(db, waProv.ID); err != nil {
		log.Fatalf("Failed to seed default plans: %v", err)
	}

	// Configure WA provider adapter from env (with sane defaults for dev)
	waBaseURL := os.Getenv("WA_BRIDGE_BASE_URL")
	if waBaseURL == "" {
		waBaseURL = "http://mautrix-whatsapp:29319"
	}
	waSecret := os.Getenv("WA_BRIDGE_SHARED_SECRET") // must match bridge provisioning.shared_secret
	if waSecret == "" {
		log.Printf("WARNING: WA_BRIDGE_SHARED_SECRET is empty; WA adapter will not authenticate against provisioning API.")
	}
	waAdapter := waProvider.New(waBaseURL, waSecret)
	waBridgeDBPath := os.Getenv("WA_BRIDGE_DB_PATH")
	if waBridgeDBPath == "" {
		waBridgeDBPath = "/bridge-data/mautrix-whatsapp.db"
	}
	waRoomMapRepo := waRoomMap.NewRepository(waBridgeDBPath)

	handlers := struct {
		*authHandler.AuthHandler
		*calendarHandler.CalendarHandler
		*todohandler.TodoHandler
		*emailHandler.EmailHandler
		*waHandler.WAHandler
	}{
		AuthHandler:     authH,
		CalendarHandler: calendarH,
		TodoHandler:     todoH,
		EmailHandler:    emailH,
		WAHandler:       waHandler.NewWAHandler(brepo, waAdapter, waRoomMapRepo, waProv.ID, userRepository),
	}

	// Setup Chi router
	log.Printf("Setting up Chi router...")
	r := chi.NewRouter()
	r.Use(middleware.Logger, middleware.Recoverer)
	log.Printf("Chi router setup complete.")

	log.Printf("Registering API routes...")
	// ALL APIs must be generated from the OpenAPI spec
	h := generated.HandlerWithOptions(handlers, generated.ChiServerOptions{
		BaseRouter: r,
		Middlewares: []generated.MiddlewareFunc{
			middlewarePkg.AuthMiddleware(jwtService),
		},
	})

	r.Mount("/api/v1", h)
	log.Printf("API routes registered at /api/v1.")

	// Provisioning endpoints are defined in docs/openapi.yaml.
	// Ensure 'make gen-be' is run to mount them through the generated router.

	// Start HTTP server
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	// Convenience: expose health under /api/v1 for mobile clients using the API base path
	r.Get("/api/v1/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080" // Default port
	}
	calendarSyncCoordinator.Start(context.Background())
	log.Printf("Todo Service starting on port %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// seedDefaultPlans ensures a default "free" plan exists with WA max_accounts=1
func seedDefaultPlans(db *gorm.DB, waProviderID uuid.UUID) error {
	// ensure free plan
	var plan bridgeEntity.Plan
	if err := db.Where("key = ?", "free").First(&plan).Error; err != nil {
		plan = bridgeEntity.Plan{Key: "free", Name: "Free"}
		if err := db.Create(&plan).Error; err != nil {
			return err
		}
	}
	// ensure plan limit for WA max_accounts=1
	var pl bridgeEntity.PlanLimit
	if err := db.Where("plan_id = ? AND provider_id = ? AND limit_key = ?", plan.ID, waProviderID, "max_accounts").First(&pl).Error; err != nil {
		pl = bridgeEntity.PlanLimit{PlanID: plan.ID, ProviderID: &waProviderID, LimitKey: "max_accounts", Value: 1}
		if err := db.Create(&pl).Error; err != nil {
			return err
		}
	}
	return nil
}
