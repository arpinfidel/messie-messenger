package repository

import (
	"context"
	"fmt"

	"messenger/backend/internal/todo/entity"

	"gorm.io/gorm"
)

type TodoListRepository interface {
	CreateTodoList(ctx context.Context, todoList *entity.TodoList) error
	GetTodoListByID(ctx context.Context, id string) (*entity.TodoList, error)
	GetTodoListsByOwnerID(ctx context.Context, ownerID string) ([]entity.TodoList, error)
	GetTodoListsByUserID(ctx context.Context, userID string) ([]entity.TodoList, error)
	UpdateTodoList(ctx context.Context, todoList *entity.TodoList) error
	DeleteTodoList(ctx context.Context, id string) error
	GetCollaboratorDetails(ctx context.Context, listID string) ([]entity.TodoListCollaboratorDetail, error)
}

type todoListRepository struct {
	db *gorm.DB
}

func NewTodoListRepository(db *gorm.DB) TodoListRepository {
	return &todoListRepository{db: db}
}

func (r *todoListRepository) GetTodoListsByUserID(ctx context.Context, userID string) ([]entity.TodoList, error) {
	var todoLists []entity.TodoList
	err := r.db.WithContext(ctx).
		Joins("LEFT JOIN todo_list_collaborators tlc ON todo_lists.id = tlc.todo_list_id").
		Where("todo_lists.owner_id = ? OR tlc.collaborator_id = ?", userID, userID).
		Group("todo_lists.id").
		Order("todo_lists.created_at DESC").
		Find(&todoLists).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get todo lists by user ID: %w", err)
	}
	return todoLists, nil
}

func (r *todoListRepository) CreateTodoList(ctx context.Context, todoList *entity.TodoList) error {
	err := r.db.WithContext(ctx).Create(todoList).Error
	if err != nil {
		return fmt.Errorf("failed to create todo list: %w", err)
	}
	return nil
}

func (r *todoListRepository) GetTodoListByID(ctx context.Context, id string) (*entity.TodoList, error) {
	var todoList entity.TodoList
	err := r.db.WithContext(ctx).First(&todoList, "id = ?", id).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, entity.ErrNotFound
		}
		return nil, fmt.Errorf("failed to get todo list by ID: %w", err)
	}
	return &todoList, nil
}

func (r *todoListRepository) GetTodoListsByOwnerID(ctx context.Context, ownerID string) ([]entity.TodoList, error) {
	var todoLists []entity.TodoList
	err := r.db.WithContext(ctx).Where("owner_id = ?", ownerID).Find(&todoLists).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get todo lists by owner ID: %w", err)
	}
	return todoLists, nil
}

func (r *todoListRepository) UpdateTodoList(ctx context.Context, todoList *entity.TodoList) error {
	err := r.db.WithContext(ctx).Save(todoList).Error
	if err != nil {
		return fmt.Errorf("failed to update todo list: %w", err)
	}
	return nil
}

func (r *todoListRepository) DeleteTodoList(ctx context.Context, id string) error {
	err := r.db.WithContext(ctx).Delete(&entity.TodoList{}, "id = ?", id).Error
	if err != nil {
		return fmt.Errorf("failed to delete todo list: %w", err)
	}
	return nil
}

func (r *todoListRepository) GetCollaboratorDetails(ctx context.Context, listID string) ([]entity.TodoListCollaboratorDetail, error) {
	var collaborators []entity.TodoListCollaboratorDetail
	err := r.db.WithContext(ctx).
		Table("todo_list_collaborators").
		Select("todo_list_collaborators.todo_list_id, todo_list_collaborators.collaborator_id, todo_list_collaborators.created_at, todo_list_collaborators.updated_at, users.id, users.username, users.matrix_id, users.email, users.created_at, users.updated_at").
		Joins("JOIN users ON users.id = todo_list_collaborators.collaborator_id").
		Where("todo_list_collaborators.todo_list_id = ?", listID).
		Find(&collaborators).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get collaborators for todo list %s: %w", listID, err)
	}
	return collaborators, nil
}
