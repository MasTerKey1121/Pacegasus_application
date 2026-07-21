-- =====================================================================
-- Migration: 003_create_daily_wellness_checkins.sql
-- Additive migration — ต่อจาก schema.sql (users) และ 002_add_otp_ref.sql
-- ใช้ users(id) และ function set_updated_at() ที่มีอยู่แล้วใน schema.sql ร่วมกัน
-- ไม่ต้องสร้างซ้ำ, ปลอดภัยต่อการรันซ้ำ (IF NOT EXISTS)
--
-- Usage:
--   node src/db/migrate.js 003_create_daily_wellness_checkins.sql
-- =====================================================================

CREATE TABLE IF NOT EXISTS daily_wellness_checkins (
    checkin_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    checkin_date    DATE NOT NULL DEFAULT CURRENT_DATE,

    sleep_quality   SMALLINT NOT NULL CHECK (sleep_quality BETWEEN 1 AND 5),
    energy_level    SMALLINT NOT NULL CHECK (energy_level BETWEEN 1 AND 5),
    muscle_soreness SMALLINT NOT NULL CHECK (muscle_soreness BETWEEN 1 AND 5),
    stress_level    SMALLINT NOT NULL CHECK (stress_level BETWEEN 1 AND 5),
    motivation      SMALLINT NOT NULL CHECK (motivation BETWEEN 1 AND 5),

    wellness_score  NUMERIC(3,1) GENERATED ALWAYS AS (
        ROUND(
            ((sleep_quality + energy_level + (6 - muscle_soreness) + (6 - stress_level) + motivation) / 5.0)::numeric,
        1)
    ) STORED,

    note            TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_wellness_checkin_user_date UNIQUE (user_id, checkin_date)
);

CREATE INDEX IF NOT EXISTS idx_wellness_checkins_user_date
    ON daily_wellness_checkins (user_id, checkin_date DESC);

-- ใช้ set_updated_at() ที่มีอยู่แล้วใน schema.sql
DROP TRIGGER IF EXISTS trg_wellness_checkins_updated_at ON daily_wellness_checkins;
CREATE TRIGGER trg_wellness_checkins_updated_at
BEFORE UPDATE ON daily_wellness_checkins
FOR EACH ROW EXECUTE FUNCTION set_updated_at();