package repository

import (
	"context"
	"fmt"
	"time"

	"messenger/backend/todo-service/internal/todo/entity"
	userentity "messenger/backend/todo-service/internal/user/entity"

	"github.com/jmoiron/sqlx"
)

type todoListCollaboratorRepository struct {
	db *sqlx.DB
}

func NewTodoListCollaboratorRepository(db *sqlx.DB) TodoListCollaboratorRepository {
	return &todoListCollaboratorRepository{db: db}
}

func (r *todoListCollaboratorRepository) AddCollaborator(ctx context.Context, collaborator *entity.TodoListCollaborator) error {
	query := `
		INSERT INTO todo_list_collaborators (todo_list_id, user_id, created_at, updated_at)
		VALUES ($1, $2, $3, $4)`

	collaborator.CreatedAt = time.Now()
	collaborator.UpdatedAt = time.Now()

	_, err := r.db.ExecContext(ctx, query, collaborator.TodoListID, collaborator.UserID, collaborator.CreatedAt, collaborator.UpdatedAt)
	if err != nil {
		return fmt.Errorf("failed to add collaborator: %w", err)
	}
	return nil
}

func (r *todoListCollaboratorRepository) RemoveCollaborator(ctx context.Context, todoListID, userID string) error {
	query := `DELETE FROM todo_list_collaborators WHERE todo_list_id = $1 AND user_id = $2`
	_, err := r.db.ExecContext(ctx, query, todoListID, userID)
	if err != nil {
		return fmt.Errorf("failed to remove collaborator: %w", err)
	}
	return nil
}

func (r *todoListCollaboratorRepository) IsCollaborator(ctx context.Context, todoListID, userID string) (bool, error) {
	var count int
	query := `SELECT COUNT(*) FROM todo_list_collaborators WHERE todo_list_id = $1 AND user_id = $2`
	err := r.db.GetContext(ctx, &count, query, todoListID, userID)
	if err != nil {
		return false, fmt.Errorf("failed to check if user is collaborator: %w", err)
	}
	return count > 0, nil
}

func (r *todoListCollaboratorRepository) GetCollaboratorsByTodoListID(ctx context.Context, todoListID string) ([]userentity.User, error) {
	var users []userentity.User
	query := `
		SELECT u.id, u.username, u.email, u.created_at, u.updated_at
		FROM users u
		JOIN todo_list_collaborators tlc ON u.id = tlc.user_id
		WHERE tlc.todo_list_id = $1`
	err := r.db.SelectContext(ctx, &users, query, todoListID)
	if err != nil {
		return nil, fmt.Errorf("failed to get collaborators by todo list ID: %w", err)
	}
	return users, nil
}

func (r *todoListCollaboratorRepository) GetTodoListsByCollaboratorID(ctx context.Context, userID string) ([]entity.TodoList, error) {
	var todoLists []entity.TodoList
	query := `
		SELECT tl.id, tl.owner_id, tl.title, tl.description, tl.created_at, tl.updated_at
		FROM todo_lists tl
		JOIN todo_list_collaborators tlc ON tl.id = tlc.todo_list_id
		WHERE tlc.user_id = $1`
	err := r.db.SelectContext(ctx, &todoLists, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo lists by collaborator ID: %w", err)
	}
	return todoLists, nil
}

func (r *todoListCollaboratorRepository) GetCollaboratorIDsByTodoListID(ctx context.Context, todoListID string) ([]string, error) {
	var userIDs []string
	query := `SELECT user_id FROM todo_list_collaborators WHERE todo_list_id = $1`
	err := r.db.SelectContext(ctx, &userIDs, query, todoListID)
	if err != nil {
		return nil, fmt.Errorf("failed to get collaborator IDs by todo list ID: %w", err)
	}
	return userIDs, nil
}
