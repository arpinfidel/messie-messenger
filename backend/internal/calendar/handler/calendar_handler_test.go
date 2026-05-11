package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"sort"
	"testing"
	"time"

	"messenger/backend/api/generated"
	"messenger/backend/internal/calendar/entity"
	"messenger/backend/internal/calendar/usecase"
	"messenger/backend/pkg/middleware"

	"github.com/google/uuid"
	openapi_types "github.com/oapi-codegen/runtime/types"
)

type handlerSourceRepo struct {
	sources map[string]entity.CalendarSource
}

func newHandlerSourceRepo() *handlerSourceRepo {
	return &handlerSourceRepo{sources: map[string]entity.CalendarSource{}}
}

func (r *handlerSourceRepo) CreateCalendarSource(ctx context.Context, source *entity.CalendarSource) error {
	r.sources[source.ID] = *source
	return nil
}

func (r *handlerSourceRepo) GetCalendarSourceByID(ctx context.Context, id string) (*entity.CalendarSource, error) {
	source, ok := r.sources[id]
	if !ok {
		return nil, entity.ErrNotFound
	}
	return &source, nil
}

func (r *handlerSourceRepo) GetCalendarSourcesByUserID(ctx context.Context, userID string) ([]entity.CalendarSource, error) {
	var result []entity.CalendarSource
	for _, source := range r.sources {
		if source.UserID == userID {
			result = append(result, source)
		}
	}
	return result, nil
}

func (r *handlerSourceRepo) GetCalendarSourcesDueForRefresh(ctx context.Context, before time.Time, limit int) ([]entity.CalendarSource, error) {
	var result []entity.CalendarSource
	for _, source := range r.sources {
		if source.ImportMode != entity.CalendarImportModeLink {
			continue
		}
		if source.NextRefreshAt == nil || !source.NextRefreshAt.After(before) {
			result = append(result, source)
		}
		if limit > 0 && len(result) >= limit {
			break
		}
	}
	return result, nil
}

func (r *handlerSourceRepo) UpdateCalendarSource(ctx context.Context, source *entity.CalendarSource) error {
	r.sources[source.ID] = *source
	return nil
}

func (r *handlerSourceRepo) DeleteCalendarSource(ctx context.Context, id string) error {
	delete(r.sources, id)
	return nil
}

type handlerEventRepo struct {
	sourceRepo *handlerSourceRepo
	events     map[string]entity.CalendarEvent
}

func newHandlerEventRepo(sourceRepo *handlerSourceRepo) *handlerEventRepo {
	return &handlerEventRepo{
		sourceRepo: sourceRepo,
		events:     map[string]entity.CalendarEvent{},
	}
}

func (r *handlerEventRepo) CreateCalendarEvents(ctx context.Context, events []entity.CalendarEvent) error {
	for _, event := range events {
		source := r.sourceRepo.sources[event.SourceID]
		event.Source = source
		r.events[event.ID] = event
	}
	return nil
}

func (r *handlerEventRepo) DeleteCalendarEventsBySourceID(ctx context.Context, sourceID string) error {
	for id, event := range r.events {
		if event.SourceID == sourceID {
			delete(r.events, id)
		}
	}
	return nil
}

func (r *handlerEventRepo) GetCalendarEventByID(ctx context.Context, id string, userID string) (*entity.CalendarEvent, error) {
	event, ok := r.events[id]
	if !ok || event.Source.UserID != userID {
		return nil, entity.ErrNotFound
	}
	return &event, nil
}

func (r *handlerEventRepo) GetCalendarEvents(
	ctx context.Context,
	userID string,
	from *time.Time,
	to *time.Time,
	sourceID *string,
	cursor *time.Time,
	direction *string,
	limit *int,
) ([]entity.CalendarEvent, error) {
	var result []entity.CalendarEvent
	directionValue := "after"
	if direction != nil && *direction != "" {
		directionValue = *direction
	}
	for _, event := range r.events {
		if event.Source.UserID != userID {
			continue
		}
		if sourceID != nil && *sourceID != "" && event.SourceID != *sourceID {
			continue
		}
		if from != nil && event.EndsAt.Before(*from) {
			continue
		}
		if to != nil && event.StartsAt.After(*to) {
			continue
		}
		if cursor != nil {
			if directionValue == "before" && !event.StartsAt.Before(*cursor) {
				continue
			}
			if directionValue != "before" && event.StartsAt.Before(*cursor) {
				continue
			}
		}
		result = append(result, event)
	}
	sort.Slice(result, func(i, j int) bool {
		if directionValue == "before" {
			return result[i].StartsAt.After(result[j].StartsAt)
		}
		return result[i].StartsAt.Before(result[j].StartsAt)
	})
	if limit != nil && *limit > 0 && len(result) > *limit {
		result = result[:*limit]
	}
	if directionValue == "before" {
		for left, right := 0, len(result)-1; left < right; left, right = left+1, right-1 {
			result[left], result[right] = result[right], result[left]
		}
	}
	return result, nil
}

