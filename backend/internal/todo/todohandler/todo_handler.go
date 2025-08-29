package todohandler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"messenger/backend/api/generated"
	"messenger/backend/internal/todo/entity"
	"messenger/backend/internal/todo/usecase"
	"messenger/backend/pkg/middleware"

	"github.com/google/uuid"
	openapi_types "github.com/oapi-codegen/runtime/types"
)

type TodoHandler struct {
	Usecases *usecase.Usecase
}

// NewHandler creates a new Handler.
func NewHandler(uc *usecase.Usecase) *TodoHandler {
	return &TodoHandler{Usecases: uc}
}

// Helper function to send JSON responses
func sendJSONResponse(w http.ResponseWriter, statusCode int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if payload != nil {
		json.NewEncoder(w).Encode(payload)
	}
}

// Helper function to send error responses
func sendErrorResponse(w http.ResponseWriter, statusCode int, message string) {
	sendJSONResponse(w, statusCode, map[string]string{"error": message})
}

func (h *TodoHandler) CreateTodoList(w http.ResponseWriter, r *http.Request) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var newTodoList generated.NewTodoList
	if err := json.NewDecoder(r.Body).Decode(&newTodoList); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	title := newTodoList.Title
	description := newTodoList.Description

	todoList, err := h.Usecases.CreateTodoList(r.Context(), title, description, userID)
	if err != nil {
		sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to create todo list: %v", err))
		return
	}

	responseTodoList := generated.TodoList{
		Id:          openapi_types.UUID(uuid.MustParse(todoList.ID)),
		OwnerId:     openapi_types.UUID(uuid.MustParse(todoList.OwnerID)),
		Title:       todoList.Title,
		Description: todoList.Description,
		CreatedAt:   &todoList.CreatedAt,
		UpdatedAt:   &todoList.UpdatedAt,
	}

	sendJSONResponse(w, http.StatusCreated, responseTodoList)
}

func (h *TodoHandler) GetTodoListById(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	todoList, err := h.Usecases.GetTodoListByID(r.Context(), listId.String(), userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get todo list: %v", err))
		}
		return
	}

	responseTodoList := generated.TodoList{
		Id:          openapi_types.UUID(uuid.MustParse(todoList.ID)),
		OwnerId:     openapi_types.UUID(uuid.MustParse(todoList.OwnerID)),
		Title:       todoList.Title,
		Description: todoList.Description,
		CreatedAt:   &todoList.CreatedAt,
		UpdatedAt:   &todoList.UpdatedAt,
	}

	sendJSONResponse(w, http.StatusOK, responseTodoList)
}

func (h *TodoHandler) GetTodoListsByUserId(w http.ResponseWriter, r *http.Request, params generated.GetTodoListsByUserIdParams) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	ownerID := params.UserId.String()
	if ownerID != userID {
		sendErrorResponse(w, http.StatusForbidden, "Forbidden: Cannot view todo lists of another user directly. Use collaborators endpoint for shared lists.")
		return
	}

	todoLists, err := h.Usecases.GetTodoListsByUser(r.Context(), ownerID)
	if err != nil {
		sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get todo lists: %v", err))
		return
	}

	responseTodoLists := make([]generated.TodoList, len(todoLists))
	for i, tl := range todoLists {
		responseTodoLists[i] = generated.TodoList{
			Id:          openapi_types.UUID(uuid.MustParse(tl.ID)),
			OwnerId:     openapi_types.UUID(uuid.MustParse(tl.OwnerID)),
			Title:       tl.Title,
			Description: tl.Description,
			CreatedAt:   &tl.CreatedAt,
			UpdatedAt:   &tl.UpdatedAt,
		}
	}

	sendJSONResponse(w, http.StatusOK, responseTodoLists)
}

func (h *TodoHandler) UpdateTodoList(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var updateTodoList generated.UpdateTodoList
	if err := json.NewDecoder(r.Body).Decode(&updateTodoList); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	title := ""
	if updateTodoList.Title != nil {
		title = *updateTodoList.Title
	}
	description := updateTodoList.Description

	todoList, err := h.Usecases.UpdateTodoList(r.Context(), listId.String(), title, description, userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to update todo list: %v", err))
		}
		return
	}

	responseTodoList := generated.TodoList{
		Id:          openapi_types.UUID(uuid.MustParse(todoList.ID)),
		OwnerId:     openapi_types.UUID(uuid.MustParse(todoList.OwnerID)),
		Title:       todoList.Title,
		Description: todoList.Description,
		CreatedAt:   &todoList.CreatedAt,
		UpdatedAt:   &todoList.UpdatedAt,
	}

	sendJSONResponse(w, http.StatusOK, responseTodoList)
}

