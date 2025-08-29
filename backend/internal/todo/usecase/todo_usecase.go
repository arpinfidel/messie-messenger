package usecase

import (
	"context"
	"fmt"

	"messenger/backend/internal/todo/entity"
	"messenger/backend/internal/todo/repository"
	"time"

	"github.com/google/uuid"
)

// TodoListUsecase defines the interface for todo list business logic.
type TodoListUsecase interface {
	CreateTodoList(ctx context.Context, title string, description *string, userID string) (*entity.TodoList, error)
	GetTodoListByID(ctx context.Context, id string, userID string) (*entity.TodoList, error)
	GetTodoListsByUser(ctx context.Context, userID string) ([]entity.TodoList, error)
	UpdateTodoList(ctx context.Context, id string, title string, description *string, userID string) (*entity.TodoList, error)
	DeleteTodoList(ctx context.Context, id string, userID string) error
	AddCollaborator(ctx context.Context, todoListID, collaboratorID, requestingUserID string) error
	RemoveCollaborator(ctx context.Context, todoListID, collaboratorID, requestingUserID string) error
	GetCollaborators(ctx context.Context, todoListID string, requestingUserID string) ([]entity.TodoListCollaborator, error)
}

// TodoItemUsecase defines the interface for todo item business logic.
type TodoItemUsecase interface {
	CreateTodoItem(ctx context.Context, listID string, description string, deadline *time.Time, prevItemID, nextItemID *string, userID string) (*entity.TodoItem, error)
	GetTodoItemByID(ctx context.Context, id string, listID string, userID string) (*entity.TodoItem, error)
	GetTodoItemsByList(ctx context.Context, listID string, userID string) ([]entity.TodoItem, error)
	UpdateTodoItem(ctx context.Context, id string, listID string, description string, deadline *time.Time, completed bool, newPrevItemID, newNextItemID *string, userID string) (*entity.TodoItem, error)
	DeleteTodoItem(ctx context.Context, id string, listID string, userID string) error
}

// Usecase implements the usecase interfaces.
type Usecase struct {
	TodoListRepo       repository.TodoListRepository
	TodoItemRepo       repository.TodoItemRepository
	TodoListCollabRepo repository.TodoListCollaboratorRepository
}

// NewUsecase creates a new Usecase.
func NewUsecase(
	todoListRepo repository.TodoListRepository,
	todoItemRepo repository.TodoItemRepository,
	todoListCollabRepo repository.TodoListCollaboratorRepository,
) *Usecase {
	return &Usecase{
		TodoListRepo:       todoListRepo,
		TodoItemRepo:       todoItemRepo,
		TodoListCollabRepo: todoListCollabRepo,
	}
}

// Implementations for TodoListUsecase
func (uc *Usecase) CreateTodoList(ctx context.Context, title string, description string, userID string) (*entity.TodoList, error) {
	todoList := &entity.TodoList{
		ID:          uuid.New().String(),
		OwnerID:     userID,
		Title:       title,
		Description: description,
	}

	err := uc.TodoListRepo.CreateTodoList(ctx, todoList)
	if err != nil {
		return nil, fmt.Errorf("failed to create todo list in repository: %w", err)
	}
	return todoList, nil
}

func (uc *Usecase) GetTodoListByID(ctx context.Context, id string, userID string) (*entity.TodoList, error) {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo list by ID from repository: %w", err)
	}

	if todoList.OwnerID != userID {
		isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, id, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to check collaborator status: %w", err)
		}
		if !isCollab {
			return nil, fmt.Errorf("user is not authorized to access this todo list")
		}
	}
	return todoList, nil
}

func (uc *Usecase) GetTodoListsByUser(ctx context.Context, userID string) ([]entity.TodoList, error) {
	todoLists, err := uc.TodoListRepo.GetTodoListsByUserID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo lists by user ID from repository: %w", err)
	}
	return todoLists, nil
}

func (uc *Usecase) UpdateTodoList(ctx context.Context, id string, title string, description string, userID string) (*entity.TodoList, error) {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo list by ID for update: %w", err)
	}

	if todoList.OwnerID != userID {
		isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, id, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to check collaborator status: %w", err)
		}
		if !isCollab {
			return nil, fmt.Errorf("user is not authorized to update this todo list")
		}
	}

	todoList.Title = title
	todoList.Description = description

	err = uc.TodoListRepo.UpdateTodoList(ctx, todoList)
	if err != nil {
		return nil, fmt.Errorf("failed to update todo list in repository: %w", err)
	}
	return todoList, nil
}

func (uc *Usecase) DeleteTodoList(ctx context.Context, id string, userID string) error {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, id)
	if err != nil {
		return fmt.Errorf("failed to get todo list by ID for deletion: %w", err)
	}

	if todoList.OwnerID != userID {
		return fmt.Errorf("user is not authorized to delete this todo list")
	}

	err = uc.TodoListRepo.DeleteTodoList(ctx, id)
	if err != nil {
		return fmt.Errorf("failed to delete todo list from repository: %w", err)
	}
	return nil
}

func (uc *Usecase) AddCollaborator(ctx context.Context, todoListID, collaboratorID, requestingUserID string) error {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, todoListID)
	if err != nil {
		return fmt.Errorf("failed to get todo list by ID: %w", err)
	}

	if todoList.OwnerID != requestingUserID {
		return fmt.Errorf("user is not authorized to add collaborators to this todo list")
	}

	isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, todoListID, collaboratorID)
	if err != nil {
		return fmt.Errorf("failed to check if user is already a collaborator: %w", err)
	}
	if isCollab {
		return fmt.Errorf("user is already a collaborator")
	}

	collaborator := &entity.TodoListCollaborator{
		TodoListID:     todoListID,
		CollaboratorID: collaboratorID,
	}

	err = uc.TodoListCollabRepo.AddCollaborator(ctx, collaborator)
	if err != nil {
		return fmt.Errorf("failed to add collaborator to repository: %w", err)
	}
	return nil
}

