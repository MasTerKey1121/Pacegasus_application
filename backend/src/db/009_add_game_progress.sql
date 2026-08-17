-- Gamification economy: balances are server-owned and every reward is idempotent.
CREATE TABLE IF NOT EXISTS user_game_progress (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  coin_balance INTEGER NOT NULL DEFAULT 0 CHECK (coin_balance >= 0),
  level SMALLINT NOT NULL DEFAULT 1 CHECK (level >= 1),
  exp INTEGER NOT NULL DEFAULT 0 CHECK (exp >= 0),
  exp_to_next INTEGER NOT NULL DEFAULT 200 CHECK (exp_to_next >= 200),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS game_reward_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_type VARCHAR(40) NOT NULL,
  source_id UUID NOT NULL,
  coins INTEGER NOT NULL CHECK (coins >= 0),
  exp INTEGER NOT NULL CHECK (exp >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source_type, source_id)
);

CREATE INDEX IF NOT EXISTS idx_game_reward_events_user_created
  ON game_reward_events (user_id, created_at DESC);

INSERT INTO user_game_progress (user_id)
SELECT id FROM users
ON CONFLICT (user_id) DO NOTHING;
