const db = require('../config/db');
const ApiError = require('../utils/ApiError');

// ยศสูงกว่าเตะยศต่ำกว่าได้เท่านั้น
const ROLE_RANK = { leader: 3, sub_leader: 2, member: 1 };

const PERMISSION_COLUMNS = {
  canApproveRequests: 'can_approve_requests',
  canInvite: 'can_invite',
  canKick: 'can_kick',
  canEditInfo: 'can_edit_info',
};

// constraint จาก migration 014 ที่อาจชนตอนมี request พร้อมกัน -> แปลงเป็นข้อความที่ผู้ใช้เข้าใจ
const CONSTRAINT_ERRORS = {
  uq_clubs_name_lower: [409, 'ชื่อคลับนี้ถูกใช้แล้ว'],
  uq_club_members_user: [409, 'ผู้ใช้นี้อยู่ในคลับอื่นแล้ว'],
  chk_clubs_member_count: [409, 'คลับเต็มแล้ว'],
  uq_club_join_requests_pair: [409, 'มีคำขอเข้าคลับนี้ค้างอยู่แล้ว'],
};

function toDbError(err) {
  const mapped = CONSTRAINT_ERRORS[err.constraint];
  return mapped && (err.code === '23505' || err.code === '23514') ? new ApiError(...mapped) : err;
}

async function withTransaction(work) {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw toDbError(err);
  } finally {
    client.release();
  }
}

function escapeLike(text) {
  return text.replace(/[\\%_]/g, '\\$&');
}

