package repository

import (
	"context"
	"fmt"
	"messenger/backend/internal/todo/entity"
	userentity "messenger/backend/internal/user/entity"

	"gorm.io/gorm"
)

type todoListCollaboratorRepository struct {
	db *gorm.DB
}

func NewTodoListCollaboratorRepository(db *gorm.DB) TodoListCollaboratorRepository {
	return &todoListCollaboratorRepository{db: db}
}

func (r *todoListCollaboratorRepository) AddCollaborator(ctx context.Context, collaborator *entity.TodoListCollaborator) error {
	err := r.db.WithContext(ctx).Create(collaborator).Error
	if err != nil {
		return fmt.Errorf("failed to add collaborator: %w", err)
	}
	return nil
}

func (r *todoListCollaboratorRepository) RemoveCollaborator(ctx context.Context, todoListID, userID string) error {
	err := r.db.WithContext(ctx).Where("todo_list_id = ? AND collaborator_id = ?", todoListID, userID).Delete(&entity.TodoListCollaborator{}).Error
	if err != nil {
		return fmt.Errorf("failed to remove collaborator: %w", err)
	}
	return nil
}

func (r *todoListCollaboratorRepository) IsCollaborator(ctx context.Context, todoListID, userID string) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&entity.TodoListCollaborator{}).Where("todo_list_id = ? AND collaborator_id = ?", todoListID, userID).Count(&count).Error
	if err != nil {
		return false, fmt.Errorf("failed to check if user is collaborator: %w", err)
	}
	return count > 0, nil
}

func (r *todoListCollaboratorRepository) GetCollaboratorsByTodoListID(ctx context.Context, todoListID string) ([]userentity.User, error) {
	var users []userentity.User
	err := r.db.WithContext(ctx).
		Table("users").
		Joins("JOIN todo_list_collaborators tlc ON users.id = tlc.collaborator_id").
		Where("tlc.todo_list_id = ?", todoListID).
		Find(&users).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get collaborators by todo list ID: %w", err)
	}
	return users, nil
}

func (r *todoListCollaboratorRepository) GetTodoListsByCollaboratorID(ctx context.Context, userID string) ([]entity.TodoList, error) {
	var todoLists []entity.TodoList
	err := r.db.WithContext(ctx).
		Table("todo_lists").
		Joins("JOIN todo_list_collaborators tlc ON todo_lists.id = tlc.todo_list_id").
		Where("tlc.collaborator_id = ?", userID).
		Find(&todoLists).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get todo lists by collaborator ID: %w", err)
	}
	return todoLists, nil
}

func (r *todoListCollaboratorRepository) GetCollaboratorIDsByTodoListID(ctx context.Context, todoListID string) ([]string, error) {
	var userIDs []string
	err := r.db.WithContext(ctx).Model(&entity.TodoListCollaborator{}).Where("todo_list_id = ?", todoListID).Select("collaborator_id").Find(&userIDs).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get collaborator IDs by todo list ID: %w", err)
	}
	return userIDs, nil
}
