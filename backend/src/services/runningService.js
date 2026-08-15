const db = require('../config/db');
const ApiError = require('../utils/ApiError');

function normalizeJsonValue(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }

  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) {
      return null;
    }

    try {
      const parsed = JSON.parse(trimmed);
      return normalizeJsonValue(parsed);
    } catch (err) {
      return null;
    }
  }

  if (typeof value === 'object') {
    return value;
  }

  return value;
}

function serializeJsonValue(value) {
  const normalized = normalizeJsonValue(value);
  if (normalized === null || normalized === undefined) {
    return null;
  }

  return JSON.stringify(normalized);
}

function normalizeSessionPayload(payload = {}) {
  const sideQuestInstanceIds = Array.isArray(payload.sideQuestInstanceIds)
    ? payload.sideQuestInstanceIds.filter(Boolean)
    : [];

  return {
    environment: payload.environment || null,
    sessionType: payload.sessionType || null,
    distanceKm: payload.distanceKm != null ? Number(payload.distanceKm) : null,
    durationSeconds: payload.durationSeconds != null ? Number(payload.durationSeconds) : null,
    note: payload.note || null,
    startLat: payload.startLat != null ? Number(payload.startLat) : null,
    startLng: payload.startLng != null ? Number(payload.startLng) : null,
    endLat: payload.endLat != null ? Number(payload.endLat) : null,
    endLng: payload.endLng != null ? Number(payload.endLng) : null,
    routePoints: normalizeJsonValue(payload.routePoints),
    avgHeartRateBpm: payload.avgHeartRateBpm != null ? Number(payload.avgHeartRateBpm) : null,
    maxHeartRateBpm: payload.maxHeartRateBpm != null ? Number(payload.maxHeartRateBpm) : null,
    sideQuestInstanceIds,
  };
}

async function startSession(userId, payload) {
  const body = normalizeSessionPayload(payload);

  const { rows } = await db.query(
    `INSERT INTO running_sessions (
       user_id, environment, session_type, status, started_at,
       start_lat, start_lng, route_points
     )
     VALUES ($1, $2, $3, 'in_progress', now(), $4, $5, $6::jsonb)
     RETURNING id, user_id, environment, session_type, status, started_at, ended_at, distance_km, duration_seconds, created_at, updated_at, start_lat, start_lng, end_lat, end_lng, route_points, avg_heart_rate_bpm, max_heart_rate_bpm`,
    [userId, body.environment, body.sessionType, body.startLat, body.startLng, serializeJsonValue(body.routePoints)]
  );

  const session = rows[0];

  if (body.sideQuestInstanceIds.length > 0) {
    await db.query(
      `UPDATE user_side_quest_instances
       SET running_session_id = $1,
           status = 'in_progress',
           started_at = COALESCE(started_at, now())
       WHERE id = ANY($2::uuid[]) AND user_id = $3`,
      [session.id, body.sideQuestInstanceIds, userId]
    );
  }

  return session;
}

async function completeSession(userId, sessionId, payload) {
  const body = normalizeSessionPayload(payload);

  const { rows } = await db.query(
    `UPDATE running_sessions
     SET status = 'completed',
         ended_at = COALESCE(ended_at, now()),
         distance_km = COALESCE($3, distance_km),
         duration_seconds = COALESCE($4, duration_seconds),
         end_lat = COALESCE($5, end_lat),
         end_lng = COALESCE($6, end_lng),
         route_points = COALESCE($7::jsonb, route_points),
         avg_heart_rate_bpm = COALESCE($8, avg_heart_rate_bpm),
         max_heart_rate_bpm = COALESCE($9, max_heart_rate_bpm),
         updated_at = now()
     WHERE id = $1 AND user_id = $2
     RETURNING id, user_id, environment, session_type, status, started_at, ended_at, distance_km, duration_seconds, created_at, updated_at, start_lat, start_lng, end_lat, end_lng, route_points, avg_heart_rate_bpm, max_heart_rate_bpm`,
    [sessionId, userId, body.distanceKm, body.durationSeconds, body.endLat, body.endLng, serializeJsonValue(body.routePoints), body.avgHeartRateBpm, body.maxHeartRateBpm]
  );

  if (rows.length === 0) {
    throw new ApiError(404, 'ไม่พบ running session ที่ต้องการ');
  }

  return rows[0];
}

