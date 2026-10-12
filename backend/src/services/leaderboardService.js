const db = require('../config/db');

// Monday 00:00 to next Monday 00:00 in Thailand; only completed runs count.
async function weeklyDistance(userId, scope) {
  const entities = scope === 'guild'
    ? `SELECT c.id, c.name, c.image_url AS image, COALESCE(SUM(r.distance_km), 0) AS distance
       FROM clubs c
       LEFT JOIN club_members m ON m.club_id = c.id
       LEFT JOIN users u ON u.id = m.user_id AND u.status = 'active'
       LEFT JOIN runs r ON r.user_id = u.id AND r.started_at >= m.joined_at
       GROUP BY c.id, c.name, c.image_url`
    : `SELECT u.id, COALESCE(u.display_name, 'นักวิ่ง') AS name, u.avatar_url AS image,
              COALESCE(SUM(r.distance_km), 0) AS distance
       FROM users u LEFT JOIN runs r ON r.user_id = u.id
       WHERE u.status = 'active' GROUP BY u.id, u.display_name, u.avatar_url`;
  const mine = scope === 'guild'
    ? 'SELECT club_id AS id FROM club_members WHERE user_id = $1'
    : 'SELECT id FROM users WHERE id = $1 AND status = \'active\'';
  const { rows } = await db.query(`
    WITH period AS (
      SELECT date_trunc('week', now() AT TIME ZONE 'Asia/Bangkok') AS local_start
    ), bounds AS (
      SELECT local_start AT TIME ZONE 'Asia/Bangkok' AS starts_at,
        (local_start + interval '1 week') AT TIME ZONE 'Asia/Bangkok' AS ends_at FROM period
    ), runs AS (
      SELECT r.user_id, r.started_at, r.distance_km FROM running_sessions r CROSS JOIN bounds b
      WHERE r.status = 'completed' AND r.ended_at >= b.starts_at AND r.ended_at < b.ends_at
        AND r.distance_km > 0
    ), entities AS (${entities}), ranked AS (
      SELECT *, ROW_NUMBER() OVER (ORDER BY distance DESC, id) AS rank FROM entities WHERE distance > 0
    ), mine AS (${mine}), top_entries AS (
      SELECT jsonb_build_object('id', id, 'name', name, 'imageUrl', image,
        'distanceKm', distance, 'rank', rank) AS entry, rank FROM ranked WHERE rank <= 50
    )
    SELECT (SELECT starts_at FROM bounds) AS starts_at, (SELECT ends_at FROM bounds) AS ends_at,
      COALESCE((SELECT jsonb_agg(entry ORDER BY rank) FROM top_entries), '[]'::jsonb) AS entries,
      (SELECT jsonb_build_object('id', e.id, 'name', e.name, 'imageUrl', e.image,
        'distanceKm', e.distance, 'rank', CASE WHEN r.rank <= 50 THEN r.rank ELSE NULL END)
       FROM entities e JOIN mine m ON m.id = e.id LEFT JOIN ranked r ON r.id = e.id) AS my_entry
  `, [userId]);
  return { scope, metric: 'weekly_distance', limit: 50, period: {
    startsAt: rows[0].starts_at, endsAt: rows[0].ends_at, timezone: 'Asia/Bangkok',
  }, entries: rows[0].entries, myEntry: rows[0].my_entry };
}
module.exports = { weeklyDistance };
