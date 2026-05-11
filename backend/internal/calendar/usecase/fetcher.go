package usecase

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type CalendarFeedFetchResult struct {
	Body         []byte
	ETag         *string
	LastModified *time.Time
	NotModified  bool
}

type CalendarFeedFetcher interface {
	Fetch(
		ctx context.Context,
		sourceURL string,
		etag *string,
		lastModified *time.Time,
	) (*CalendarFeedFetchResult, error)
}

type httpCalendarFeedFetcher struct {
	client *http.Client
}

func NewHTTPCalendarFeedFetcher(timeout time.Duration) CalendarFeedFetcher {
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	return &httpCalendarFeedFetcher{
		client: &http.Client{Timeout: timeout},
	}
}

func (f *httpCalendarFeedFetcher) Fetch(
	ctx context.Context,
	sourceURL string,
	etag *string,
	lastModified *time.Time,
) (*CalendarFeedFetchResult, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sourceURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create calendar fetch request: %w", err)
	}
	if etag != nil && strings.TrimSpace(*etag) != "" {
		req.Header.Set("If-None-Match", strings.TrimSpace(*etag))
	}
	if lastModified != nil && !lastModified.IsZero() {
		req.Header.Set("If-Modified-Since", lastModified.UTC().Format(http.TimeFormat))
	}

	resp, err := f.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch calendar URL: %w", err)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK:
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, fmt.Errorf("failed to read calendar response body: %w", err)
		}
		result := &CalendarFeedFetchResult{
			Body:         body,
			ETag:         stringPtrOrNil(resp.Header.Get("ETag")),
			LastModified: parseLastModified(resp.Header.Get("Last-Modified")),
		}
		return result, nil
	case http.StatusNotModified:
		return &CalendarFeedFetchResult{
			NotModified:  true,
			ETag:         stringPtrOrNil(resp.Header.Get("ETag")),
			LastModified: parseLastModified(resp.Header.Get("Last-Modified")),
		}, nil
	default:
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		message := strings.TrimSpace(string(body))
		if message == "" {
			message = resp.Status
		}
		return nil, fmt.Errorf("calendar fetch returned %d: %s", resp.StatusCode, message)
	}
}

func parseLastModified(value string) *time.Time {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	parsed, err := time.Parse(http.TimeFormat, value)
	if err != nil {
		return nil
	}
	parsed = parsed.UTC()
	return &parsed
}

func stringPtrOrNil(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return &value
}
