package usecase

import (
	"context"
	"log"
	"time"
)

type SyncCoordinator struct {
	Usecase  *Usecase
	Interval time.Duration
	Limit    int
	Logger   *log.Logger
}

func (c *SyncCoordinator) Start(ctx context.Context) {
	if c == nil || c.Usecase == nil {
		return
	}
	interval := c.Interval
	if interval <= 0 {
		interval = time.Minute
	}
	limit := c.Limit
	if limit <= 0 {
		limit = 25
	}

	go func() {
		c.runOnce(ctx, limit)

		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				c.runOnce(ctx, limit)
			}
		}
	}()
}

func (c *SyncCoordinator) runOnce(ctx context.Context, limit int) {
	refreshed, err := c.Usecase.RefreshDueCalendarSources(ctx, limit)
	if err != nil {
		if c.Logger != nil {
			c.Logger.Printf("calendar sync iteration failed: %v", err)
		}
		return
	}
	if refreshed > 0 && c.Logger != nil {
		c.Logger.Printf("calendar sync refreshed %d linked source(s)", refreshed)
	}
}
