-- FocusDNS PostgreSQL 16 Production Schema
-- Local-First, Privacy-First, Zero-Countdown Architecture

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table (Argon2id + TOTP 2FA)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL, -- Argon2id encoded string
    totp_secret VARCHAR(255),
    totp_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Registered client devices with Ed25519 public key binding
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(64) UNIQUE NOT NULL,
    platform VARCHAR(32) NOT NULL, -- 'android', 'ios', 'extension', 'macos', 'linux', 'windows'
    ed25519_public_key VARCHAR(64) NOT NULL,
    device_name VARCHAR(128),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Synced sessions with precomputed absolute timelines
CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(64) PRIMARY KEY, -- e.g. 'ses_1700000000000_1234'
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
    mode VARCHAR(32) NOT NULL, -- 'NORMAL', 'STRICT', 'CYCLES', 'FEED_ONLY'
    primary_state VARCHAR(32) NOT NULL, -- 'ACTIVE_NORMAL', 'STRICT_RUNNING', 'CYCLES_RUNNING', 'PAUSED', 'COMPLETED'
    wall_start_epoch_ms BIGINT NOT NULL,
    mono_start_ms BIGINT NOT NULL,
    total_target_end_epoch_ms BIGINT NOT NULL,
    is_strict_lockout BOOLEAN NOT NULL DEFAULT FALSE,
    timeline_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Immutable append-only session event journal with strict idempotency
CREATE TABLE IF NOT EXISTS session_events (
    id VARCHAR(64) PRIMARY KEY,
    session_id VARCHAR(64) NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    sequence_number BIGINT NOT NULL,
    timestamp_epoch_ms BIGINT NOT NULL,
    mono_timestamp_ms BIGINT NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    idempotency_key VARCHAR(128) UNIQUE NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Privacy-First Hourly Analytics Rollups (Option A)
-- ZERO individual domain lookups or URLs are uploaded or stored.
-- Retained at 1-hour resolution for 30 days, aggregated to daily/monthly for 2 years.
CREATE TABLE IF NOT EXISTS hourly_analytics_rollups (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    hour_bucket_epoch_ms BIGINT NOT NULL, -- Truncated to start of hour
    category VARCHAR(64) NOT NULL, -- 'social', 'adult', 'gambling', 'piracy', 'productivity', 'system'
    total_queries BIGINT NOT NULL DEFAULT 0,
    blocked_queries BIGINT NOT NULL DEFAULT 0,
    allowed_queries BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uniq_user_device_hour_cat UNIQUE(user_id, device_id, hour_bucket_epoch_ms, category)
);

-- Cryptographically signed Ed25519 dynamic delta rule packs
CREATE TABLE IF NOT EXISTS rule_packs (
    pack_id VARCHAR(64) PRIMARY KEY,
    version INT NOT NULL,
    kill_switch BOOLEAN NOT NULL DEFAULT FALSE,
    exact_blocked_domains JSONB NOT NULL,
    wildcard_suffixes JSONB NOT NULL,
    signature_ed25519_hex VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for high-throughput queries
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_events_session_seq ON session_events(session_id, sequence_number);
CREATE INDEX IF NOT EXISTS idx_hourly_analytics_user_hour ON hourly_analytics_rollups(user_id, hour_bucket_epoch_ms);
