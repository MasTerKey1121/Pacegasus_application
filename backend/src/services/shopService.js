const db = require('../config/db');
const ApiError = require('../utils/ApiError');
const gameProgressService = require('./gameProgressService');
const { ITEM_COLUMNS, toItem } = require('./avatarService');

const ON_SALE = `l.is_active AND i.is_active
  AND l.starts_at <= now() AND (l.ends_at IS NULL OR l.ends_at > now())`;

// whitelist เท่านั้น ห้ามต่อ string จาก query ตรงๆ
const SORT_ORDER = {
  rarity_asc: "CASE i.rarity WHEN 'common' THEN 0 WHEN 'rare' THEN 1 WHEN 'epic' THEN 2 WHEN 'legendary' THEN 3 END, l.price_coins",
  rarity_desc: "CASE i.rarity WHEN 'common' THEN 0 WHEN 'rare' THEN 1 WHEN 'epic' THEN 2 WHEN 'legendary' THEN 3 END DESC, l.price_coins",
  featured: 'l.is_featured DESC, l.sort_order, l.starts_at DESC',
  newest: 'l.starts_at DESC',
  price_asc: 'l.price_coins, l.starts_at DESC',
  price_desc: 'l.price_coins DESC, l.starts_at DESC',
  ending_soon: 'l.ends_at ASC NULLS LAST, l.starts_at DESC',
};

function toListing(row) {
  return {
    listingId: row.listing_id,
    priceCoins: row.price_coins,
    originalPriceCoins: row.original_price_coins,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    isFeatured: row.is_featured,
    owned: row.owned,
    item: toItem(row),
  };
}

const LISTING_COLUMNS = `l.id AS listing_id, l.price_coins, l.original_price_coins, l.starts_at, l.ends_at,
  l.is_featured, (ui.user_id IS NOT NULL) AS owned, ${ITEM_COLUMNS}`;

const LISTING_FROM = `
  FROM shop_listings l
  JOIN avatar_items i ON i.id = l.item_id
  JOIN avatar_slots s ON s.code = i.slot_code AND s.is_active
  LEFT JOIN user_avatar_items ui ON ui.item_id = i.id AND ui.user_id = $1`;

const ON_SALE_LISTING_BY_ID = `SELECT ${LISTING_COLUMNS} ${LISTING_FROM} WHERE l.id = $2 AND ${ON_SALE}`;

function escapeLike(text) {
  return text.replace(/[\\%_]/g, '\\$&');
}

async function listItems(userId, filters) {
  const params = [userId];
  const where = [ON_SALE];
  const add = (value, condition) => {
    params.push(value);
    where.push(condition.replace('?', `$${params.length}`));
  };

  if (filters.slot?.length) add(filters.slot, 'i.slot_code = ANY(?::text[])');
  if (filters.rarity?.length) add(filters.rarity, 'i.rarity = ANY(?::item_rarity_enum[])');
  if (filters.q) add(`%${escapeLike(filters.q)}%`, 'i.name ILIKE ?');
  if (filters.minPrice !== undefined) add(filters.minPrice, 'l.price_coins >= ?');
  if (filters.maxPrice !== undefined) add(filters.maxPrice, 'l.price_coins <= ?');
  if (filters.owned !== undefined) where.push(`ui.user_id IS ${filters.owned ? 'NOT ' : ''}NULL`);
  if (filters.featured !== undefined) where.push(`l.is_featured = ${filters.featured}`);
  params.push(filters.limit, filters.offset);

  const { rows } = await db.query(
    `SELECT ${LISTING_COLUMNS}, COUNT(*) OVER () AS total_count
     ${LISTING_FROM}
     WHERE ${where.join(' AND ')}
     ORDER BY ${SORT_ORDER[filters.sort]}, l.id
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );
  return { items: rows.map(toListing), total: rows[0] ? Number(rows[0].total_count) : 0 };
}

async function getItem(userId, listingId) {
  const { rows } = await db.query(ON_SALE_LISTING_BY_ID, [userId, listingId]);
  if (!rows[0]) throw new ApiError(404, 'ไม่พบสินค้า หรือหมดช่วงเวลาขายแล้ว');
  return toListing(rows[0]);
}

async function purchase(userId, listingId) {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    // ล็อกยอดเหรียญก่อน: กดซื้อซ้อนกัน ครั้งที่ 2 จะรอจนครั้งแรกจบ แล้วเห็นว่ามีไอเท็มแล้ว (409)
    await gameProgressService.lockProgress(client, userId);
    const { rows } = await client.query(ON_SALE_LISTING_BY_ID, [userId, listingId]);
    const listing = rows[0];
    if (!listing) throw new ApiError(404, 'ไม่พบสินค้า หรือหมดช่วงเวลาขายแล้ว');
    if (listing.owned) throw new ApiError(409, 'คุณมีไอเท็มนี้อยู่แล้ว');

    const progress = await gameProgressService.spendCoins(client, userId, listing.price_coins);
    // กันเหนียว: ถ้ายังหลุดมาได้จะชน uq_shop_purchases_user_item แล้ว rollback (เหรียญไม่หาย)
    const { rows: [purchaseRow] } = await client.query(
      `INSERT INTO shop_purchases (user_id, listing_id, item_id, price_coins, coin_balance_after)
       VALUES ($1, $2, $3, $4, $5) RETURNING id, created_at`,
      [userId, listingId, listing.item_id, listing.price_coins, progress.coinBalance]
    );
    await client.query(
      `INSERT INTO user_avatar_items (user_id, item_id, source, source_ref) VALUES ($1, $2, 'shop', $3)`,
      [userId, listing.item_id, purchaseRow.id]
    );

    await client.query('COMMIT');
    return {
      purchaseId: purchaseRow.id,
      purchasedAt: purchaseRow.created_at,
      priceCoins: listing.price_coins,
      item: toItem(listing),
      progress,
    };
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') throw new ApiError(409, 'คุณมีไอเท็มนี้อยู่แล้ว');
    throw err;
  } finally {
    client.release();
  }
}

async function listPurchases(userId, { limit, offset }) {
  const { rows } = await db.query(
    `SELECT p.id AS purchase_id, p.listing_id, p.price_coins, p.coin_balance_after, p.created_at, ${ITEM_COLUMNS}
     FROM shop_purchases p
     JOIN avatar_items i ON i.id = p.item_id
     WHERE p.user_id = $1
     ORDER BY p.created_at DESC
     LIMIT $2 OFFSET $3`,
    [userId, limit, offset]
  );
  return rows.map((row) => ({
    purchaseId: row.purchase_id,
    listingId: row.listing_id,
    priceCoins: row.price_coins,
    coinBalanceAfter: row.coin_balance_after,
    purchasedAt: row.created_at,
    item: toItem(row),
  }));
}

module.exports = { listItems, getItem, purchase, listPurchases };
