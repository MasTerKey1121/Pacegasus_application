const db = require('../config/db');
const ApiError = require('../utils/ApiError');

const DEFAULT_SKIN_TONE = '#F1C27D';

// ใช้ร่วมกับ shopService: SELECT ${ITEM_COLUMNS} FROM avatar_items i ...
const ITEM_COLUMNS = `i.id AS item_id, i.code AS item_code, i.slot_code, i.name AS item_name,
  i.description AS item_description, i.rarity, i.thumbnail_url, i.asset_url, i.render_data, i.is_tintable`;

function toItem(row) {
  return {
    id: row.item_id,
    code: row.item_code,
    slot: row.slot_code,
    name: row.item_name,
    description: row.item_description,
    rarity: row.rarity,
    thumbnailUrl: row.thumbnail_url,
    assetUrl: row.asset_url,
    renderData: row.render_data,
    isTintable: row.is_tintable,
  };
}

function toSlot(row) {
  return {
    code: row.code,
    name: row.name,
    layerOrder: row.layer_order,
    sortOrder: row.sort_order,
    isRequired: row.is_required,
  };
}

// สร้าง avatar ครั้งแรก + แจกไอเท็ม default (รวมตัวที่เพิ่มเข้าแคตตาล็อกภายหลัง)
// + ใส่ไอเท็ม default ให้ช่องบังคับที่ยังว่าง — ทุกคำสั่ง idempotent เรียกซ้ำได้
async function ensureAvatar(client, userId) {
  await client.query(`INSERT INTO user_avatars (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`, [userId]);
  await client.query(
    `INSERT INTO user_avatar_items (user_id, item_id, source)
     SELECT $1, i.id, 'default' FROM avatar_items i
     WHERE i.is_default AND i.is_active
     ON CONFLICT (user_id, item_id) DO NOTHING`,
    [userId]
  );
  await client.query(
    `INSERT INTO user_avatar_equipment (user_id, slot_code, item_id)
     SELECT DISTINCT ON (s.code) $1, s.code, i.id
     FROM avatar_slots s
     JOIN avatar_items i ON i.slot_code = s.code AND i.is_default AND i.is_active
     WHERE s.is_required AND s.is_active
     ORDER BY s.code, i.created_at
     ON CONFLICT (user_id, slot_code) DO NOTHING`,
    [userId]
  );
}

async function loadAvatar(executor, userId) {
  // ไม่ใช้ Promise.all เพราะ executor อาจเป็น client เดียวกัน (pg ไม่รองรับ query ซ้อนบน client)
  const { rows: avatarRows } = await executor.query(
    `SELECT skin_tone, updated_at FROM user_avatars WHERE user_id = $1`,
    [userId]
  );
  const { rows: equipmentRows } = await executor.query(
    `SELECT e.slot_code, e.color_hex, s.layer_order, ${ITEM_COLUMNS}
     FROM user_avatar_equipment e
     JOIN avatar_items i ON i.id = e.item_id
     JOIN avatar_slots s ON s.code = e.slot_code
     WHERE e.user_id = $1
     ORDER BY s.layer_order`,
    [userId]
  );
  return {
    skinTone: avatarRows[0]?.skin_tone ?? DEFAULT_SKIN_TONE,
    // เรียงตาม layer_order แล้ว (หลัง -> หน้า) frontend วาดตามลำดับนี้ได้เลย
    equipment: equipmentRows.map((row) => ({
      slot: row.slot_code,
      layerOrder: row.layer_order,
      colorHex: row.color_hex,
      item: toItem(row),
    })),
    updatedAt: avatarRows[0]?.updated_at ?? null,
  };
}

async function withClient(work) {
  const client = await db.getClient();
  try {
    return await work(client);
  } finally {
    client.release();
  }
}

async function listSlots() {
  const { rows } = await db.query(`SELECT * FROM avatar_slots WHERE is_active ORDER BY sort_order`);
  return rows.map(toSlot);
}

function getMyAvatar(userId) {
  return withClient(async (client) => {
    await ensureAvatar(client, userId);
    return loadAvatar(client, userId);
  });
}

// ดู avatar ของคนอื่น (เช่นจากรายชื่อเพื่อน/สมาชิกคลับ) — ไม่สร้างข้อมูลแทนเจ้าของ
async function getAvatarByUid(uid) {
  const { rows } = await db.query(
    `SELECT id, uid, display_name FROM users WHERE uid = $1 AND status = 'active'`,
    [uid]
  );
  if (!rows[0]) throw new ApiError(404, 'ไม่พบผู้ใช้จาก UID นี้');
  const avatar = await loadAvatar(db, rows[0].id);
  return { user: { uid: rows[0].uid, displayName: rows[0].display_name }, ...avatar };
}

