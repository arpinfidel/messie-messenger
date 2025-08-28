package entity

import "time"

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
	Description string     `db:"description"`
	Deadline    *time.Time `db:"deadline"` // Optional
	Completed   bool       `db:"completed"`
	CreatedAt   time.Time  `db:"created_at"`
	UpdatedAt   time.Time  `db:"updated_at"`
}

// TodoListCollaborator represents a many-to-many relationship between TodoList and User.
type TodoListCollaborator struct {
	TodoListID     string    `db:"todo_list_id"`    // Foreign key to TodoList.ID
	CollaboratorID string    `db:"collaborator_id"` // ID of the collaborating user
	UserID         string    `db:"user_id"`         // ID of the user associated with this collaboration
	CreatedAt      time.Time `db:"created_at"`
	UpdatedAt      time.Time `db:"updated_at"`
}