function toClub(row) {
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    imageUrl: row.image_url,
    tags: row.tags,
    memberCount: row.member_count,
    maxMembers: row.max_members,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toPublicUser(row) {
  return {
    id: row.user_id,
    uid: row.uid,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    level: row.level ?? 1,
  };
}

function toJoinRequest(row) {
  return {
    requestId: row.id,
    clubId: row.club_id,
    kind: row.kind,
    message: row.message,
    invitedBy: row.invited_by,
    createdAt: row.created_at,
  };
}

function toRolePermissions(row) {
  return Object.fromEntries(Object.entries(PERMISSION_COLUMNS).map(([key, column]) => [key, row[column] === true]));
}

// leader มีทุกสิทธิ์เสมอ ยศอื่นใช้ค่าจาก club_role_permissions
function toMembership(row) {
  if (!row) return null;
  const permissions = row.role === 'leader'
    ? Object.fromEntries(Object.keys(PERMISSION_COLUMNS).map((key) => [key, true]))
    : toRolePermissions(row);
  return { role: row.role, permissions };
}

const USER_COLUMNS = `u.id AS user_id, u.uid, u.display_name, u.avatar_url, g.level`;

// executor = db หรือ client ใน transaction
async function getMembership(executor, clubId, userId) {
  const { rows } = await executor.query(
    `SELECT m.role, p.can_approve_requests, p.can_invite, p.can_kick, p.can_edit_info
     FROM club_members m
     LEFT JOIN club_role_permissions p ON p.club_id = m.club_id AND p.role = m.role
     WHERE m.club_id = $1 AND m.user_id = $2`,
    [clubId, userId]
  );
  return toMembership(rows[0]);
}

async function requireMember(executor, clubId, userId) {
  const membership = await getMembership(executor, clubId, userId);
  if (!membership) throw new ApiError(403, 'คุณไม่ได้เป็นสมาชิกคลับนี้');
  return membership;
}

async function requirePermission(executor, clubId, userId, permission) {
  const membership = await requireMember(executor, clubId, userId);
  if (!membership.permissions[permission]) throw new ApiError(403, 'ยศของคุณไม่มีสิทธิ์ทำรายการนี้');
  return membership;
}

async function requireLeader(executor, clubId, userId) {
  const membership = await requireMember(executor, clubId, userId);
  if (membership.role !== 'leader') throw new ApiError(403, 'เฉพาะหัวหน้าคลับเท่านั้น');
  return membership;
}

// ล็อกแถวคลับ ทำให้การเปลี่ยนแปลงสมาชิกของคลับเดียวกันทำทีละรายการ
async function lockClub(client, clubId) {
  const { rows } = await client.query(`SELECT * FROM clubs WHERE id = $1 FOR UPDATE`, [clubId]);
  if (!rows[0]) throw new ApiError(404, 'ไม่พบคลับ');
  return rows[0];
}

async function ensureNotInClub(client, userId, message) {
  const { rows } = await client.query(`SELECT club_id FROM club_members WHERE user_id = $1`, [userId]);
  if (rows[0]) throw new ApiError(409, message);
}

async function findPendingForUpdate(client, clubId, userId) {
  const { rows } = await client.query(
    `SELECT * FROM club_join_requests WHERE club_id = $1 AND user_id = $2 FOR UPDATE`,
    [clubId, userId]
  );
  return rows[0] || null;
}

// ผู้เรียกต้องล็อกคลับ (lockClub) ไว้แล้ว
async function addMember(client, club, userId) {
  if (club.member_count >= club.max_members) throw new ApiError(409, 'คลับเต็มแล้ว');
  await client.query(`INSERT INTO club_members (club_id, user_id) VALUES ($1, $2)`, [club.id, userId]);
  // อยู่ได้คลับเดียว คำขอ/คำเชิญอื่นที่ค้างของคนนี้จึงหมดความหมาย
  await client.query(`DELETE FROM club_join_requests WHERE user_id = $1`, [userId]);
}

async function findMember(client, clubId, userId) {
  const membership = await getMembership(client, clubId, userId);
  if (!membership) throw new ApiError(404, 'ไม่พบสมาชิกคนนี้ในคลับ');
  return membership;
}

// ---------------------------------------------------------------------
// Clubs
// ---------------------------------------------------------------------

async function createClub(userId, info) {
  return withTransaction(async (client) => {
    await ensureNotInClub(client, userId, 'คุณอยู่ในคลับอื่นแล้ว ต้องออกก่อนจึงจะสร้างคลับใหม่ได้');
    const { rows: [club] } = await client.query(
      `INSERT INTO clubs (name, description, image_url, tags, created_by)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [info.name, info.description || null, info.imageUrl ?? null, info.tags, userId]
    );
    await client.query(`INSERT INTO club_members (club_id, user_id, role) VALUES ($1, $2, 'leader')`, [club.id, userId]);
    await client.query(`DELETE FROM club_join_requests WHERE user_id = $1`, [userId]);
    // RETURNING ได้ค่าก่อน trigger นับสมาชิก จึงใส่ 1 (ตัว leader) เอง
    return { ...toClub({ ...club, member_count: 1 }), myMembership: toMembership({ role: 'leader' }) };
  });
}

async function searchClubs(userId, { q, tag, hasSlot, limit, offset }) {
  const params = [userId];
  const where = ['TRUE'];
  if (q) {
    params.push(`%${escapeLike(q)}%`);
    where.push(`c.name ILIKE $${params.length}`);
  }
  if (tag) {
    params.push([tag]);
    where.push(`c.tags @> $${params.length}::text[]`);
  }
  if (hasSlot) where.push('c.member_count < c.max_members');
  params.push(limit, offset);

  const { rows } = await db.query(
    `SELECT c.*, COUNT(*) OVER () AS total_count, leader.*,
            r.id AS pending_id, r.kind AS pending_kind
     FROM clubs c
     LEFT JOIN LATERAL (
       SELECT ${USER_COLUMNS}
       FROM club_members m
       JOIN users u ON u.id = m.user_id
       LEFT JOIN user_game_progress g ON g.user_id = u.id
       WHERE m.club_id = c.id AND m.role = 'leader'
     ) leader ON TRUE
     LEFT JOIN club_join_requests r ON r.club_id = c.id AND r.user_id = $1
     WHERE ${where.join(' AND ')}
     ORDER BY c.member_count DESC, c.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  return {
    clubs: rows.map((row) => ({
      ...toClub(row),
      leader: row.user_id ? toPublicUser(row) : null,
      myPendingRequest: row.pending_id ? { requestId: row.pending_id, kind: row.pending_kind } : null,
    })),
    total: rows[0] ? Number(rows[0].total_count) : 0,
  };
}

async function getClub(userId, clubId) {
  const [{ rows: clubRows }, { rows: memberRows }, myMembership, { rows: pendingRows }] = await Promise.all([
    db.query(`SELECT * FROM clubs WHERE id = $1`, [clubId]),
    db.query(
      `SELECT m.role, m.joined_at, ${USER_COLUMNS}
       FROM club_members m
       JOIN users u ON u.id = m.user_id
       LEFT JOIN user_game_progress g ON g.user_id = u.id
       WHERE m.club_id = $1
       ORDER BY CASE m.role WHEN 'leader' THEN 0 WHEN 'sub_leader' THEN 1 ELSE 2 END, m.joined_at`,
      [clubId]
    ),
    getMembership(db, clubId, userId),
    db.query(`SELECT * FROM club_join_requests WHERE club_id = $1 AND user_id = $2`, [clubId, userId]),
  ]);
  if (!clubRows[0]) throw new ApiError(404, 'ไม่พบคลับ');

  return {
    club: toClub(clubRows[0]),
    members: memberRows.map((row) => ({ user: toPublicUser(row), role: row.role, joinedAt: row.joined_at })),
    myMembership,
    myPendingRequest: pendingRows[0] ? toJoinRequest(pendingRows[0]) : null,
  };
}

async function getMyClub(userId) {
  const { rows } = await db.query(`SELECT club_id FROM club_members WHERE user_id = $1`, [userId]);
  return rows[0] ? getClub(userId, rows[0].club_id) : null;
}

const CLUB_INFO_COLUMNS = { name: 'name', description: 'description', imageUrl: 'image_url', tags: 'tags' };

async function updateClub(userId, clubId, patch) {
  return withTransaction(async (client) => {
    await lockClub(client, clubId);
    await requirePermission(client, clubId, userId, 'canEditInfo');

    const params = [clubId];
    const sets = [];
    for (const [key, column] of Object.entries(CLUB_INFO_COLUMNS)) {
      if (patch[key] === undefined) continue;
      params.push(patch[key] === '' ? null : patch[key]);
      sets.push(`${column} = $${params.length}`);
    }
    const { rows: [club] } = await client.query(
      `UPDATE clubs SET ${sets.join(', ')} WHERE id = $1 RETURNING *`,
      params
    );
    return toClub(club);
  });
}

async function disbandClub(userId, clubId) {
  return withTransaction(async (client) => {
    await lockClub(client, clubId);
    await requireLeader(client, clubId, userId);
    await client.query(`DELETE FROM clubs WHERE id = $1`, [clubId]);
    return { clubId, action: 'disbanded' };
  });
}

// หัวหน้าออกได้เมื่ออยู่คนเดียว (คลับถูกยุบ) ไม่อย่างนั้นต้องโอนตำแหน่งก่อน
async function leaveClub(userId, clubId) {
  return withTransaction(async (client) => {
    const club = await lockClub(client, clubId);
    const membership = await requireMember(client, clubId, userId);

    if (membership.role === 'leader') {
      if (club.member_count > 1) throw new ApiError(409, 'กรุณาโอนตำแหน่งหัวหน้าให้สมาชิกคนอื่นก่อนออกจากคลับ');
      await client.query(`DELETE FROM clubs WHERE id = $1`, [clubId]);
      return { clubId, action: 'disbanded' };
    }

    await client.query(`DELETE FROM club_members WHERE club_id = $1 AND user_id = $2`, [clubId, userId]);
    return { clubId, action: 'left' };
  });
}

// ---------------------------------------------------------------------
// Members & roles
// ---------------------------------------------------------------------

async function kickMember(actorId, clubId, targetUserId) {
  if (actorId === targetUserId) throw new ApiError(400, 'ไม่สามารถเตะตัวเองได้ ใช้การออกจากคลับแทน');
  return withTransaction(async (client) => {
    await lockClub(client, clubId);
    const actor = await requirePermission(client, clubId, actorId, 'canKick');
    const target = await findMember(client, clubId, targetUserId);
    if (ROLE_RANK[actor.role] <= ROLE_RANK[target.role]) {
      throw new ApiError(403, 'เตะได้เฉพาะสมาชิกที่ยศต่ำกว่าคุณ');
    }
    await client.query(`DELETE FROM club_members WHERE club_id = $1 AND user_id = $2`, [clubId, targetUserId]);
    return { clubId, userId: targetUserId, action: 'kicked' };
  });
}

async function changeMemberRole(actorId, clubId, targetUserId, role) {
  if (actorId === targetUserId) throw new ApiError(400, 'เปลี่ยนยศตัวเองไม่ได้ ใช้การโอนตำแหน่งหัวหน้าแทน');
  return withTransaction(async (client) => {
    await lockClub(client, clubId);
    await requireLeader(client, clubId, actorId);
    await findMember(client, clubId, targetUserId);
    await client.query(
      `UPDATE club_members SET role = $3 WHERE club_id = $1 AND user_id = $2`,
      [clubId, targetUserId, role]
    );
    return { clubId, userId: targetUserId, role };
  });
}

async function transferLeadership(actorId, clubId, targetUserId) {
  if (actorId === targetUserId) throw new ApiError(400, 'คุณเป็นหัวหน้าคลับอยู่แล้ว');
  return withTransaction(async (client) => {
    await lockClub(client, clubId);
    await requireLeader(client, clubId, actorId);
    await findMember(client, clubId, targetUserId);
    // ต้องลดยศคนเดิมก่อน เพราะ uq_club_members_leader ตรวจทีละแถว
    await client.query(`UPDATE club_members SET role = 'sub_leader' WHERE club_id = $1 AND user_id = $2`, [clubId, actorId]);
    await client.query(`UPDATE club_members SET role = 'leader' WHERE club_id = $1 AND user_id = $2`, [clubId, targetUserId]);
    return { clubId, previousLeaderId: actorId, newLeaderId: targetUserId };
  });
}

async function getPermissions(userId, clubId) {
  await requireMember(db, clubId, userId);
  const { rows } = await db.query(`SELECT * FROM club_role_permissions WHERE club_id = $1`, [clubId]);
  const byRole = Object.fromEntries(rows.map((row) => [row.role, toRolePermissions(row)]));
  return {
    leader: toMembership({ role: 'leader' }).permissions,
    sub_leader: byRole.sub_leader,
    member: byRole.member,
  };
}

async function updateRolePermissions(actorId, clubId, role, changes) {
  return withTransaction(async (client) => {
    await lockClub(client, clubId);
    await requireLeader(client, clubId, actorId);

    const params = [clubId, role];
    const sets = [];
    for (const [key, column] of Object.entries(PERMISSION_COLUMNS)) {
      if (changes[key] === undefined) continue;
      params.push(changes[key]);
      sets.push(`${column} = $${params.length}`);
    }
    const { rows } = await client.query(
      `UPDATE club_role_permissions SET ${sets.join(', ')} WHERE club_id = $1 AND role = $2 RETURNING *`,
      params
    );
    if (!rows[0]) throw new ApiError(404, 'ไม่พบการตั้งค่าสิทธิ์ของยศนี้');
    return { role, permissions: toRolePermissions(rows[0]) };
  });
}

// ---------------------------------------------------------------------
// Join requests & invites
// ---------------------------------------------------------------------

async function requestToJoin(userId, clubId, { message }) {
  return withTransaction(async (client) => {
    const club = await lockClub(client, clubId);
    await ensureNotInClub(client, userId, 'คุณอยู่ในคลับอื่นแล้ว ต้องออกก่อนจึงจะขอเข้าคลับใหม่ได้');

    const existing = await findPendingForUpdate(client, clubId, userId);
    if (existing?.kind === 'request') throw new ApiError(409, 'ส่งคำขอเข้าคลับนี้ไปแล้ว กรุณารอการอนุมัติ');
    if (existing) {
      // ถูกเชิญไว้แล้ว -> การขอเข้าถือเป็นการตอบรับคำเชิญ
      await addMember(client, club, userId);
      return { status: 'joined', clubId };
    }
    if (club.member_count >= club.max_members) throw new ApiError(409, 'คลับเต็มแล้ว');

    const { rows: [row] } = await client.query(
      `INSERT INTO club_join_requests (club_id, user_id, kind, message)
       VALUES ($1, $2, 'request', $3) RETURNING *`,
      [clubId, userId, message || null]
    );
    return { status: 'pending', request: toJoinRequest(row) };
  });
}

async function inviteUser(actorId, clubId, { uid, message }) {
  const { rows: targetRows } = await db.query(
    `SELECT ${USER_COLUMNS}
     FROM users u
     LEFT JOIN user_game_progress g ON g.user_id = u.id
     WHERE u.uid = $1 AND u.status = 'active'`,
    [uid]
  );
  const target = targetRows[0];
  if (!target) throw new ApiError(404, 'ไม่พบผู้ใช้จาก UID นี้');
  if (target.user_id === actorId) throw new ApiError(400, 'ไม่สามารถเชิญตัวเองได้');

  return withTransaction(async (client) => {
    const club = await lockClub(client, clubId);
    const actor = await requirePermission(client, clubId, actorId, 'canInvite');
    await ensureNotInClub(client, target.user_id, 'ผู้ใช้นี้อยู่ในคลับแล้ว');

    const existing = await findPendingForUpdate(client, clubId, target.user_id);
    if (existing?.kind === 'invite') throw new ApiError(409, 'เชิญผู้ใช้นี้ไปแล้ว กรุณารอการตอบรับ');
    if (existing) {
      // เขาขอเข้ามาเองอยู่แล้ว -> ถ้ามีสิทธิ์อนุมัติ การเชิญถือเป็นการอนุมัติ
      if (!actor.permissions.canApproveRequests) {
        throw new ApiError(409, 'ผู้ใช้นี้ส่งคำขอเข้าคลับแล้ว รอผู้มีสิทธิ์อนุมัติ');
      }
      await addMember(client, club, target.user_id);
      return { status: 'joined', user: toPublicUser(target) };
    }
    if (club.member_count >= club.max_members) throw new ApiError(409, 'คลับเต็มแล้ว');

    const { rows: [row] } = await client.query(
      `INSERT INTO club_join_requests (club_id, user_id, kind, invited_by, message)
       VALUES ($1, $2, 'invite', $3, $4) RETURNING *`,
      [clubId, target.user_id, actorId, message || null]
    );
    return { status: 'pending', request: toJoinRequest(row), user: toPublicUser(target) };
  });
}

// staff ดูคำขอเข้าคลับ (kind=request) หรือคำเชิญที่ส่งไปแล้ว (kind=invite)
async function listClubJoinRequests(actorId, clubId, { kind, limit, offset }) {
  await requirePermission(db, clubId, actorId, kind === 'request' ? 'canApproveRequests' : 'canInvite');
  const { rows } = await db.query(
    `SELECT r.*, ${USER_COLUMNS}
     FROM club_join_requests r
     JOIN users u ON u.id = r.user_id
     LEFT JOIN user_game_progress g ON g.user_id = u.id
     WHERE r.club_id = $1 AND r.kind = $2::club_join_kind_enum AND u.status = 'active'
     ORDER BY r.created_at DESC
     LIMIT $3 OFFSET $4`,
    [clubId, kind, limit, offset]
  );
  return rows.map((row) => ({ ...toJoinRequest(row), user: toPublicUser(row) }));
}

async function approveJoinRequest(actorId, clubId, requestId) {
  return withTransaction(async (client) => {
    const club = await lockClub(client, clubId);
    await requirePermission(client, clubId, actorId, 'canApproveRequests');
    const { rows } = await client.query(
      `SELECT r.* FROM club_join_requests r
       WHERE r.id = $1 AND r.club_id = $2 AND r.kind = 'request'
         AND EXISTS (SELECT 1 FROM users u WHERE u.id = r.user_id AND u.status = 'active')
       FOR UPDATE`,
      [requestId, clubId]
    );
    if (!rows[0]) throw new ApiError(404, 'ไม่พบคำขอเข้าคลับ');
    await addMember(client, club, rows[0].user_id);
    return { clubId, userId: rows[0].user_id, status: 'joined' };
  });
}

// staff ปฏิเสธคำขอ (request) หรือยกเลิกคำเชิญ (invite)
async function removeClubJoinRequest(actorId, clubId, requestId) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `SELECT * FROM club_join_requests WHERE id = $1 AND club_id = $2 FOR UPDATE`,
      [requestId, clubId]
    );
    const row = rows[0];
    if (!row) throw new ApiError(404, 'ไม่พบคำขอเข้าคลับ');
    await requirePermission(client, clubId, actorId, row.kind === 'request' ? 'canApproveRequests' : 'canInvite');
    await client.query(`DELETE FROM club_join_requests WHERE id = $1`, [requestId]);
    return { requestId, action: row.kind === 'request' ? 'rejected' : 'revoked' };
  });
}

