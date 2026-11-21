package session

import (
	"errors"
	"fmt"
)

var (
	ErrOutOfBounds         = errors.New("ERR_OUT_OF_BOUNDS")
	ErrInvalidPauseDuration = errors.New("ERR_INVALID_PAUSE_DURATION")
	ErrPauseNotAllowed     = errors.New("ERR_PAUSE_NOT_ALLOWED")
	ErrStrictLockoutActive = errors.New("ERR_STRICT_LOCKOUT_ACTIVE")
)

type SessionMode string

const (
	ModeNormal   SessionMode = "NORMAL"
	ModeStrict   SessionMode = "STRICT"
	ModeCycles   SessionMode = "CYCLES"
	ModeFeedOnly SessionMode = "FEED_ONLY"
)

type PrimaryState string

const (
	StateInactive      PrimaryState = "INACTIVE"
	StateActiveNormal  PrimaryState = "ACTIVE_NORMAL"
	StateActiveFeed    PrimaryState = "ACTIVE_FEED"
	StatePaused        PrimaryState = "PAUSED"
	StateStrictRunning PrimaryState = "STRICT_RUNNING"
	StateCyclesRunning PrimaryState = "CYCLES_RUNNING"
	StateCompleted     PrimaryState = "COMPLETED"
)

type PhaseType string

const (
	PhaseIdle                 PhaseType = "IDLE"
	PhasePreparationGrace     PhaseType = "PREPARATION_GRACE"
	PhaseFocusSession         PhaseType = "FOCUS_SESSION"
	PhaseBreakSession         PhaseType = "BREAK_SESSION"
	PhaseBreakExpiringGrace   PhaseType = "BREAK_EXPIRING_GRACE"
	PhaseAppTerminationSweep PhaseType = "APP_TERMINATION_SWEEP"
	PhaseCompleted            PhaseType = "COMPLETED"
)

type PhaseInterval struct {
	PhaseIndex   int       `json:"phase_index"`
	PhaseType    PhaseType `json:"phase_type"`
	CycleNumber  int       `json:"cycle_number"`
	StartEpochMs int64     `json:"start_epoch_ms"`
	EndEpochMs   int64     `json:"end_epoch_ms"`
}

type SessionConfig struct {
	Mode                   SessionMode `json:"mode"`
	StrictMinutes          int         `json:"strict_minutes"`
	FocusMinutes           int         `json:"focus_minutes"`
	BreakMinutes           int         `json:"break_minutes"`
	TotalCycles            int         `json:"total_cycles"`
	AutoTerminateOnBreakEnd bool       `json:"auto_terminate_on_break_end"`
	Label                  string      `json:"label"`
}

func (c *SessionConfig) Validate() error {
	switch c.Mode {
	case ModeStrict:
		if c.StrictMinutes < 5 || c.StrictMinutes > 480 {
			return ErrOutOfBounds
		}
	case ModeCycles:
		if c.FocusMinutes < 5 || c.FocusMinutes > 480 ||
			c.BreakMinutes < 5 || c.BreakMinutes > 30 ||
			c.TotalCycles < 1 || c.TotalCycles > 12 {
			return ErrOutOfBounds
		}
	}
	return nil
}

type SessionSnapshot struct {
	SessionID             string          `json:"session_id"`
	UserID                string          `json:"user_id"`
	DeviceID              string          `json:"device_id"`
	PrimaryState          PrimaryState    `json:"primary_state"`
	ActivePhase           PhaseType       `json:"active_phase"`
	Config                SessionConfig   `json:"config"`
	WallStartEpochMs      int64           `json:"wall_start_epoch_ms"`
	MonoStartMs           int64           `json:"mono_start_ms"`
	TotalTargetEndEpochMs int64           `json:"total_target_end_epoch_ms"`
	Phases                []PhaseInterval `json:"phases"`
	ActivePhaseIndex      int             `json:"active_phase_index"`
	IsStrictLockout       bool            `json:"is_strict_lockout"`
	PauseEndEpochMs       *int64          `json:"pause_end_epoch_ms,omitempty"`
}

// BuildCyclesTimeline calculates absolute start/end timestamps for cycles.
func BuildCyclesTimeline(startMs int64, cfg *SessionConfig) (int64, []PhaseInterval) {
	fMs := int64(cfg.FocusMinutes * 60 * 1000)
	bMs := int64(cfg.BreakMinutes * 60 * 1000)
	prepGraceMs := int64(10 * 1000)
	breakGraceMs := int64(30 * 1000)

	var phases []PhaseInterval
	curr := startMs
	idx := 0

	// Initial Prep Grace
	phases = append(phases, PhaseInterval{
		PhaseIndex:   idx,
		PhaseType:    PhasePreparationGrace,
		CycleNumber:  1,
		StartEpochMs: curr,
		EndEpochMs:   curr + prepGraceMs,
	})
	idx++
	curr += prepGraceMs

	for c := 1; c <= cfg.TotalCycles; c++ {
		// Focus
		phases = append(phases, PhaseInterval{
			PhaseIndex:   idx,
			PhaseType:    PhaseFocusSession,
			CycleNumber:  c,
			StartEpochMs: curr,
			EndEpochMs:   curr + fMs,
		})
		idx++
		curr += fMs

		// Main Break
		mainBreakMs := bMs - breakGraceMs
		if mainBreakMs < 0 {
			mainBreakMs = 0
		}
		phases = append(phases, PhaseInterval{
			PhaseIndex:   idx,
			PhaseType:    PhaseBreakSession,
			CycleNumber:  c,
			StartEpochMs: curr,
			EndEpochMs:   curr + mainBreakMs,
		})
		idx++
		curr += mainBreakMs

		// Break Grace
		phases = append(phases, PhaseInterval{
			PhaseIndex:   idx,
			PhaseType:    PhaseBreakExpiringGrace,
			CycleNumber:  c,
			StartEpochMs: curr,
			EndEpochMs:   curr + breakGraceMs,
		})
		idx++
		curr += breakGraceMs
	}

	phases = append(phases, PhaseInterval{
		PhaseIndex:   idx,
		PhaseType:    PhaseCompleted,
		CycleNumber:  cfg.TotalCycles,
		StartEpochMs: curr,
		EndEpochMs:   curr,
	})

	return curr, phases
}