async function abandonSession(userId, sessionId, payload) {
  const body = normalizeSessionPayload(payload);

  const { rows } = await db.query(
    `UPDATE running_sessions
     SET status = 'abandoned',
         ended_at = COALESCE(ended_at, now()),
         distance_km = COALESCE($3, distance_km),
         duration_seconds = COALESCE($4, duration_seconds),
         end_lat = COALESCE($5, end_lat),
         end_lng = COALESCE($6, end_lng),
         route_points = COALESCE($7::jsonb, route_points),
         avg_heart_rate_bpm = COALESCE($8, avg_heart_rate_bpm),
         max_heart_rate_bpm = COALESCE($9, max_heart_rate_bpm),
         updated_at = now()
     WHERE id = $1 AND user_id = $2
     RETURNING id, user_id, environment, session_type, status, started_at, ended_at, distance_km, duration_seconds, created_at, updated_at, start_lat, start_lng, end_lat, end_lng, route_points, avg_heart_rate_bpm, max_heart_rate_bpm`,
    [sessionId, userId, body.distanceKm, body.durationSeconds, body.endLat, body.endLng, serializeJsonValue(body.routePoints), body.avgHeartRateBpm, body.maxHeartRateBpm]
  );

  if (rows.length === 0) {
    throw new ApiError(404, 'ไม่พบ running session ที่ต้องการ');
  }

  return rows[0];
}

async function getSessionDetail(userId, sessionId) {
  const { rows } = await db.query(
    `SELECT id, user_id, environment, session_type, status, started_at, ended_at, distance_km, duration_seconds, created_at, updated_at, start_lat, start_lng, end_lat, end_lng, route_points, avg_heart_rate_bpm, max_heart_rate_bpm
     FROM running_sessions
     WHERE id = $1 AND user_id = $2`,
    [sessionId, userId]
  );

  if (rows.length === 0) {
    throw new ApiError(404, 'ไม่พบ running session ที่ต้องการ');
  }

  return rows[0];
}

/**
 * ดึงประวัติ session ที่วิ่งเสร็จแล้ว โดยสามารถเรียงตามวัน เดือน หรือปีได้
 */
async function getSessionHistory(userId, sortBy, order) {
  const sessionDateExpression = 'COALESCE(ended_at, started_at)';
  const sortExpressions = {
    date: sessionDateExpression,
    month: `DATE_TRUNC('month', ${sessionDateExpression})`,
    year: `DATE_TRUNC('year', ${sessionDateExpression})`,
  };
  const sortExpression = sortExpressions[sortBy] || sortExpressions.date;
  const direction = order === 'asc' ? 'ASC' : 'DESC';

  const { rows } = await db.query(
    `SELECT rs.id, rs.environment, rs.session_type, rs.status, rs.started_at, rs.ended_at,
            rs.distance_km, rs.duration_seconds, rs.avg_heart_rate_bpm,
            rs.max_heart_rate_bpm, rs.created_at,
            ${sessionDateExpression.replaceAll('ended_at', 'rs.ended_at').replaceAll('started_at', 'rs.started_at')} AS session_date,
            COALESCE(rpe.rpe_logs, '[]'::json) AS rpe_logs
     FROM running_sessions rs
     LEFT JOIN LATERAL (
       SELECT json_agg(
         json_build_object(
           'id', r.id,
           'rpeScore', r.rpe_score,
           'stressLevel', r.stress_level,
           'mood', r.mood,
           'hasPain', r.has_pain,
           'sessionRpe', r.session_rpe,
           'loggedAt', r.logged_at
         ) ORDER BY r.logged_at DESC
       ) AS rpe_logs
       FROM rpe_logs r
       WHERE r.running_session_id = rs.id AND r.user_id = rs.user_id
     ) rpe ON TRUE
     WHERE rs.user_id = $1 AND rs.status = 'completed'
     ORDER BY ${sortExpression.replaceAll('ended_at', 'rs.ended_at').replaceAll('started_at', 'rs.started_at')} ${direction}, rs.ended_at ${direction}`,
    [userId]
  );

  return { sortBy, order, sessions: rows };
}

module.exports = {
  startSession,
  completeSession,
  abandonSession,
  getSessionDetail,
  getSessionHistory,
};
