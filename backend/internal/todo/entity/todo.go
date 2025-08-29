package entity

import (
	userentity "messenger/backend/internal/user/entity"
	"time"
)

// TodoList represents a todo list.
type TodoList struct {
	ID          string    `db:"id"`
	Title       string    `db:"title"`
	Description *string   `db:"description"` // Optional
	OwnerID     string    `db:"owner_id"`    // ID of the user who owns the list
	CreatedAt   time.Time `db:"created_at"`
	UpdatedAt   time.Time `db:"updated_at"`
}

// TodoItem represents a todo item within a list.
type TodoItem struct {
	ID          string     `db:"id"`
	ListID      string     `db:"list_id"` // Foreign key to TodoList.ID
	Title       string     `db:"title" json:"title"`
	Description string     `db:"description"`
	Deadline    *time.Time `db:"deadline" json:"due_date,omitempty"` // Optional
	Completed   bool       `db:"completed"`
	Position    string     `db:"position"` // Fractional index position
	CreatedAt   time.Time  `db:"created_at"`
	UpdatedAt   time.Time  `db:"updated_at"`
}

// TodoListCollaborator represents a many-to-many relationship between TodoList and User.
type TodoListCollaborator struct {
	TodoListID     string    `db:"todo_list_id"`    // Foreign key to TodoList.ID
	CollaboratorID string    `db:"collaborator_id"` // ID of the collaborating user
	CreatedAt      time.Time `db:"created_at"`
	UpdatedAt      time.Time `db:"updated_at"`
}

// TodoListCollaboratorDetail combines TodoListCollaborator with User details.
type TodoListCollaboratorDetail struct {
	TodoListCollaborator
	userentity.User
}
