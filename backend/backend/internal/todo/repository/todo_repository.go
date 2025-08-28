package repository

import (
	"context"

	"messenger/backend/todo-service/internal/todo/entity"
	userentity "messenger/backend/todo-service/internal/user/entity"

	"github.com/jmoiron/sqlx"
)

// TodoItemRepository defines the interface for todo item data operations.
type TodoItemRepository interface {
	CreateTodoItem(ctx context.Context, todoItem *entity.TodoItem) error
	GetTodoItemByID(ctx context.Context, id string) (*entity.TodoItem, error)
	GetTodoItemsByListID(ctx context.Context, listID string) ([]entity.TodoItem, error)
	UpdateTodoItem(ctx context.Context, todoItem *entity.TodoItem) error
	DeleteTodoItem(ctx context.Context, id string) error
}

// TodoListCollaboratorRepository defines the interface for todo list collaborator data operations.
type TodoListCollaboratorRepository interface {
	AddCollaborator(ctx context.Context, collaborator *entity.TodoListCollaborator) error
	RemoveCollaborator(ctx context.Context, todoListID, userID string) error
	IsCollaborator(ctx context.Context, todoListID, userID string) (bool, error)
	GetCollaboratorsByTodoListID(ctx context.Context, todoListID string) ([]userentity.User, error)
	GetTodoListsByCollaboratorID(ctx context.Context, userID string) ([]entity.TodoList, error)
	GetCollaboratorIDsByTodoListID(ctx context.Context, todoListID string) ([]string, error)
}

// Repository combines all specific repository interfaces.
type Repository interface {
	TodoListRepository
	TodoItemRepository
	TodoListCollaboratorRepository
}

type repository struct {
	TodoListRepository
	TodoItemRepository
	TodoListCollaboratorRepository
}

// NewRepository creates a new repository.
func NewRepository(db *sqlx.DB) Repository {
	return &repository{
		TodoListRepository:             NewTodoListRepository(db),
		TodoItemRepository:             NewTodoItemRepository(db),
		TodoListCollaboratorRepository: NewTodoListCollaboratorRepository(db),
	}
}