// ผู้ใช้ดูคำเชิญที่ได้รับ (kind=invite) หรือคำขอที่ตัวเองส่งไป (kind=request)
async function listMyJoinRequests(userId, { kind, limit, offset }) {
  const { rows } = await db.query(
    `SELECT r.*, c.name, c.image_url, c.tags, c.member_count, c.max_members,
            iu.uid AS inviter_uid, iu.display_name AS inviter_display_name
     FROM club_join_requests r
     JOIN clubs c ON c.id = r.club_id
     LEFT JOIN users iu ON iu.id = r.invited_by
     WHERE r.user_id = $1 AND r.kind = $2::club_join_kind_enum
     ORDER BY r.created_at DESC
     LIMIT $3 OFFSET $4`,
    [userId, kind, limit, offset]
  );
  return rows.map((row) => ({
    ...toJoinRequest(row),
    club: {
      id: row.club_id,
      name: row.name,
      imageUrl: row.image_url,
      tags: row.tags,
      memberCount: row.member_count,
      maxMembers: row.max_members,
    },
    inviter: row.invited_by ? { uid: row.inviter_uid, displayName: row.inviter_display_name } : null,
  }));
}

async function acceptInvite(userId, requestId) {
  const { rows } = await db.query(
    `SELECT club_id FROM club_join_requests WHERE id = $1 AND user_id = $2 AND kind = 'invite'`,
    [requestId, userId]
  );
  if (!rows[0]) throw new ApiError(404, 'ไม่พบคำเชิญเข้าคลับ');

  return withTransaction(async (client) => {
    // ล็อกคลับก่อนแถวคำเชิญ ให้ลำดับการล็อกตรงกับ flow อื่น
    const club = await lockClub(client, rows[0].club_id);
    const { rows: inviteRows } = await client.query(
      `SELECT id FROM club_join_requests WHERE id = $1 AND user_id = $2 AND kind = 'invite' FOR UPDATE`,
      [requestId, userId]
    );
    if (!inviteRows[0]) throw new ApiError(404, 'ไม่พบคำเชิญเข้าคลับ');
    await addMember(client, club, userId);
    return { clubId: club.id, status: 'joined' };
  });
}

// ผู้ใช้ยกเลิกคำขอของตัวเอง (request) หรือปฏิเสธคำเชิญ (invite)
async function removeMyJoinRequest(userId, requestId) {
  const { rows } = await db.query(
    `DELETE FROM club_join_requests WHERE id = $1 AND user_id = $2 RETURNING kind`,
    [requestId, userId]
  );
  if (!rows[0]) throw new ApiError(404, 'ไม่พบคำขอหรือคำเชิญเข้าคลับ');
  return { requestId, action: rows[0].kind === 'request' ? 'cancelled' : 'declined' };
}

module.exports = {
  createClub,
  searchClubs,
  getClub,
  getMyClub,
  updateClub,
  disbandClub,
  leaveClub,
  kickMember,
  changeMemberRole,
  transferLeadership,
  getPermissions,
  updateRolePermissions,
  requestToJoin,
  inviteUser,
  listClubJoinRequests,
  approveJoinRequest,
  removeClubJoinRequest,
  listMyJoinRequests,
  acceptInvite,
  removeMyJoinRequest,
};
