const db = require('../config/db');
const ApiError = require('../utils/ApiError');

const PAIR_CONDITION = `LEAST(f.requester_id, f.addressee_id) = LEAST($1::uuid, $2::uuid)
   AND GREATEST(f.requester_id, f.addressee_id) = GREATEST($1::uuid, $2::uuid)`;

// ข้อมูลผู้ใช้ที่เปิดเผยให้คนอื่นเห็นได้ (ไม่มี email)
function toPublicUser(row) {
  return {
    id: row.user_id,
    uid: row.uid,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    level: row.level ?? 1,
  };
}

function toFriendship(row, userId) {
  return {
    friendshipId: row.id,
    status: row.status,
    direction: row.requester_id === userId ? 'outgoing' : 'incoming',
    requestedAt: row.created_at,
    respondedAt: row.responded_at,
  };
}

async function findActiveUserByUid(uid) {
  const { rows } = await db.query(
    `SELECT u.id AS user_id, u.uid, u.display_name, u.avatar_url, g.level
     FROM users u
     LEFT JOIN user_game_progress g ON g.user_id = u.id
     WHERE u.uid = $1 AND u.status = 'active'`,
    [uid]
  );
  if (!rows[0]) throw new ApiError(404, 'ไม่พบผู้ใช้จาก UID นี้');
  return rows[0];
}

// GET /friends/lookup/:uid — ดูโปรไฟล์ก่อนแอด พร้อมสถานะความสัมพันธ์ปัจจุบัน
async function lookupByUid(userId, uid) {
  const target = await findActiveUserByUid(uid);
  if (target.user_id === userId) {
    return { user: toPublicUser(target), relationship: { status: 'self' } };
  }

  const { rows } = await db.query(`SELECT f.* FROM friendships f WHERE ${PAIR_CONDITION}`, [userId, target.user_id]);
  return {
    user: toPublicUser(target),
    relationship: rows[0] ? toFriendship(rows[0], userId) : { status: 'none' },
  };
}

async function sendFriendRequest(userId, uid) {
  const target = await findActiveUserByUid(uid);
  if (target.user_id === userId) throw new ApiError(400, 'ไม่สามารถเพิ่มตัวเองเป็นเพื่อนได้');

  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const { rows: existingRows } = await client.query(
      `SELECT f.* FROM friendships f WHERE ${PAIR_CONDITION} FOR UPDATE`,
      [userId, target.user_id]
    );
    const existing = existingRows[0];

    let row;
    let autoAccepted = false;
    if (existing?.status === 'accepted') {
      throw new ApiError(409, 'เป็นเพื่อนกับผู้ใช้นี้อยู่แล้ว');
    } else if (existing && existing.requester_id === userId) {
      throw new ApiError(409, 'ส่งคำขอเป็นเพื่อนไปแล้ว กรุณารอการตอบรับ');
    } else if (existing) {
      // อีกฝ่ายส่งคำขอมาหาเราก่อนแล้ว -> การแอดกลับถือเป็นการตอบรับ
      ({ rows: [row] } = await client.query(
        `UPDATE friendships SET status = 'accepted', responded_at = now()
         WHERE id = $1 RETURNING *`,
        [existing.id]
      ));
      autoAccepted = true;
    } else {
      ({ rows: [row] } = await client.query(
        `INSERT INTO friendships (requester_id, addressee_id) VALUES ($1, $2) RETURNING *`,
        [userId, target.user_id]
      ));
    }

    await client.query('COMMIT');
    return { ...toFriendship(row, userId), autoAccepted, user: toPublicUser(target) };
  } catch (err) {
    await client.query('ROLLBACK');
    // อีกฝ่ายส่งคำขอหากันพร้อมกันพอดี -> ชน uq_friendships_pair
    if (err.code === '23505') throw new ApiError(409, 'มีคำขอเป็นเพื่อนระหว่างผู้ใช้นี้อยู่แล้ว');
    throw err;
  } finally {
    client.release();
  }
}

// เฉพาะผู้รับ (addressee) เท่านั้นที่ยืนยันได้ และผู้ส่งต้องยังเป็นบัญชี active
async function acceptFriendRequest(userId, friendshipId) {
  const { rows } = await db.query(
    `WITH accepted AS (
       UPDATE friendships f SET status = 'accepted', responded_at = now()
       WHERE f.id = $1 AND f.addressee_id = $2 AND f.status = 'pending'
         AND EXISTS (SELECT 1 FROM users r WHERE r.id = f.requester_id AND r.status = 'active')
       RETURNING f.*
     )
     SELECT a.*, u.id AS user_id, u.uid, u.display_name, u.avatar_url, g.level
     FROM accepted a
     JOIN users u ON u.id = a.requester_id
     LEFT JOIN user_game_progress g ON g.user_id = u.id`,
    [friendshipId, userId]
  );
  if (!rows[0]) throw new ApiError(404, 'ไม่พบคำขอเป็นเพื่อนที่รอการตอบรับ');
  return { ...toFriendship(rows[0], userId), user: toPublicUser(rows[0]) };
}

async function deleteFriendship(userId, friendshipId, status) {
  const { rows } = await db.query(
    `DELETE FROM friendships
     WHERE id = $1 AND status = $3::friendship_status_enum
       AND (requester_id = $2 OR addressee_id = $2)
     RETURNING *`,
    [friendshipId, userId, status]
  );
  return rows[0] || null;
}

// ผู้รับกดปฏิเสธ หรือผู้ส่งกดยกเลิกคำขอที่ยัง pending
async function removeFriendRequest(userId, friendshipId) {
  const row = await deleteFriendship(userId, friendshipId, 'pending');
  if (!row) throw new ApiError(404, 'ไม่พบคำขอเป็นเพื่อนที่รอการตอบรับ');
  return { friendshipId: row.id, action: row.requester_id === userId ? 'cancelled' : 'declined' };
}

async function removeFriend(userId, friendshipId) {
  const row = await deleteFriendship(userId, friendshipId, 'accepted');
  if (!row) throw new ApiError(404, 'ไม่พบเพื่อนคนนี้');
  return { friendshipId: row.id, action: 'unfriended' };
}

async function listRelationships(userId, condition, orderBy, { limit, offset }) {
  const { rows } = await db.query(
    `SELECT f.*, u.id AS user_id, u.uid, u.display_name, u.avatar_url, g.level
     FROM friendships f
     JOIN users u ON u.id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
     LEFT JOIN user_game_progress g ON g.user_id = u.id
     WHERE ${condition} AND u.status = 'active'
     ORDER BY ${orderBy}
     LIMIT $2 OFFSET $3`,
    [userId, limit, offset]
  );
  return rows.map((row) => ({ ...toFriendship(row, userId), user: toPublicUser(row) }));
}

function listFriends(userId, filters) {
  return listRelationships(
    userId,
    `f.status = 'accepted' AND (f.requester_id = $1 OR f.addressee_id = $1)`,
    'f.responded_at DESC',
    filters
  );
}

function listFriendRequests(userId, filters) {
  const column = filters.direction === 'outgoing' ? 'f.requester_id' : 'f.addressee_id';
  return listRelationships(userId, `f.status = 'pending' AND ${column} = $1`, 'f.created_at DESC', filters);
}

module.exports = {
  lookupByUid,
  sendFriendRequest,
  acceptFriendRequest,
  removeFriendRequest,
  removeFriend,
  listFriends,
  listFriendRequests,
};
