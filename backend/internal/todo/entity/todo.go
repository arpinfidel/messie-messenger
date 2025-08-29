package entity

import (
	"errors"
	userentity "messenger/backend/internal/user/entity"
	"time"
)

var ErrNotFound = errors.New("not found")

// TodoList represents a todo list.
type TodoList struct {
	ID          string    `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	Title       string    `gorm:"type:text;not null" json:"title"`
	Description string    `gorm:"type:text;not null" json:"description"` // Optional
	OwnerID     string    `gorm:"type:uuid;not null" json:"owner_id"`    // ID of the user who owns the list
	CreatedAt   time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt   time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

// TodoItem represents a todo item within a list.
type TodoItem struct {
	ID          string     `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	ListID      string     `gorm:"type:uuid;not null" json:"list_id"` // Foreign key to TodoList.ID
	
	Position    string     `gorm:"type:text;not null" json:"position"` // Fractional index position
	Title       string     `gorm:"type:text;not null" json:"title"`
	Description string     `gorm:"type:text;not null" json:"description"`
	
	Deadline    *time.Time `gorm:"type:timestamp with time zone" json:"due_date,omitempty"` // Optional
	Completed   bool       `gorm:"type:boolean;default:false" json:"completed"`
	
	CreatedAt   time.Time  `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt   time.Time  `gorm:"autoUpdateTime" json:"updated_at"`
}

// TodoListCollaborator represents a many-to-many relationship between TodoList and User.
type TodoListCollaborator struct {
	TodoListID     string    `gorm:"type:uuid;primaryKey" json:"todo_list_id"`    // Foreign key to TodoList.ID
	CollaboratorID string    `gorm:"type:uuid;primaryKey" json:"collaborator_id"` // ID of the collaborating user
	CreatedAt      time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt      time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

// TodoListCollaboratorDetail combines TodoListCollaborator with User details.
type TodoListCollaboratorDetail struct {
	TodoListCollaborator
	userentity.User
}
