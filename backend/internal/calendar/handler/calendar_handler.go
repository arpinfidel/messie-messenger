package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"messenger/backend/api/generated"
	"messenger/backend/internal/calendar/entity"
	"messenger/backend/internal/calendar/usecase"
	"messenger/backend/pkg/middleware"

	"github.com/google/uuid"
	openapi_types "github.com/oapi-codegen/runtime/types"
)

type CalendarHandler struct {
	Usecases *usecase.Usecase
}

func NewCalendarHandler(uc *usecase.Usecase) *CalendarHandler {
	return &CalendarHandler{Usecases: uc}
}

func sendJSONResponse(w http.ResponseWriter, statusCode int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if payload != nil {
		_ = json.NewEncoder(w).Encode(payload)
	}
}

func sendErrorResponse(w http.ResponseWriter, statusCode int, message string) {
	sendJSONResponse(w, statusCode, map[string]string{"message": message})
}

func currentUserID(r *http.Request) (string, bool) {
	userID, ok := r.Context().Value(middleware.ContextKeyUserID).(string)
	return userID, ok && userID != ""
}

func validateCalendarCategory(category string) (string, error) {
	trimmed := strings.TrimSpace(category)
	if trimmed == "" {
		return "", fmt.Errorf("category is required")
	}
	return trimmed, nil
}

func (h *CalendarHandler) ImportCalendarSource(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	if err := r.ParseMultipartForm(32 << 20); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid multipart form: %v", err))
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		sendErrorResponse(w, http.StatusBadRequest, "Missing calendar file upload")
		return
	}
	defer file.Close()

	displayName := strings.TrimSpace(r.FormValue("display_name"))
	category, err := validateCalendarCategory(r.FormValue("category"))
	if err != nil {
		sendErrorResponse(w, http.StatusBadRequest, err.Error())
		return
	}
	source, importedCount, err := h.Usecases.ImportCalendarSource(
		r.Context(),
		userID,
		header.Filename,
		category,
		displayName,
		file,
	)
	if err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Failed to import calendar source: %v", err))
		return
	}

	sendJSONResponse(w, http.StatusCreated, generated.CalendarImportResponse{
		Source:             toGeneratedCalendarSource(*source),
		ImportedEventCount: int32(importedCount),
	})
}

func (h *CalendarHandler) CreateLinkedCalendarSource(
	w http.ResponseWriter,
	r *http.Request,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var body generated.CreateLinkedCalendarSourceJSONRequestBody
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&body); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	displayName := ""
	if body.DisplayName != nil {
		displayName = strings.TrimSpace(*body.DisplayName)
	}
	category, err := validateCalendarCategory(body.Category)
	if err != nil {
		sendErrorResponse(w, http.StatusBadRequest, err.Error())
		return
	}

	source, importedCount, err := h.Usecases.ImportCalendarSourceFromURL(
		r.Context(),
		userID,
		body.Url,
		category,
		displayName,
	)
	if err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Failed to import linked calendar source: %v", err))
		return
	}

	sendJSONResponse(w, http.StatusCreated, generated.CalendarImportResponse{
		Source:             toGeneratedCalendarSource(*source),
		ImportedEventCount: int32(importedCount),
	})
}

func (h *CalendarHandler) GetCalendarSources(w http.ResponseWriter, r *http.Request) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	sources, err := h.Usecases.GetCalendarSources(r.Context(), userID)
	if err != nil {
		sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get calendar sources: %v", err))
		return
	}

	response := make([]generated.CalendarSource, len(sources))
	for i, source := range sources {
		response[i] = toGeneratedCalendarSource(source)
	}
	sendJSONResponse(w, http.StatusOK, response)
}

func (h *CalendarHandler) GetCalendarSourceById(
	w http.ResponseWriter,
	r *http.Request,
	sourceId openapi_types.UUID,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	source, err := h.Usecases.GetCalendarSourceByID(r.Context(), sourceId.String(), userID)
	if err != nil {
		handleCalendarError(w, err, "calendar source")
		return
	}
	sendJSONResponse(w, http.StatusOK, toGeneratedCalendarSource(*source))
}

func (h *CalendarHandler) DeleteCalendarSource(
	w http.ResponseWriter,
	r *http.Request,
	sourceId openapi_types.UUID,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	if err := h.Usecases.DeleteCalendarSource(r.Context(), sourceId.String(), userID); err != nil {
		handleCalendarError(w, err, "calendar source")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *CalendarHandler) UpdateCalendarSource(
	w http.ResponseWriter,
	r *http.Request,
	sourceId openapi_types.UUID,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	var body generated.UpdateCalendarSourceJSONRequestBody
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&body); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, fmt.Sprintf("Invalid request body: %v", err))
		return
	}

	category, err := validateCalendarCategory(body.Category)
	if err != nil {
		sendErrorResponse(w, http.StatusBadRequest, err.Error())
		return
	}

	source, err := h.Usecases.UpdateCalendarSource(
		r.Context(),
		sourceId.String(),
		userID,
		category,
		body.DisplayName,
	)
	if err != nil {
		handleCalendarError(w, err, "calendar source")
		return
	}
	sendJSONResponse(w, http.StatusOK, toGeneratedCalendarSource(*source))
}