func (h *TodoHandler) DeleteTodoList(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	err := h.Usecases.DeleteTodoList(r.Context(), listId.String(), userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to delete todo list: %v", err))
		}
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *TodoHandler) AddCollaborator(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var newCollaborator generated.NewCollaborator
	if err := json.NewDecoder(r.Body).Decode(&newCollaborator); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	err := h.Usecases.AddCollaborator(r.Context(), listId.String(), newCollaborator.UserId.String(), userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo list or user not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else if strings.Contains(err.Error(), "already a collaborator") {
			sendErrorResponse(w, http.StatusConflict, fmt.Sprintf("Conflict: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to add collaborator: %v", err))
		}
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func (h *TodoHandler) RemoveCollaborator(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID, userId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	err := h.Usecases.RemoveCollaborator(r.Context(), listId.String(), userId.String(), userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo list or collaborator not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to remove collaborator: %v", err))
		}
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *TodoHandler) CreateTodoItem(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var newTodoItem generated.NewTodoItem
	if err := json.NewDecoder(r.Body).Decode(&newTodoItem); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	description := newTodoItem.Description
	dueDate := newTodoItem.DueDate

	descriptionVal := ""
	if description != nil {
		descriptionVal = *description
	}

	todoItem, err := h.Usecases.CreateTodoItem(r.Context(), listId.String(), descriptionVal, dueDate, newTodoItem.Position, userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to create todo item: %v", err))
		}
		return
	}

	responseTodoItem := generated.TodoItem{
		Id:          openapi_types.UUID(uuid.MustParse(todoItem.ID)),
		ListId:      openapi_types.UUID(uuid.MustParse(todoItem.ListID)),
		Description: &todoItem.Description, // entity.TodoItem.Description is string, generated.TodoItem.Description is *string
		Completed:   todoItem.Completed,
		DueDate:     todoItem.Deadline,
		Position:    todoItem.Position,
		CreatedAt:   &todoItem.CreatedAt,
		UpdatedAt:   &todoItem.UpdatedAt,
	}

	sendJSONResponse(w, http.StatusCreated, responseTodoItem)
}

func (h *TodoHandler) GetTodoItemsByListId(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	todoItems, err := h.Usecases.GetTodoItemsByList(r.Context(), listId.String(), userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get todo items: %v", err))
		}
		return
	}

	responseTodoItems := make([]generated.TodoItem, len(todoItems))
	for i, item := range todoItems {
		responseTodoItems[i] = generated.TodoItem{
			Id:          openapi_types.UUID(uuid.MustParse(item.ID)),
			ListId:      openapi_types.UUID(uuid.MustParse(item.ListID)),
			Description: &item.Description, // entity.TodoItem.Description is string, generated.TodoItem.Description is *string
			Completed:   item.Completed,
			DueDate:     item.Deadline,
			CreatedAt:   &item.CreatedAt,
			UpdatedAt:   &item.UpdatedAt,
		}
		responseTodoItems[i].Position = item.Position
	}

	sendJSONResponse(w, http.StatusOK, responseTodoItems)
}

func (h *TodoHandler) GetTodoItemById(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID, itemId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	todoItem, err := h.Usecases.GetTodoItemByID(r.Context(), itemId.String(), listId.String(), userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo item or list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get todo item: %v", err))
		}
		return
	}

	responseTodoItem := generated.TodoItem{
		Id:          openapi_types.UUID(uuid.MustParse(todoItem.ID)),
		ListId:      openapi_types.UUID(uuid.MustParse(todoItem.ListID)),
		Description: &todoItem.Description, // entity.TodoItem.Description is string, generated.TodoItem.Description is *string
		Completed:   todoItem.Completed,
		DueDate:     todoItem.Deadline,
		CreatedAt:   &todoItem.CreatedAt,
		UpdatedAt:   &todoItem.UpdatedAt,
	}

	sendJSONResponse(w, http.StatusOK, responseTodoItem)
}

func (h *TodoHandler) UpdateTodoItem(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID, itemId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var updateTodoItem generated.UpdateTodoItem
	if err := json.NewDecoder(r.Body).Decode(&updateTodoItem); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	todoItem, err := h.Usecases.UpdateTodoItem(r.Context(), itemId.String(), listId.String(), userID, &entity.TodoItem{
		Description: updateTodoItem.Description,
		Deadline:    updateTodoItem.DueDate,
		Completed:   updateTodoItem.Completed,
		Position:    updateTodoItem.Position,
	})
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo item or list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to update todo item: %v", err))
		}
		return
	}

	responseTodoItem := generated.TodoItem{
		Id:          openapi_types.UUID(uuid.MustParse(todoItem.ID)),
		ListId:      openapi_types.UUID(uuid.MustParse(todoItem.ListID)),
		Description: &todoItem.Description, // entity.TodoItem.Description is string, generated.TodoItem.Description is *string
		Completed:   todoItem.Completed,
		DueDate:     todoItem.Deadline,
		Position:    todoItem.Position,
		CreatedAt:   &todoItem.CreatedAt,
		UpdatedAt:   &todoItem.UpdatedAt,
	}

	sendJSONResponse(w, http.StatusOK, responseTodoItem)
}

func (h *TodoHandler) DeleteTodoItem(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID, itemId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	err := h.Usecases.DeleteTodoItem(r.Context(), itemId.String(), listId.String(), userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo item or list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to delete todo item: %v", err))
		}
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *TodoHandler) GetCollaborators(w http.ResponseWriter, r *http.Request, listId openapi_types.UUID) {
	// User ID is expected to be in the context after authentication middleware
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	if !ok || userID == "" {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	collaborators, err := h.Usecases.GetCollaboratorDetailss(r.Context(), listId.String(), userID)
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("Todo list not found: %v", err))
		} else if strings.Contains(err.Error(), "not authorized") {
			sendErrorResponse(w, http.StatusForbidden, fmt.Sprintf("Forbidden: %v", err))
		} else {
			sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get collaborators: %v", err))
		}
		return
	}

	responseCollaborators := make([]generated.CollaboratorDetail, len(collaborators))
	for i, collab := range collaborators {
		responseCollaborators[i] = generated.CollaboratorDetail{
			ListId:         openapi_types.UUID(uuid.MustParse(collab.TodoListID)),
			CollaboratorId: openapi_types.UUID(uuid.MustParse(collab.CollaboratorID)),
			Username:       collab.Username,
		}
	}

	sendJSONResponse(w, http.StatusOK, responseCollaborators)
}
