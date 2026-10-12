const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const friends = require('./friendService');
const avatars = require('./avatarService');

async function getProfile(viewerId, identifier) {
  const isId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(identifier);
  if (!isId && !/^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{10}$/.test(identifier)) {
    throw new ApiError(400, 'รหัสผู้ใช้ไม่ถูกต้อง');
  }
  const { rows } = await db.query(`SELECT uid FROM users WHERE ${isId ? 'id' : 'uid'} = $1 AND status = 'active'`, [identifier]);
  if (!rows[0]) throw new ApiError(404, 'ไม่พบผู้ใช้');
  const profile = await friends.lookupByUid(viewerId, rows[0].uid);
  const avatar = await avatars.getAvatarByUid(rows[0].uid);
  const { rows: clubs } = await db.query(`
    SELECT c.id, c.name, target.role, viewer.role AS viewer_role
    FROM club_members target JOIN clubs c ON c.id = target.club_id
    LEFT JOIN club_members viewer ON viewer.club_id = c.id AND viewer.user_id = $2
    WHERE target.user_id = $1`, [profile.user.id, viewerId]);
  const { rows: distances } = await db.query(`SELECT COALESCE(SUM(distance_km), 0) AS distance
    FROM running_sessions WHERE user_id = $1 AND status = 'completed'`, [profile.user.id]);
  const club = clubs[0];
  return { ...profile, avatar, distanceKm: Number(distances[0].distance),
    club: club ? { id: club.id, name: club.name, role: club.role } : null,
    canManageMember: viewerId !== profile.user.id && club?.viewer_role === 'leader' && club.role !== 'leader' };
}
module.exports = { getProfile };