async function validateEquipment(client, userId, equipment) {
  const { rows: slotRows } = await client.query(`SELECT * FROM avatar_slots WHERE is_active`);
  const slots = new Map(slotRows.map((row) => [row.code, row]));

  const itemIds = equipment.filter((entry) => entry.itemId).map((entry) => entry.itemId);
  const { rows: itemRows } = await client.query(
    `SELECT i.id, i.slot_code, i.is_tintable, (ui.user_id IS NOT NULL) AS owned
     FROM avatar_items i
     LEFT JOIN user_avatar_items ui ON ui.item_id = i.id AND ui.user_id = $2
     WHERE i.id = ANY($1::uuid[])`,
    [itemIds, userId]
  );
  const items = new Map(itemRows.map((row) => [row.id, row]));

  for (const { slot, itemId, colorHex } of equipment) {
    const slotRow = slots.get(slot);
    if (!slotRow) throw new ApiError(400, `ไม่มีช่องแต่งตัว "${slot}"`);
    if (itemId === null) {
      if (slotRow.is_required) throw new ApiError(400, `ช่อง "${slotRow.name}" ต้องใส่ไอเท็มเสมอ`);
      continue;
    }
    const item = items.get(itemId);
    if (!item) throw new ApiError(404, `ไม่พบไอเท็ม ${itemId}`);
    if (item.slot_code !== slot) throw new ApiError(400, `ไอเท็ม ${itemId} ใส่ในช่อง "${slotRow.name}" ไม่ได้`);
    if (!item.owned) throw new ApiError(403, `คุณยังไม่มีไอเท็ม ${itemId}`);
    if (colorHex && !item.is_tintable) throw new ApiError(400, `ไอเท็ม ${itemId} เปลี่ยนสีไม่ได้`);
  }
}

// บันทึกทั้งชุดครั้งเดียว (ผู้เล่นลองแต่งในหน้าแต่งตัวแล้วกดบันทึก) ส่งมาเฉพาะช่องที่เปลี่ยน
async function updateMyAvatar(userId, { skinTone, equipment = [] }) {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    await ensureAvatar(client, userId);
    await validateEquipment(client, userId, equipment);

    for (const { slot, itemId, colorHex } of equipment) {
      if (itemId === null) {
        await client.query(`DELETE FROM user_avatar_equipment WHERE user_id = $1 AND slot_code = $2`, [userId, slot]);
      } else {
        await client.query(
          `INSERT INTO user_avatar_equipment (user_id, slot_code, item_id, color_hex)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (user_id, slot_code)
           DO UPDATE SET item_id = EXCLUDED.item_id, color_hex = EXCLUDED.color_hex, equipped_at = now()`,
          [userId, slot, itemId, colorHex ?? null]
        );
      }
    }
    await client.query(
      `UPDATE user_avatars SET skin_tone = COALESCE($2, skin_tone), updated_at = now() WHERE user_id = $1`,
      [userId, skinTone ?? null]
    );

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
  return loadAvatar(db, userId);
}

async function listInventory(userId, { slot, rarity, limit, offset }) {
  return withClient(async (client) => {
    await ensureAvatar(client, userId);
    const params = [userId];
    const where = ['ui.user_id = $1'];
    if (slot?.length) {
      params.push(slot);
      where.push(`i.slot_code = ANY($${params.length}::text[])`);
    }
    if (rarity?.length) {
      params.push(rarity);
      where.push(`i.rarity = ANY($${params.length}::item_rarity_enum[])`);
    }
    params.push(limit, offset);

    const { rows } = await client.query(
      `SELECT ${ITEM_COLUMNS}, ui.source, ui.acquired_at,
              (e.item_id IS NOT NULL) AS equipped, COUNT(*) OVER () AS total_count
       FROM user_avatar_items ui
       JOIN avatar_items i ON i.id = ui.item_id
       LEFT JOIN user_avatar_equipment e ON e.user_id = ui.user_id AND e.item_id = ui.item_id
       WHERE ${where.join(' AND ')}
       ORDER BY ui.acquired_at DESC, i.name
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return {
      items: rows.map((row) => ({
        item: toItem(row),
        source: row.source,
        acquiredAt: row.acquired_at,
        equipped: row.equipped,
      })),
      total: rows[0] ? Number(rows[0].total_count) : 0,
    };
  });
}

module.exports = {
  ITEM_COLUMNS,
  toItem,
  listSlots,
  getMyAvatar,
  getAvatarByUid,
  updateMyAvatar,
  listInventory,
};
