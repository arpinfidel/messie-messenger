package repository

import (
	"context"
	"fmt"
	"time"

	"messenger/backend/internal/todo/entity"

	"github.com/jmoiron/sqlx"
)

type todoItemRepository struct {
	db *sqlx.DB
}

func NewTodoItemRepository(db *sqlx.DB) TodoItemRepository {
	return &todoItemRepository{db: db}
}

func (r *todoItemRepository) CreateTodoItem(ctx context.Context, todoItem *entity.TodoItem) error {
	query := `
		INSERT INTO todo_items (list_id, description, deadline, completed, position, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id`

	todoItem.CreatedAt = time.Now()
	todoItem.UpdatedAt = time.Now()

	err := r.db.QueryRowContext(ctx, query, todoItem.ListID, todoItem.Description, todoItem.Deadline, todoItem.Completed, todoItem.Position, todoItem.CreatedAt, todoItem.UpdatedAt).Scan(&todoItem.ID)
	if err != nil {
		return fmt.Errorf("failed to create todo item: %w", err)
	}
	return nil
}

func (r *todoItemRepository) GetTodoItemByID(ctx context.Context, id string) (*entity.TodoItem, error) {
	var todoItem entity.TodoItem
	query := `SELECT id, list_id, description, deadline, completed, created_at, updated_at FROM todo_items WHERE id = $1`
	err := r.db.GetContext(ctx, &todoItem, query, id)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo item by ID: %w", err)
	}
	return &todoItem, nil
}

func (r *todoItemRepository) GetTodoItemsByListID(ctx context.Context, listID string) ([]entity.TodoItem, error) {
	var todoItems []entity.TodoItem
	query := `SELECT id, list_id, description, deadline, completed, created_at, updated_at FROM todo_items WHERE list_id = $1`
	err := r.db.SelectContext(ctx, &todoItems, query, listID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo items by list ID: %w", err)
	}
	return todoItems, nil
}

func (r *todoItemRepository) UpdateTodoItem(ctx context.Context, todoItem *entity.TodoItem) error {
	query := `
		UPDATE todo_items
		SET description = $1, deadline = $2, completed = $3, updated_at = $4
		WHERE id = $5`

	todoItem.UpdatedAt = time.Now()

	_, err := r.db.ExecContext(ctx, query, todoItem.Description, todoItem.Deadline, todoItem.Completed, todoItem.UpdatedAt, todoItem.ID)
	if err != nil {
		return fmt.Errorf("failed to update todo item: %w", err)
	}
	return nil
}

func (r *todoItemRepository) DeleteTodoItem(ctx context.Context, id string) error {
	query := `DELETE FROM todo_items WHERE id = $1`
	_, err := r.db.ExecContext(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to delete todo item: %w", err)
	}
	return nil
}
