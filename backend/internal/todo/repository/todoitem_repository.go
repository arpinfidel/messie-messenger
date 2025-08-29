package repository

import (
	"context"
	"fmt"
	"messenger/backend/internal/todo/entity"

	"gorm.io/gorm"
)

type todoItemRepository struct {
	db *gorm.DB
}

func NewTodoItemRepository(db *gorm.DB) TodoItemRepository {
	return &todoItemRepository{db: db}
}

func (r *todoItemRepository) CreateTodoItem(ctx context.Context, todoItem *entity.TodoItem) error {
	err := r.db.WithContext(ctx).Create(todoItem).Error
	if err != nil {
		return fmt.Errorf("failed to create todo item: %w", err)
	}
	return nil
}

func (r *todoItemRepository) GetTodoItemByID(ctx context.Context, id string) (*entity.TodoItem, error) {
	var todoItem entity.TodoItem
	err := r.db.WithContext(ctx).First(&todoItem, "id = ?", id).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, entity.ErrNotFound
		}
		return nil, fmt.Errorf("failed to get todo item by ID: %w", err)
	}
	return &todoItem, nil
}

func (r *todoItemRepository) GetTodoItemsByListID(ctx context.Context, listID string) ([]entity.TodoItem, error) {
	var todoItems []entity.TodoItem
	err := r.db.WithContext(ctx).Where("list_id = ?", listID).Find(&todoItems).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get todo items by list ID: %w", err)
	}
	return todoItems, nil
}

func (r *todoItemRepository) UpdateTodoItem(ctx context.Context, todoItem *entity.TodoItem) error {
	err := r.db.WithContext(ctx).Save(todoItem).Error
	if err != nil {
		return fmt.Errorf("failed to update todo item: %w", err)
	}
	return nil
}

func (r *todoItemRepository) DeleteTodoItem(ctx context.Context, id string) error {
	err := r.db.WithContext(ctx).Delete(&entity.TodoItem{}, "id = ?", id).Error
	if err != nil {
		return fmt.Errorf("failed to delete todo item: %w", err)
	}
	return nil
}
