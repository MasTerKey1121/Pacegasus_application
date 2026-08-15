-- RPE (Rate of Perceived Exertion) records recorded after a running session.
DO $$
BEGIN
  CREATE TYPE rpe_mood_enum AS ENUM ('exhausted', 'bad', 'neutral', 'good', 'great');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS rpe_logs (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  running_session_id UUID REFERENCES running_sessions(id) ON DELETE SET NULL,
  duration_minutes   INTEGER NOT NULL CHECK (duration_minutes > 0),
  rpe_score          SMALLINT NOT NULL CHECK (rpe_score BETWEEN 1 AND 10),
  stress_level       SMALLINT NOT NULL CHECK (stress_level BETWEEN 1 AND 10),
  mood               rpe_mood_enum NOT NULL,
  has_pain           BOOLEAN NOT NULL DEFAULT FALSE,
  pain_note          TEXT,
  session_rpe        INTEGER NOT NULL CHECK (session_rpe = duration_minutes * rpe_score),
  logged_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_rpe_pain_note
    CHECK ((has_pain AND pain_note IS NOT NULL AND length(trim(pain_note)) > 0)
       OR (NOT has_pain AND pain_note IS NULL))
);

CREATE INDEX IF NOT EXISTS idx_rpe_logs_user_logged_at
  ON rpe_logs (user_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_rpe_logs_running_session
  ON rpe_logs (running_session_id)
  WHERE running_session_id IS NOT NULL;