func (uc *Usecase) RemoveCollaborator(ctx context.Context, todoListID, collaboratorID, requestingUserID string) error {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, todoListID)
	if err != nil {
		return fmt.Errorf("failed to get todo list by ID: %w", err)
	}

	if todoList.OwnerID != requestingUserID {
		return fmt.Errorf("user is not authorized to remove collaborators from this todo list")
	}

	err = uc.TodoListCollabRepo.RemoveCollaborator(ctx, todoListID, collaboratorID)
	if err != nil {
		return fmt.Errorf("failed to remove collaborator from repository: %w", err)
	}
	return nil
}

func (uc *Usecase) GetCollaboratorDetailss(ctx context.Context, todoListID string, requestingUserID string) ([]entity.TodoListCollaboratorDetail, error) {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, todoListID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo list by ID: %w", err)
	}

	if todoList.OwnerID != requestingUserID {
		isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, todoListID, requestingUserID)
		if err != nil {
			return nil, fmt.Errorf("failed to check collaborator status: %w", err)
		}
		if !isCollab {
			return nil, fmt.Errorf("user is not authorized to view collaborators for this todo list")
		}
	}

	collaborators, err := uc.TodoListRepo.GetCollaboratorDetails(ctx, todoListID)
	if err != nil {
		return nil, fmt.Errorf("failed to get collaborators from repository: %w", err)
	}
	return collaborators, nil
}

// Implementations for TodoItemUsecase
func (uc *Usecase) CreateTodoItem(ctx context.Context, listID string, description string, deadline *time.Time, position string, userID string) (*entity.TodoItem, error) {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, listID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo list by ID: %w", err)
	}

	if todoList.OwnerID != userID {
		isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, listID, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to check collaborator status: %w", err)
		}
		if !isCollab {
			return nil, fmt.Errorf("user is not authorized to create items in this todo list")
		}
	}

	todoItem := &entity.TodoItem{
		ID:          uuid.New().String(),
		ListID:      listID,
		Description: description,
		Deadline:    deadline,
		Completed:   false,
		Position:    position,
	}

	err = uc.TodoItemRepo.CreateTodoItem(ctx, todoItem)
	if err != nil {
		return nil, fmt.Errorf("failed to create todo item in repository: %w", err)
	}
	return todoItem, nil
}

func (uc *Usecase) GetTodoItemByID(ctx context.Context, id string, listID string, userID string) (*entity.TodoItem, error) {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, listID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo list by ID: %w", err)
	}

	if todoList.OwnerID != userID {
		isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, listID, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to check collaborator status: %w", err)
		}
		if !isCollab {
			return nil, fmt.Errorf("user is not authorized to access items in this todo list")
		}
	}

	todoItem, err := uc.TodoItemRepo.GetTodoItemByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo item by ID from repository: %w", err)
	}
	return todoItem, nil
}

func (uc *Usecase) GetTodoItemsByList(ctx context.Context, listID string, userID string) ([]entity.TodoItem, error) {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, listID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo list by ID: %w", err)
	}

	if todoList.OwnerID != userID {
		isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, listID, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to check collaborator status: %w", err)
		}
		if !isCollab {
			return nil, fmt.Errorf("user is not authorized to access items in this todo list")
		}
	}

	todoItems, err := uc.TodoItemRepo.GetTodoItemsByListID(ctx, listID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo items by list ID from repository: %w", err)
	}
	return todoItems, nil
}

func (uc *Usecase) UpdateTodoItem(ctx context.Context, id string, listID string, userID string, newItem *entity.TodoItem) (*entity.TodoItem, error) {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, listID)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo list by ID: %w", err)
	}

	if todoList.OwnerID != userID {
		isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, listID, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to check collaborator status: %w", err)
		}
		if !isCollab {
			return nil, fmt.Errorf("user is not authorized to update items in this todo list")
		}
	}

	todoItem, err := uc.TodoItemRepo.GetTodoItemByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("failed to get todo item by ID for update: %w", err)
	}

	todoItem.Description = newItem.Description
	todoItem.Deadline = newItem.Deadline
	todoItem.Completed = newItem.Completed
	todoItem.Position = newItem.Position

	err = uc.TodoItemRepo.UpdateTodoItem(ctx, todoItem)
	if err != nil {
		return nil, fmt.Errorf("failed to update todo item in repository: %w", err)
	}
	return todoItem, nil
}

func (uc *Usecase) DeleteTodoItem(ctx context.Context, id string, listID string, userID string) error {
	todoList, err := uc.TodoListRepo.GetTodoListByID(ctx, listID)
	if err != nil {
		return fmt.Errorf("failed to get todo list by ID: %w", err)
	}

	if todoList.OwnerID != userID {
		isCollab, err := uc.TodoListCollabRepo.IsCollaborator(ctx, listID, userID)
		if err != nil {
			return fmt.Errorf("failed to check collaborator status: %w", err)
		}
		if !isCollab {
			return fmt.Errorf("user is not authorized to delete items from this todo list")
		}
	}

	err = uc.TodoItemRepo.DeleteTodoItem(ctx, id)
	if err != nil {
		return fmt.Errorf("failed to delete todo item from repository: %w", err)
	}
	return nil
}
