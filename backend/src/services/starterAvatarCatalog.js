const codes = [
  ['starter_hair', 'hair', 'ผมสั้นนักวิ่ง', true],
  ['starter_face', 'face', 'หน้ายิ้มเริ่มต้น', true],
  ['starter_tee_black', 'inner_top', 'เสื้อวิ่งสีดำ', true],
  ['starter_tee_white', 'inner_top', 'เสื้อวิ่งสีขาว', false],
  ['starter_shorts', 'pants', 'กางเกงวิ่งเริ่มต้น', true],
  ['starter_socks', 'socks', 'ถุงเท้าสีขาว', true],
  ['starter_shoes', 'shoes', 'รองเท้าวิ่งเริ่มต้น', true],
];
const items = codes.map(([code, slot, name, equipped], index) => ({
  id: `10000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
  code, slot, name,
  thumbnail: `asset:assets/models/items/${code}.png`,
  asset: 'asset:assets/models/pacegasus_starter_v9.glb',
  render: { family: 'pacegasus_starter_v9', starterEquipped: equipped,
    variant: code === 'starter_tee_white' ? 'starter_tee_white' : null },
}));

// Add only the named starter catalog. Existing equipment/ownership is not
// overwritten; ensureAvatar grants defaults to each user on first access.
async function ensureStarterCatalog(client) {
  await client.query(`INSERT INTO avatar_items
    (id, code, slot_code, name, description, thumbnail_url, asset_url,
     render_data, is_default, is_active)
    SELECT x.id::uuid, x.code, x.slot, x.name, 'ไอเทมเริ่มต้นฟรี',
      x.thumbnail, x.asset, x.render, true, true
    FROM jsonb_to_recordset($1::jsonb) AS x
      (id text, code text, slot text, name text, thumbnail text, asset text, render jsonb)
    ON CONFLICT (code) DO UPDATE SET
      thumbnail_url = EXCLUDED.thumbnail_url, asset_url = EXCLUDED.asset_url,
      render_data = EXCLUDED.render_data, is_default = true`, [JSON.stringify(items)]);
}
module.exports = { items, ensureStarterCatalog };