func (r *handlerEventRepo) GetUpcomingCalendarEvents(ctx context.Context, userID string, from time.Time, limit int) ([]entity.CalendarEvent, error) {
	var result []entity.CalendarEvent
	for _, event := range r.events {
		if event.Source.UserID == userID && !event.EndsAt.Before(from) {
			result = append(result, event)
		}
	}
	return result, nil
}

func newCalendarHandlerForTests() (*CalendarHandler, *handlerSourceRepo, *handlerEventRepo) {
	sourceRepo := newHandlerSourceRepo()
	eventRepo := newHandlerEventRepo(sourceRepo)
	uc := usecase.NewUsecase(sourceRepo, eventRepo, usecase.NewCalendarICSParser())
	uc.Now = func() time.Time { return time.Date(2026, 4, 21, 12, 0, 0, 0, time.UTC) }
	uc.Fetcher = &fakeHandlerCalendarFetcher{
		result: &usecase.CalendarFeedFetchResult{
			Body: []byte("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nX-WR-CALNAME:Linked Work\r\nBEGIN:VEVENT\r\nUID:event-1@example.com\r\nDTSTAMP:20260421T100000Z\r\nDTSTART:20260422T150000Z\r\nDTEND:20260422T160000Z\r\nSUMMARY:Planning\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"),
		},
	}
	return NewCalendarHandler(uc), sourceRepo, eventRepo
}

type fakeHandlerCalendarFetcher struct {
	result *usecase.CalendarFeedFetchResult
	err    error
}

func (f *fakeHandlerCalendarFetcher) Fetch(
	ctx context.Context,
	sourceURL string,
	etag *string,
	lastModified *time.Time,
) (*usecase.CalendarFeedFetchResult, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.result, nil
}

func withUserID(req *http.Request, userID string) *http.Request {
	ctx := context.WithValue(req.Context(), middleware.ContextKeyUserID, userID)
	return req.WithContext(ctx)
}

