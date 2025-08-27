package repository

import (
	"context"
	"fmt"
	"time"

	"messenger/backend/todo-service/internal/todo/entity"

	"github.com/jmoiron/sqlx"
)

type TodoListRepository interface {
	CreateTodoList(ctx context.Context, todoList *entity.TodoList) error
	GetTodoListByID(ctx context.Context, id string) (*entity.TodoList, error)
	GetTodoListsByOwnerID(ctx context.Context, ownerID string) ([]entity.TodoList, error)
	GetTodoListsByUserID(ctx context.Context, userID string) ([]entity.TodoList, error)
	UpdateTodoList(ctx context.Context, todoList *entity.TodoList) error
	DeleteTodoList(ctx context.Context, id string) error
}

type todoListRepository struct {
	db *sqlx.DB
}

func NewTodoListRepository(db *sqlx.DB) TodoListRepository {
	return &todoListRepository{db: db}
}

func (r *todoListRepository) GetTodoListsByUserID(ctx context.Context, userID string) ([]entity.TodoList, error) {
	var todoLists []entity.TodoList
	query := `
		SELECT tl.id, tl.owner_id, tl.title, tl.description, tl.created_at, tl.updated_at
		FROM todo_lists tl
		LEFT JOIN todo_list_collaborators tlc ON tl.id = tlc.todo_list_id
		WHERE tl.owner_id = $1 OR tlc.user_id = $1
		GROUP BY tl.id
		ORDER BY tl.created_at DESC`
	err := r.db.SelectContext(ctx, &todoLists, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo lists by user ID: %w", err)
	}
	return todoLists, nil
}

func (r *todoListRepository) CreateTodoList(ctx context.Context, todoList *entity.TodoList) error {
	query := `
		INSERT INTO todo_lists (id, owner_id, title, description, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id`

	todoList.CreatedAt = time.Now()
	todoList.UpdatedAt = time.Now()

	err := r.db.QueryRowContext(ctx, query, todoList.ID, todoList.OwnerID, todoList.Title, todoList.Description, todoList.CreatedAt, todoList.UpdatedAt).Scan(&todoList.ID)
	if err != nil {
		return fmt.Errorf("failed to create todo list: %w", err)
	}
	return nil
}

func (r *todoListRepository) GetTodoListByID(ctx context.Context, id string) (*entity.TodoList, error) {
	var todoList entity.TodoList
	query := `SELECT id, owner_id, title, description, created_at, updated_at FROM todo_lists WHERE id = $1`
	err := r.db.GetContext(ctx, &todoList, query, id)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo list by ID: %w", err)
	}
	return &todoList, nil
}

func (r *todoListRepository) GetTodoListsByOwnerID(ctx context.Context, ownerID string) ([]entity.TodoList, error) {
	var todoLists []entity.TodoList
	query := `SELECT id, owner_id, title, description, created_at, updated_at FROM todo_lists WHERE owner_id = $1`
	err := r.db.SelectContext(ctx, &todoLists, query, ownerID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo lists by owner ID: %w", err)
	}
	return todoLists, nil
}

func (r *todoListRepository) UpdateTodoList(ctx context.Context, todoList *entity.TodoList) error {
	query := `
		UPDATE todo_lists
		SET title = $1, description = $2, updated_at = $3
		WHERE id = $4`

	todoList.UpdatedAt = time.Now()

	_, err := r.db.ExecContext(ctx, query, todoList.Title, todoList.Description, todoList.UpdatedAt, todoList.ID)
	if err != nil {
		return fmt.Errorf("failed to update todo list: %w", err)
	}
	return nil
}

func (r *todoListRepository) DeleteTodoList(ctx context.Context, id string) error {
	query := `DELETE FROM todo_lists WHERE id = $1`
	_, err := r.db.ExecContext(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to delete todo list: %w", err)
	}
	return nil
}