func (h *CalendarHandler) RefreshCalendarSource(
	w http.ResponseWriter,
	r *http.Request,
	sourceId openapi_types.UUID,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	source, importedCount, err := h.Usecases.RefreshCalendarSource(
		r.Context(),
		sourceId.String(),
		userID,
	)
	if err != nil {
		handleCalendarError(w, err, "calendar source")
		return
	}

	sendJSONResponse(w, http.StatusOK, generated.CalendarImportResponse{
		Source:             toGeneratedCalendarSource(*source),
		ImportedEventCount: int32(importedCount),
	})
}

func (h *CalendarHandler) GetCalendarEvents(
	w http.ResponseWriter,
	r *http.Request,
	params generated.GetCalendarEventsParams,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	events, err := h.Usecases.GetCalendarEvents(
		r.Context(),
		userID,
		params.From,
		params.To,
		stringPtrFromUUID(params.SourceId),
		params.Cursor,
		stringPtrFromDirection(params.Direction),
		params.Limit,
	)
	if err != nil {
		handleCalendarError(w, err, "calendar events")
		return
	}

	response := make([]generated.CalendarEvent, len(events))
	for i, event := range events {
		response[i] = toGeneratedCalendarEvent(event)
	}
	sendJSONResponse(w, http.StatusOK, response)
}

func (h *CalendarHandler) GetCalendarEventById(
	w http.ResponseWriter,
	r *http.Request,
	eventId openapi_types.UUID,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	event, err := h.Usecases.GetCalendarEventByID(r.Context(), userID, eventId.String())
	if err != nil {
		handleCalendarError(w, err, "calendar event")
		return
	}
	sendJSONResponse(w, http.StatusOK, toGeneratedCalendarEvent(*event))
}

func (h *CalendarHandler) GetUpcomingCalendarEvents(
	w http.ResponseWriter,
	r *http.Request,
	params generated.GetUpcomingCalendarEventsParams,
) {
	userID, ok := currentUserID(r)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "User ID not found in context")
		return
	}

	limit := 50
	if params.Limit != nil {
		limit = int(*params.Limit)
	}
	events, err := h.Usecases.GetUpcomingCalendarEvents(r.Context(), userID, limit)
	if err != nil {
		handleCalendarError(w, err, "upcoming calendar events")
		return
	}

	response := make([]generated.CalendarEvent, len(events))
	for i, event := range events {
		response[i] = toGeneratedCalendarEvent(event)
	}
	sendJSONResponse(w, http.StatusOK, response)
}

