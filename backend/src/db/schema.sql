-- =====================================================================
-- Pacegasus Database Schema (fresh install)
-- PostgreSQL 14+ (compatible with Supabase PostgreSQL)
-- Scope of this migration:
--   1) Authentication: Email + OTP, Google OAuth
--   2) Onboarding (4 steps): basic info, injury history, goals, running history
-- Gamification / Adaptive Training tables are intentionally NOT included
-- here (out of scope for today's work) and can be added in a later migration.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- for gen_random_uuid()

-- ---------------------------------------------------------------------
-- ENUM TYPES
-- ---------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE auth_provider_enum AS ENUM ('email', 'google');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE user_role_enum AS ENUM ('guest', 'user', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE user_status_enum AS ENUM ('active', 'suspended', 'deleted');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE experience_level_enum AS ENUM ('beginner', 'intermediate', 'advanced', 'elite');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE gender_enum AS ENUM ('male', 'female', 'other', 'prefer_not_to_say');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE otp_purpose_enum AS ENUM ('register', 'login');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE preferred_environment_enum AS ENUM ('park', 'road', 'city', 'treadmill', 'trail');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE training_time_enum AS ENUM ('early_morning', 'morning', 'afternoon', 'evening', 'night');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------
-- CORE: users
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email                 VARCHAR(255) NOT NULL UNIQUE,
  email_verified        BOOLEAN NOT NULL DEFAULT FALSE,
  display_name          VARCHAR(150),
  avatar_url            TEXT,
  role                  user_role_enum NOT NULL DEFAULT 'user',
  status                user_status_enum NOT NULL DEFAULT 'active',
  onboarding_completed  BOOLEAN NOT NULL DEFAULT FALSE,
  onboarding_step       SMALLINT NOT NULL DEFAULT 0, -- 0 = not started, 1..4 = last completed step
  last_login_at         TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A user may have multiple sign-in methods linked to the same account
-- (e.g. registered by email OTP, later links Google) -- kept 1:1 per provider.
CREATE TABLE IF NOT EXISTS user_auth_providers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider          auth_provider_enum NOT NULL,
  provider_user_id  VARCHAR(255), -- Google "sub" claim; NULL for email provider
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_user_id),
  UNIQUE (user_id, provider)
);

-- ---------------------------------------------------------------------
-- AUTH: OTP codes (email login/register)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS otp_codes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         VARCHAR(255) NOT NULL,
  otp_hash      VARCHAR(255) NOT NULL, -- bcrypt hash of the 6-digit code, never store plaintext
  otp_ref       VARCHAR(8) NOT NULL,   -- reference code shown to the user (e.g. "K7X9QZ"); not secret,
                                        -- used to look up + disambiguate which OTP transaction is being verified
  purpose       otp_purpose_enum NOT NULL DEFAULT 'login',
  attempts      SMALLINT NOT NULL DEFAULT 0,
  max_attempts  SMALLINT NOT NULL DEFAULT 5,
  is_used       BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at    TIMESTAMPTZ NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (otp_ref)
);
CREATE INDEX IF NOT EXISTS idx_otp_codes_email ON otp_codes(email);
CREATE INDEX IF NOT EXISTS idx_otp_codes_email_created ON otp_codes(email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_otp_codes_ref ON otp_codes(otp_ref);

-- ---------------------------------------------------------------------
-- AUTH: refresh tokens (for JWT session rotation)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    VARCHAR(255) NOT NULL UNIQUE, -- sha256 hash of the refresh token
  device_info   VARCHAR(255),
  ip_address    VARCHAR(64),
  revoked       BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at    TIMESTAMPTZ NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);

-- ---------------------------------------------------------------------
-- ONBOARDING STEP 1: basic info
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_basic_info (
  user_id                     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  date_of_birth               DATE,
  gender                      gender_enum,
  height_cm                   NUMERIC(5,2),
  weight_kg                   NUMERIC(5,2),
  running_experience_level    experience_level_enum,
  weekly_distance_km          NUMERIC(6,2),
  running_days_per_week       SMALLINT CHECK (running_days_per_week BETWEEN 0 AND 7),
  timezone                    VARCHAR(64) NOT NULL DEFAULT 'Asia/Bangkok',
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- ONBOARDING STEP 2: injury history
-- ---------------------------------------------------------------------
-- Summary flag answered directly on the onboarding screen ("have you been injured?")
CREATE TABLE IF NOT EXISTS user_injury_summary (
  user_id             UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  has_injury_history  BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Detailed list, only populated when has_injury_history = true
CREATE TABLE IF NOT EXISTS user_injuries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body_part     VARCHAR(100) NOT NULL, -- e.g. knee, ankle, IT band, lower back
  injury_type   VARCHAR(150),
  severity      SMALLINT CHECK (severity BETWEEN 1 AND 10),
  is_current    BOOLEAN NOT NULL DEFAULT FALSE,
  occurred_at   DATE,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_user_injuries_user_id ON user_injuries(user_id);

-- ---------------------------------------------------------------------
-- ONBOARDING STEP 3: goals
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_goals (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  goal_type                 VARCHAR(50) NOT NULL, -- lose_weight | run_5k | run_10k | half_marathon | marathon | general_fitness | improve_pace | stay_consistent
  target_distance_km        NUMERIC(6,2),
  target_date               DATE,
  target_pace_sec_per_km    INT,
  is_primary                BOOLEAN NOT NULL DEFAULT FALSE,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_user_goals_user_id ON user_goals(user_id);

-- ---------------------------------------------------------------------
-- ONBOARDING STEP 4: running history
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_running_history (
  user_id                       UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  has_run_before                BOOLEAN NOT NULL DEFAULT FALSE,
  years_running                 NUMERIC(4,1),
  best_5k_seconds                INT,
  best_10k_seconds               INT,
  best_half_marathon_seconds     INT,
  best_marathon_seconds          INT,
  preferred_environment          preferred_environment_enum,
  typical_training_time          training_time_enum,
  connected_strava               BOOLEAN NOT NULL DEFAULT FALSE,
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Auto-update updated_at columns
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_basic_info_updated_at ON user_basic_info;
CREATE TRIGGER trg_basic_info_updated_at BEFORE UPDATE ON user_basic_info
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_running_history_updated_at ON user_running_history;
CREATE TRIGGER trg_running_history_updated_at BEFORE UPDATE ON user_running_history
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_injury_summary_updated_at ON user_injury_summary;
CREATE TRIGGER trg_injury_summary_updated_at BEFORE UPDATE ON user_injury_summary
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();