func TestCalendarHandlerImportAndSourceLifecycle(t *testing.T) {
	handler, sourceRepo, _ := newCalendarHandlerForTests()
	const userID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	fileWriter, err := writer.CreateFormFile("file", "work.ics")
	if err != nil {
		t.Fatalf("CreateFormFile() error = %v", err)
	}
	const input = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nX-WR-CALNAME:Imported Work\r\nBEGIN:VEVENT\r\nUID:event-1@example.com\r\nDTSTAMP:20260421T100000Z\r\nDTSTART:20260422T150000Z\r\nDTEND:20260422T160000Z\r\nSUMMARY:Planning\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
	if _, err := fileWriter.Write([]byte(input)); err != nil {
		t.Fatalf("Write() error = %v", err)
	}
	if err := writer.WriteField("display_name", "Override Name"); err != nil {
		t.Fatalf("WriteField() error = %v", err)
	}
	if err := writer.WriteField("category", "Work"); err != nil {
		t.Fatalf("WriteField() error = %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}

	request := httptest.NewRequest(http.MethodPost, "/calendar/sources/import", &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	recorder := httptest.NewRecorder()

	handler.ImportCalendarSource(recorder, withUserID(request, userID))
	if recorder.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d, body=%s", recorder.Code, http.StatusCreated, recorder.Body.String())
	}

	var response generated.CalendarImportResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("Unmarshal() error = %v", err)
	}
	if response.Source.DisplayName != "Override Name" {
		t.Fatalf("DisplayName = %q, want %q", response.Source.DisplayName, "Override Name")
	}
	if response.Source.Category != "Work" {
		t.Fatalf("Category = %v, want %q", response.Source.Category, "Work")
	}
	if response.ImportedEventCount != 1 {
		t.Fatalf("ImportedEventCount = %d, want 1", response.ImportedEventCount)
	}

	sourceID := response.Source.Id

	listReq := httptest.NewRequest(http.MethodGet, "/calendar/sources", nil)
	listRec := httptest.NewRecorder()
	handler.GetCalendarSources(listRec, withUserID(listReq, userID))
	if listRec.Code != http.StatusOK {
		t.Fatalf("list status = %d, want %d", listRec.Code, http.StatusOK)
	}

	getReq := httptest.NewRequest(http.MethodGet, "/calendar/sources/"+sourceID.String(), nil)
	getRec := httptest.NewRecorder()
	handler.GetCalendarSourceById(getRec, withUserID(getReq, userID), sourceID)
	if getRec.Code != http.StatusOK {
		t.Fatalf("get status = %d, want %d", getRec.Code, http.StatusOK)
	}

	forbiddenProbeReq := httptest.NewRequest(http.MethodGet, "/calendar/sources/"+sourceID.String(), nil)
	forbiddenProbeRec := httptest.NewRecorder()
	handler.GetCalendarSourceById(forbiddenProbeRec, withUserID(forbiddenProbeReq, "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"), sourceID)
	if forbiddenProbeRec.Code != http.StatusNotFound {
		t.Fatalf("cross-user get status = %d, want %d", forbiddenProbeRec.Code, http.StatusNotFound)
	}

	deleteReq := httptest.NewRequest(http.MethodDelete, "/calendar/sources/"+sourceID.String(), nil)
	deleteRec := httptest.NewRecorder()
	handler.DeleteCalendarSource(deleteRec, withUserID(deleteReq, userID), sourceID)
	if deleteRec.Code != http.StatusNoContent {
		t.Fatalf("delete status = %d, want %d", deleteRec.Code, http.StatusNoContent)
	}
	if _, ok := sourceRepo.sources[sourceID.String()]; ok {
		t.Fatalf("source %s still exists after delete", sourceID)
	}
}

func TestCalendarHandlerGetEventsAndUpcoming(t *testing.T) {
	handler, sourceRepo, eventRepo := newCalendarHandlerForTests()
	const userID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	sourceRepo.sources["11111111-1111-1111-1111-111111111111"] = entity.CalendarSource{
		ID:          "11111111-1111-1111-1111-111111111111",
		UserID:      userID,
		DisplayName: "Work",
	}
	source := sourceRepo.sources["11111111-1111-1111-1111-111111111111"]
	eventRepo.events["22222222-2222-2222-2222-222222222222"] = entity.CalendarEvent{
		ID:          "22222222-2222-2222-2222-222222222222",
		SourceID:    source.ID,
		Source:      source,
		ExternalUID: "uid-1",
		Title:       "Planning",
		Description: "",
		Location:    "",
		StartsAt:    time.Date(2026, 4, 22, 15, 0, 0, 0, time.UTC),
		EndsAt:      time.Date(2026, 4, 22, 16, 0, 0, 0, time.UTC),
		Status:      "CONFIRMED",
		Timezone:    "UTC",
	}
	eventRepo.events["33333333-3333-3333-3333-333333333333"] = entity.CalendarEvent{
		ID:          "33333333-3333-3333-3333-333333333333",
		SourceID:    source.ID,
		Source:      source,
		ExternalUID: "uid-2",
		Title:       "Retro",
		Description: "",
		Location:    "",
		StartsAt:    time.Date(2026, 4, 30, 15, 0, 0, 0, time.UTC),
		EndsAt:      time.Date(2026, 4, 30, 16, 0, 0, 0, time.UTC),
		Status:      "CONFIRMED",
		Timezone:    "UTC",
	}
	recurrence := "FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6"
	eventRepo.events["44444444-4444-4444-4444-444444444444"] = entity.CalendarEvent{
		ID:            "44444444-4444-4444-4444-444444444444",
		SourceID:      source.ID,
		Source:        source,
		ExternalUID:   "uid-3",
		Title:         "Class",
		Description:   "",
		Location:      "",
		StartsAt:      time.Date(2026, 4, 28, 15, 0, 0, 0, time.UTC),
		EndsAt:        time.Date(2026, 4, 28, 16, 0, 0, 0, time.UTC),
		Status:        "CONFIRMED",
		Timezone:      "UTC",
		RecurrenceRaw: &recurrence,
	}
	sourceID := openapi_types.UUID(uuid.MustParse(source.ID))

	rangeReq := httptest.NewRequest(http.MethodGet, "/calendar/events", nil)
	rangeRec := httptest.NewRecorder()
	from := time.Date(2026, 4, 22, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 4, 23, 0, 0, 0, 0, time.UTC)
	handler.GetCalendarEvents(
		rangeRec,
		withUserID(rangeReq, userID),
		generated.GetCalendarEventsParams{
			From:     &from,
			To:       &to,
			SourceId: &sourceID,
		},
	)
	if rangeRec.Code != http.StatusOK {
		t.Fatalf("range status = %d, want %d", rangeRec.Code, http.StatusOK)
	}
	var rangeEvents []generated.CalendarEvent
	if err := json.Unmarshal(rangeRec.Body.Bytes(), &rangeEvents); err != nil {
		t.Fatalf("Unmarshal() range error = %v", err)
	}
	if len(rangeEvents) != 1 || rangeEvents[0].Title != "Planning" {
		t.Fatalf("range events = %+v, want only Planning", rangeEvents)
	}

	cursorReq := httptest.NewRequest(http.MethodGet, "/calendar/events", nil)
	cursorRec := httptest.NewRecorder()
	cursor := time.Date(2026, 4, 30, 0, 0, 0, 0, time.UTC)
	direction := generated.GetCalendarEventsParamsDirection("before")
	cursorLimit := 1
	handler.GetCalendarEvents(
		cursorRec,
		withUserID(cursorReq, userID),
		generated.GetCalendarEventsParams{
			Cursor:    &cursor,
			Direction: &direction,
			Limit:     &cursorLimit,
		},
	)
	if cursorRec.Code != http.StatusOK {
		t.Fatalf("cursor status = %d, want %d", cursorRec.Code, http.StatusOK)
	}
	var cursorEvents []generated.CalendarEvent
	if err := json.Unmarshal(cursorRec.Body.Bytes(), &cursorEvents); err != nil {
		t.Fatalf("Unmarshal() cursor error = %v", err)
	}
	if len(cursorEvents) != 1 || cursorEvents[0].Title != "Class" {
		t.Fatalf("cursor events = %+v, want only Class", cursorEvents)
	}

	eventReq := httptest.NewRequest(http.MethodGet, "/calendar/events/44444444-4444-4444-4444-444444444444", nil)
	eventRec := httptest.NewRecorder()
	handler.GetCalendarEventById(
		eventRec,
		withUserID(eventReq, userID),
		openapi_types.UUID(uuid.MustParse("44444444-4444-4444-4444-444444444444")),
	)
	if eventRec.Code != http.StatusOK {
		t.Fatalf("event status = %d, want %d", eventRec.Code, http.StatusOK)
	}
	var recurringEvent generated.CalendarEvent
	if err := json.Unmarshal(eventRec.Body.Bytes(), &recurringEvent); err != nil {
		t.Fatalf("Unmarshal() recurring event error = %v", err)
	}
	if recurringEvent.RecurrenceSummary == nil || *recurringEvent.RecurrenceSummary != "Every week, on Mon, Wed, Fri, 6 times" {
		t.Fatalf("RecurrenceSummary = %v, want weekly summary", recurringEvent.RecurrenceSummary)
	}
	if bytes.Contains(eventRec.Body.Bytes(), []byte("recurrence_raw")) {
		t.Fatalf("event response leaked recurrence_raw: %s", eventRec.Body.String())
	}
	if bytes.Contains(eventRec.Body.Bytes(), []byte("raw_ics_blob")) {
		t.Fatalf("event response leaked raw_ics_blob: %s", eventRec.Body.String())
	}

	upcomingReq := httptest.NewRequest(http.MethodGet, "/calendar/upcoming", nil)
	upcomingRec := httptest.NewRecorder()
	limit := int32(10)
	handler.GetUpcomingCalendarEvents(
		upcomingRec,
		withUserID(upcomingReq, userID),
		generated.GetUpcomingCalendarEventsParams{Limit: &limit},
	)
	if upcomingRec.Code != http.StatusOK {
		t.Fatalf("upcoming status = %d, want %d", upcomingRec.Code, http.StatusOK)
	}
	var upcomingEvents []generated.CalendarEvent
	if err := json.Unmarshal(upcomingRec.Body.Bytes(), &upcomingEvents); err != nil {
		t.Fatalf("Unmarshal() upcoming error = %v", err)
	}
	if len(upcomingEvents) != 3 {
		t.Fatalf("len(upcomingEvents) = %d, want 3", len(upcomingEvents))
	}
}

func TestCalendarHandlerLinkedSourceLifecycle(t *testing.T) {
	handler, sourceRepo, _ := newCalendarHandlerForTests()
	const userID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

	createReq := httptest.NewRequest(
		http.MethodPost,
		"/calendar/sources/link",
		bytes.NewBufferString(`{"url":"https://calendar.example.com/feed.ics","category":"Team","display_name":"Team Calendar"}`),
	)
	createReq.Header.Set("Content-Type", "application/json")
	createRec := httptest.NewRecorder()
	handler.CreateLinkedCalendarSource(createRec, withUserID(createReq, userID))
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create status = %d, want %d, body=%s", createRec.Code, http.StatusCreated, createRec.Body.String())
	}

	var createResponse generated.CalendarImportResponse
	if err := json.Unmarshal(createRec.Body.Bytes(), &createResponse); err != nil {
		t.Fatalf("Unmarshal(create) error = %v", err)
	}
	if createResponse.Source.ImportMode != entity.CalendarImportModeLink {
		t.Fatalf("ImportMode = %q, want %q", createResponse.Source.ImportMode, entity.CalendarImportModeLink)
	}

	sourceID := createResponse.Source.Id

	updateReq := httptest.NewRequest(
		http.MethodPatch,
		"/calendar/sources/"+sourceID.String(),
		bytes.NewBufferString(`{"category":"Ops","display_name":"Renamed Calendar"}`),
	)
	updateReq.Header.Set("Content-Type", "application/json")
	updateRec := httptest.NewRecorder()
	handler.UpdateCalendarSource(updateRec, withUserID(updateReq, userID), sourceID)
	if updateRec.Code != http.StatusOK {
		t.Fatalf("update status = %d, want %d, body=%s", updateRec.Code, http.StatusOK, updateRec.Body.String())
	}

	refreshReq := httptest.NewRequest(
		http.MethodPost,
		"/calendar/sources/"+sourceID.String()+"/refresh",
		nil,
	)
	refreshRec := httptest.NewRecorder()
	handler.RefreshCalendarSource(refreshRec, withUserID(refreshReq, userID), sourceID)
	if refreshRec.Code != http.StatusOK {
		t.Fatalf("refresh status = %d, want %d, body=%s", refreshRec.Code, http.StatusOK, refreshRec.Body.String())
	}

	source := sourceRepo.sources[sourceID.String()]
	if source.DisplayName != "Renamed Calendar" {
		t.Fatalf("DisplayName = %q, want %q", source.DisplayName, "Renamed Calendar")
	}
	if source.Category != "Ops" {
		t.Fatalf("Category = %v, want %q", source.Category, "Ops")
	}
	if source.ImportMode != entity.CalendarImportModeLink {
		t.Fatalf("ImportMode = %q, want %q", source.ImportMode, entity.CalendarImportModeLink)
	}
}

