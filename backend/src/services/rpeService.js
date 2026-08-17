const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const gameProgressService = require('./gameProgressService');

async function logRpe(userId, data) {
  const validScore = (score) => Number.isInteger(score) && score >= 1 && score <= 10;
  if (!validScore(data.rpeScore) || !validScore(data.stressLevel)) {
    throw new ApiError(400, 'rpeScore และ stressLevel ต้องเป็นจำนวนเต็มระหว่าง 1–10');
  }
  if (!Number.isInteger(data.durationMinutes) || data.durationMinutes < 1) {
    throw new ApiError(400, 'durationMinutes ต้องเป็นจำนวนเต็มมากกว่า 0');
  }
  const sessionRpe = data.durationMinutes * data.rpeScore;

  if (data.runningSessionId) {
    const { rows } = await db.query(
      'SELECT id FROM running_sessions WHERE id = $1 AND user_id = $2',
      [data.runningSessionId, userId]
    );
    if (!rows[0]) throw new ApiError(404, 'ไม่พบ running session ของผู้ใช้นี้');
  }

  const client = await db.getClient();
  try {
  await client.query('BEGIN');
  const { rows } = await client.query(
    `INSERT INTO rpe_logs (
       user_id, running_session_id, duration_minutes, rpe_score, stress_level,
       mood, has_pain, pain_note, session_rpe, logged_at
     ) VALUES ($1, $2, $3, $4, $5, $6::rpe_mood_enum, $7, $8, $9, COALESCE($10, now()))
     RETURNING *`,
    [userId, data.runningSessionId || null, data.durationMinutes, data.rpeScore,
      data.stressLevel, data.mood, data.hasPain, data.hasPain ? data.painNote.trim() : null,
      sessionRpe, data.loggedAt || null]
  );
  const reward = await gameProgressService.award(client, userId, {
    sourceType: 'rpe_log', sourceId: rows[0].id, coins: 5, exp: 5,
  });
  await client.query('COMMIT');
  return { ...rows[0], reward };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

async function getRpeHistory(userId, filters) {
  const values = [userId];
  const conditions = ['r.user_id = $1'];
  const addCondition = (sql, value) => { values.push(value); conditions.push(sql.replace('?', `$${values.length}`)); };

  if (filters.startDate) addCondition('r.logged_at >= ?', filters.startDate);
  if (filters.endDate) addCondition('r.logged_at < ?::timestamptz + INTERVAL \'1 day\'', filters.endDate);
  if (filters.mood) addCondition('r.mood = ?::rpe_mood_enum', filters.mood);
  if (filters.hasPain !== undefined) addCondition('r.has_pain = ?', filters.hasPain);
  values.push(filters.limit, filters.offset);

  const { rows } = await db.query(
    `SELECT r.*, rs.distance_km, rs.duration_seconds, rs.started_at, rs.ended_at,
            rs.session_type, rs.status AS running_session_status,
            CASE WHEN rs.distance_km > 0 AND rs.duration_seconds IS NOT NULL
              THEN ROUND((rs.duration_seconds::numeric / rs.distance_km), 2)
              ELSE NULL END AS pace_seconds_per_km
     FROM rpe_logs r
     LEFT JOIN running_sessions rs ON rs.id = r.running_session_id AND rs.user_id = r.user_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY r.logged_at DESC, r.created_at DESC
     LIMIT $${values.length - 1} OFFSET $${values.length}`,
    values
  );
  return rows;
}

async function getRpeDetail(userId, rpeLogId) {
  const { rows } = await db.query(
    `SELECT r.*, rs.distance_km, rs.duration_seconds, rs.started_at, rs.ended_at,
            rs.session_type, rs.status AS running_session_status,
            CASE WHEN rs.distance_km > 0 AND rs.duration_seconds IS NOT NULL
              THEN ROUND((rs.duration_seconds::numeric / rs.distance_km), 2)
              ELSE NULL END AS pace_seconds_per_km
     FROM rpe_logs r
     LEFT JOIN running_sessions rs ON rs.id = r.running_session_id AND rs.user_id = r.user_id
     WHERE r.id = $1 AND r.user_id = $2`,
    [rpeLogId, userId]
  );
  if (!rows[0]) throw new ApiError(404, 'ไม่พบ RPE log ที่ต้องการ');
  return rows[0];
}

async function calculateTrainingLoad(userId) {
  const { rows } = await db.query(
    `SELECT
       COALESCE(SUM(session_rpe) FILTER (WHERE logged_at >= now() - INTERVAL '7 days'), 0)::int AS acute_load,
       COALESCE(SUM(session_rpe) FILTER (WHERE logged_at >= now() - INTERVAL '28 days'), 0)::int AS chronic_load
     FROM rpe_logs WHERE user_id = $1`,
    [userId]
  );
  const { acute_load: acuteLoad, chronic_load: chronicLoad } = rows[0];
  const chronicWeeklyAverage = chronicLoad / 4;
  const acwr = chronicWeeklyAverage > 0 ? Number((acuteLoad / chronicWeeklyAverage).toFixed(2)) : null;
  const riskLevel = acwr === null ? 'green' : acwr < 1.3 ? 'green' : acwr < 1.5 ? 'yellow' : 'red';

  return { acuteLoad, chronicLoad, chronicWeeklyAverage, acwr, riskLevel };
}

module.exports = { logRpe, getRpeHistory, getRpeDetail, calculateTrainingLoad };