func handleCalendarError(w http.ResponseWriter, err error, label string) {
	switch {
	case errors.Is(err, entity.ErrNotFound) || strings.Contains(err.Error(), entity.ErrNotFound.Error()):
		sendErrorResponse(w, http.StatusNotFound, fmt.Sprintf("%s not found", strings.Title(label)))
	case strings.Contains(err.Error(), "not authorized"):
		sendErrorResponse(w, http.StatusForbidden, "Forbidden")
	default:
		sendErrorResponse(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get %s", label))
	}
}

func toGeneratedCalendarSource(source entity.CalendarSource) generated.CalendarSource {
	return generated.CalendarSource{
		Id:                   openapi_types.UUID(uuid.MustParse(source.ID)),
		UserId:               openapi_types.UUID(uuid.MustParse(source.UserID)),
		Kind:                 source.Kind,
		DisplayName:          source.DisplayName,
		Category:             source.Category,
		ImportMode:           source.ImportMode,
		SourceUrl:            source.SourceURL,
		RefreshState:         source.RefreshState,
		LastSyncedAt:         source.LastSyncedAt,
		LastRefreshAttemptAt: source.LastRefreshAttemptAt,
		LastRefreshError:     source.LastRefreshError,
		Etag:                 source.ETag,
		LastModified:         source.LastModified,
		NextRefreshAt:        source.NextRefreshAt,
		CreatedAt:            &source.CreatedAt,
		UpdatedAt:            &source.UpdatedAt,
	}
}

func toGeneratedCalendarEvent(event entity.CalendarEvent) generated.CalendarEvent {
	return generated.CalendarEvent{
		Id:                openapi_types.UUID(uuid.MustParse(event.ID)),
		SourceId:          openapi_types.UUID(uuid.MustParse(event.SourceID)),
		ExternalUid:       event.ExternalUID,
		Title:             event.Title,
		Description:       event.Description,
		Location:          event.Location,
		StartsAt:          event.StartsAt,
		EndsAt:            event.EndsAt,
		AllDay:            event.AllDay,
		Status:            event.Status,
		Timezone:          event.Timezone,
		RecurrenceSummary: summarizeRecurrenceRule(event.RecurrenceRaw),
		SourceDisplayName: event.Source.DisplayName,
		CreatedAt:         &event.CreatedAt,
		UpdatedAt:         &event.UpdatedAt,
	}
}

func summarizeRecurrenceRule(rule *string) *string {
	if rule == nil || strings.TrimSpace(*rule) == "" {
		return nil
	}

	parts := map[string]string{}
	for _, rawPart := range strings.Split(*rule, ";") {
		part := strings.TrimSpace(rawPart)
		if part == "" {
			continue
		}
		key, value, found := strings.Cut(part, "=")
		if !found {
			continue
		}
		parts[strings.ToUpper(strings.TrimSpace(key))] = strings.TrimSpace(value)
	}

	frequency := recurrenceFrequencyLabel(parts["FREQ"], parts["INTERVAL"])
	if frequency == "" {
		value := strings.TrimSpace(*rule)
		return &value
	}

	segments := []string{frequency}
	if byDay := recurrenceByDayLabel(parts["BYDAY"]); byDay != "" {
		segments = append(segments, byDay)
	}
	if count := recurrenceCountLabel(parts["COUNT"]); count != "" {
		segments = append(segments, count)
	} else if until := recurrenceUntilLabel(parts["UNTIL"]); until != "" {
		segments = append(segments, until)
	}

	summary := strings.Join(segments, ", ")
	return &summary
}

func recurrenceFrequencyLabel(freq, intervalValue string) string {
	freq = strings.ToUpper(strings.TrimSpace(freq))
	interval := 1
	if parsed, err := strconv.Atoi(strings.TrimSpace(intervalValue)); err == nil && parsed > 1 {
		interval = parsed
	}

	switch freq {
	case "DAILY":
		if interval == 1 {
			return "Every day"
		}
		return fmt.Sprintf("Every %d days", interval)
	case "WEEKLY":
		if interval == 1 {
			return "Every week"
		}
		return fmt.Sprintf("Every %d weeks", interval)
	case "MONTHLY":
		if interval == 1 {
			return "Every month"
		}
		return fmt.Sprintf("Every %d months", interval)
	case "YEARLY":
		if interval == 1 {
			return "Every year"
		}
		return fmt.Sprintf("Every %d years", interval)
	default:
		return ""
	}
}

func recurrenceByDayLabel(value string) string {
	if strings.TrimSpace(value) == "" {
		return ""
	}

	labels := make([]string, 0)
	for _, token := range strings.Split(value, ",") {
		switch strings.ToUpper(strings.TrimSpace(token)) {
		case "MO":
			labels = append(labels, "Mon")
		case "TU":
			labels = append(labels, "Tue")
		case "WE":
			labels = append(labels, "Wed")
		case "TH":
			labels = append(labels, "Thu")
		case "FR":
			labels = append(labels, "Fri")
		case "SA":
			labels = append(labels, "Sat")
		case "SU":
			labels = append(labels, "Sun")
		}
	}
	if len(labels) == 0 {
		return ""
	}
	return "on " + strings.Join(labels, ", ")
}

func recurrenceCountLabel(value string) string {
	count, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || count <= 0 {
		return ""
	}
	if count == 1 {
		return "1 time"
	}
	return fmt.Sprintf("%d times", count)
}

func recurrenceUntilLabel(value string) string {
	raw := strings.TrimSpace(value)
	if raw == "" {
		return ""
	}

	layouts := []string{
		"20060102T150405Z",
		"20060102T150405",
		"20060102",
	}
	for _, layout := range layouts {
		parsed, err := time.Parse(layout, raw)
		if err != nil {
			continue
		}
		return "until " + parsed.UTC().Format("Jan 2, 2006")
	}
	return ""
}

func stringPtrFromUUID(value *openapi_types.UUID) *string {
	if value == nil {
		return nil
	}
	stringValue := value.String()
	return &stringValue
}

func stringPtrFromDirection(value *generated.GetCalendarEventsParamsDirection) *string {
	if value == nil {
		return nil
	}
	stringValue := string(*value)
	return &stringValue
}

func parseOptionalDateTime(value string) (*time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return nil, err
	}
	return &parsed, nil
}

func parseOptionalInt(value string) (*int32, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, nil
	}
	parsed, err := strconv.ParseInt(value, 10, 32)
	if err != nil {
		return nil, err
	}
	result := int32(parsed)
	return &result, nil
}