func TestCalendarHandlerRejectsBlankCategory(t *testing.T) {
	handler, _, _ := newCalendarHandlerForTests()
	const userID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

	createReq := httptest.NewRequest(
		http.MethodPost,
		"/calendar/sources/link",
		bytes.NewBufferString(`{"url":"https://calendar.example.com/feed.ics","category":"   ","display_name":"Team Calendar"}`),
	)
	createReq.Header.Set("Content-Type", "application/json")
	createRec := httptest.NewRecorder()
	handler.CreateLinkedCalendarSource(createRec, withUserID(createReq, userID))
	if createRec.Code != http.StatusBadRequest {
		t.Fatalf("create status = %d, want %d, body=%s", createRec.Code, http.StatusBadRequest, createRec.Body.String())
	}

	updateReq := httptest.NewRequest(
		http.MethodPatch,
		"/calendar/sources/11111111-1111-1111-1111-111111111111",
		bytes.NewBufferString(`{"category":"   ","display_name":"Renamed Calendar"}`),
	)
	updateReq.Header.Set("Content-Type", "application/json")
	updateRec := httptest.NewRecorder()
	handler.UpdateCalendarSource(
		updateRec,
		withUserID(updateReq, userID),
		openapi_types.UUID(uuid.MustParse("11111111-1111-1111-1111-111111111111")),
	)
	if updateRec.Code != http.StatusBadRequest {
		t.Fatalf("update status = %d, want %d, body=%s", updateRec.Code, http.StatusBadRequest, updateRec.Body.String())
	}
}
