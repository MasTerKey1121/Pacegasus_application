const db = require('../config/db');

const LEVEL_ONE_EXP_TO_NEXT = 200;
const EXP_STEP_PER_LEVEL = 10;

function toPayload(row) {
  return { coinBalance: row.coin_balance, level: row.level, exp: row.exp, expToNext: row.exp_to_next };
}

async function ensureProgress(client, userId) {
  await client.query(
    `INSERT INTO user_game_progress (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`,
    [userId]
  );
}

async function getProgress(userId) {
  const client = await db.getClient();
  try {
    await ensureProgress(client, userId);
    const { rows } = await client.query(
      `SELECT coin_balance, level, exp, exp_to_next FROM user_game_progress WHERE user_id = $1`, [userId]
    );
    return toPayload(rows[0]);
  } finally {
    client.release();
  }
}

// The caller owns the transaction. The unique event key makes retries safe.
async function award(client, userId, { sourceType, sourceId, coins, exp }) {
  const event = await client.query(
    `INSERT INTO game_reward_events (user_id, source_type, source_id, coins, exp)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (source_type, source_id) DO NOTHING RETURNING id`,
    [userId, sourceType, sourceId, coins, exp]
  );
  await ensureProgress(client, userId);
  const { rows } = await client.query(
    `SELECT coin_balance, level, exp, exp_to_next FROM user_game_progress WHERE user_id = $1 FOR UPDATE`, [userId]
  );
  const current = rows[0];
  if (!event.rows[0]) return { awarded: false, coins: 0, exp: 0, progress: toPayload(current) };

  let level = current.level;
  let currentExp = current.exp + exp;
  let expToNext = current.exp_to_next || LEVEL_ONE_EXP_TO_NEXT;
  while (currentExp >= expToNext) {
    currentExp -= expToNext;
    level += 1;
    expToNext += EXP_STEP_PER_LEVEL;
  }
  const { rows: updatedRows } = await client.query(
    `UPDATE user_game_progress SET coin_balance = coin_balance + $2, level = $3, exp = $4,
       exp_to_next = $5, updated_at = now() WHERE user_id = $1
     RETURNING coin_balance, level, exp, exp_to_next`,
    [userId, coins, level, currentExp, expToNext]
  );
  return { awarded: true, coins, exp, progress: toPayload(updatedRows[0]) };
}

module.exports = { getProgress, award };
