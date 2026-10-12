const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const Joi = require('joi');

const updateSchema = Joi.object({
  displayName: Joi.string().trim().min(1).max(80).required(),
}).unknown(false).required();
function toUser(row) {
  return { uid: row.uid, displayName: row.display_name, avatarUrl: row.avatar_url };
}
async function get(userId) {
  const { rows } = await db.query(`
    SELECT u.uid, u.display_name, u.avatar_url,
      (SELECT jsonb_build_object('name', c.name) FROM club_members m
       JOIN clubs c ON c.id = m.club_id WHERE m.user_id = u.id) AS club,
      COALESCE(s.total_km, 0) AS total_km, COALESCE(s.total_runs, 0) AS total_runs,
      COALESCE(s.week_km, 0) AS week_km, COALESCE(s.week_runs, 0) AS week_runs
    FROM users u LEFT JOIN LATERAL (
      SELECT SUM(distance_km) AS total_km, COUNT(*) AS total_runs,
        SUM(distance_km) FILTER (WHERE COALESCE(ended_at, started_at) >=
          date_trunc('week', now() AT TIME ZONE 'Asia/Bangkok') AT TIME ZONE 'Asia/Bangkok') AS week_km,
        COUNT(*) FILTER (WHERE COALESCE(ended_at, started_at) >=
          date_trunc('week', now() AT TIME ZONE 'Asia/Bangkok') AT TIME ZONE 'Asia/Bangkok') AS week_runs
      FROM running_sessions WHERE user_id = u.id AND status = 'completed'
        AND COALESCE(ended_at, started_at) <= now()
    ) s ON TRUE WHERE u.id = $1 AND u.status = 'active'`, [userId]);
  if (!rows[0]) throw new ApiError(404, 'ไม่พบผู้ใช้');
  const row = rows[0];
  return { user: toUser(row), club: row.club, stats: {
    weeklyDistanceKm: Number(row.week_km), weeklyRuns: Number(row.week_runs),
    totalDistanceKm: Number(row.total_km), totalRuns: Number(row.total_runs) } };
}
async function update(userId, input) {
  const { value, error } = updateSchema.validate(input);
  if (error) throw new ApiError(400, 'กรอกชื่อ 1–80 ตัวอักษร');
  const { rows } = await db.query(`UPDATE users SET display_name = $2
    WHERE id = $1 AND status = 'active' RETURNING uid, display_name, avatar_url`,
    [userId, value.displayName]);
  if (!rows[0]) throw new ApiError(404, 'ไม่พบผู้ใช้');
  return { user: toUser(rows[0]) };
}
module.exports = { get, update, updateSchema };
