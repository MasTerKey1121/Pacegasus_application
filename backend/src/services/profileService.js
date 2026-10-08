const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const { loadAvatar } = require('./avatarService');

async function areFriends(userId, otherId) {
  const { rows } = await db.query(
    `SELECT 1 FROM friendships f
     WHERE f.status = 'accepted'
       AND LEAST(f.requester_id, f.addressee_id) = LEAST($1::uuid, $2::uuid)
       AND GREATEST(f.requester_id, f.addressee_id) = GREATEST($1::uuid, $2::uuid)`,
    [userId, otherId]
  );
  return rows.length > 0;
}

async function loadClub(userId) {
  const { rows } = await db.query(
    `SELECT c.id, c.name, c.image_url, c.member_count, c.max_members, m.role
     FROM club_members m
     JOIN clubs c ON c.id = m.club_id
     WHERE m.user_id = $1`,
    [userId]
  );
  if (!rows[0]) return null;
  return {
    id: rows[0].id,
    name: rows[0].name,
    imageUrl: rows[0].image_url,
    memberCount: rows[0].member_count,
    maxMembers: rows[0].max_members,
    role: rows[0].role,
  };
}

// ระยะสะสมนับเฉพาะ session ที่ completed
async function loadTotalDistanceKm(userId) {
  const { rows } = await db.query(
    `SELECT COALESCE(SUM(distance_km), 0)::float8 AS total_km, COUNT(*)::int AS runs
     FROM running_sessions WHERE user_id = $1 AND status = 'completed'`,
    [userId]
  );
  return { totalDistanceKm: Math.round(rows[0].total_km * 100) / 100, totalRuns: rows[0].runs };
}

// หน้า Profile: UID, ชื่อ, ชุดที่ใส่, คลับ, ระยะสะสม — ดูได้ทุกคนที่มี UID (relationship = self | friend | none)
async function getProfileByUid(viewerId, uid) {
  const { rows } = await db.query(
    `SELECT u.id, u.uid, u.display_name, u.avatar_url, g.level
     FROM users u
     LEFT JOIN user_game_progress g ON g.user_id = u.id
     WHERE u.uid = $1 AND u.status = 'active'`,
    [uid]
  );
  const target = rows[0];
  if (!target) throw new ApiError(404, 'ไม่พบผู้ใช้จาก UID นี้');

  const isSelf = target.id === viewerId;
  const relationship = isSelf ? 'self' : (await areFriends(viewerId, target.id)) ? 'friend' : 'none';

  const [avatar, club, distance] = await Promise.all([
    loadAvatar(db, target.id),
    loadClub(target.id),
    loadTotalDistanceKm(target.id),
  ]);

  return {
    user: {
      uid: target.uid,
      displayName: target.display_name,
      avatarUrl: target.avatar_url,
      level: target.level ?? 1,
    },
    relationship,
    avatar,
    club,
    stats: distance,
  };
}

module.exports = { getProfileByUid };
