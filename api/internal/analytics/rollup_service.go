package analytics

import (
	"errors"
	"time"
)

var (
	ErrInvalidHourBucket = errors.New("hour bucket must be aligned to top of hour (00:00)")
)

type CategoryCount struct {
	Total   int64 `json:"total"`
	Blocked int64 `json:"blocked"`
	Allowed int64 `json:"allowed"`
}

type IngestRollupRequest struct {
	DeviceID          string                   `json:"device_id"`
	HourBucketEpochMs int64                    `json:"hour_bucket_epoch_ms"`
	CategoryCounts    map[string]CategoryCount `json:"category_counts"`
}

func ValidateHourBucket(bucketMs int64) bool {
	// A valid hour bucket is divisible by 3,600,000 ms (1 hour)
	return bucketMs%3600000 == 0
}

type AnalyticsSummary struct {
	TimeRange        string                   `json:"time_range"` // "24h", "7d", "30d", "2y"
	TotalQueries     int64                    `json:"total_queries"`
	BlockedQueries   int64                    `json:"blocked_queries"`
	AllowedQueries   int64                    `json:"allowed_queries"`
	BlockedPercent   float64                  `json:"blocked_percentage"`
	Categories       map[string]CategoryCount `json:"categories"`
	HourlyDataPoints []HourlyDataPoint        `json:"hourly_data_points"`
}

type HourlyDataPoint struct {
	TimestampEpochMs int64 `json:"timestamp_epoch_ms"`
	TotalQueries     int64 `json:"total_queries"`
	BlockedQueries   int64 `json:"blocked_queries"`
}

// TruncateToHour returns the timestamp rounded down to the nearest hour.
func TruncateToHour(t time.Time) time.Time {
	return t.Truncate(time.Hour)
}
