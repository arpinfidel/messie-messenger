package database

import (
	"fmt"
	"log"
	"os"

	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq" // PostgreSQL driver
)

var DB *sqlx.DB

func InitDB() (*sqlx.DB, error) {
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL environment variable not set")
	}

	var err error
	DB, err = sqlx.Connect("postgres", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	if err = DB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	if err = CreateTables(); err != nil {
		return nil, err
	}

	log.Println("Successfully connected to the database!")
	return DB, nil
}

func CreateTables() error {
	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id UUID PRIMARY KEY,
		email VARCHAR(255) NOT NULL UNIQUE,
		username VARCHAR(255) NOT NULL UNIQUE,
		password_hash VARCHAR(255) NOT NULL,
		created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS todo_lists (
		id UUID PRIMARY KEY,
		owner_id UUID NOT NULL,
		
		title VARCHAR(255) NOT NULL,
		description TEXT,
		
		created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS todo_items (
		id UUID PRIMARY KEY,
		list_id UUID NOT NULL REFERENCES todo_lists(id) ON DELETE CASCADE,
		
		description TEXT NOT NULL,
		deadline TIMESTAMP WITH TIME ZONE,
		completed BOOLEAN DEFAULT FALSE,
		
		created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS todo_list_collaborators (
		todo_list_id UUID NOT NULL REFERENCES todo_lists(id) ON DELETE CASCADE,
		collaborator_id UUID NOT NULL,
		
		created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
		
		PRIMARY KEY (todo_list_id, collaborator_id)
	);`

	_, err := DB.Exec(schema)
	if err != nil {
		return fmt.Errorf("failed to create tables: %w", err)
	}

	log.Println("Todo service tables created or already exist.")
	return nil
}
