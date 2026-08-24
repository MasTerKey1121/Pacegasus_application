-- Soft delete for cancelled training-program registrations.
-- Cancelled programs are kept for history, while existing active-program queries ignore them.
ALTER TYPE program_status_enum ADD VALUE IF NOT EXISTS 'cancelled';

ALTER TABLE user_programs
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_user_programs_user_deleted_at
  ON user_programs (user_id, deleted_at)
  WHERE deleted_at IS NOT NULL;
