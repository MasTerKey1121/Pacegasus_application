const items = [
  { id: '20000000-0000-4000-8000-000000000001', code: 'shop_tee_purple',
    listingId: '30000000-0000-4000-8000-000000000001', name: 'เสื้อวิ่งสีม่วง', price: 20 },
  { id: '20000000-0000-4000-8000-000000000002', code: 'shop_tee_brown',
    listingId: '30000000-0000-4000-8000-000000000002', name: 'เสื้อวิ่งสีน้ำตาล', price: 1000 },
].map(item => ({ ...item, slot: 'inner_top', asset: 'asset:assets/models/pacegasus_starter_v9.glb',
  description: 'เสื้อวิ่งทรงเริ่มต้น โลโก้สีทอง', render: { family: 'pacegasus_starter_v9',
  variant: item.code, productAsset: 'asset:assets/models/product_running_tee.glb' } }));
items.push({
  id: '20000000-0000-4000-8000-000000000003', code: 'shop_golden_wings',
  listingId: '30000000-0000-4000-8000-000000000003', name: 'ปีกขนนกสีทอง',
  slot: 'back', price: 100, description: 'ปีกสีทอง ขนปีกเชื่อมเป็นชิ้นเดียว ติดตามหลังอวตาร',
  asset: 'asset:assets/models/product_golden_wings.glb',
  render: { family: 'pacegasus_starter_v9',
    productAsset: 'asset:assets/models/product_golden_wings.glb',
    avatarAsset: 'asset:assets/models/pacegasus_golden_wings.glb' },
});

async function ensureRunnerShopCatalog(executor, catalog = items) {
  await executor.query(`INSERT INTO avatar_items
    (id, code, slot_code, name, description, thumbnail_url, asset_url, render_data, is_default)
    SELECT x.id::uuid, x.code, x.slot, x.name, x.description,
      'asset:assets/models/items/' || x.code || '.png',
      x.asset, x.render, false
    FROM jsonb_to_recordset($1::jsonb) AS x(id text, code text, slot text, name text, description text, asset text, render jsonb)
    ON CONFLICT (code) DO UPDATE SET render_data=EXCLUDED.render_data,
      thumbnail_url=EXCLUDED.thumbnail_url, asset_url=EXCLUDED.asset_url,
      is_default=false`, [JSON.stringify(catalog)]);
  await executor.query(`INSERT INTO shop_listings(id, item_id, price_coins, is_featured, sort_order)
    SELECT x."listingId"::uuid, i.id, x.price, true, x.price
    FROM jsonb_to_recordset($1::jsonb) AS x("listingId" text, code text, price integer)
    JOIN avatar_items i ON i.code=x.code
    ON CONFLICT (id) DO UPDATE SET price_coins=EXCLUDED.price_coins`, [JSON.stringify(catalog)]);
}
module.exports = { items, ensureRunnerShopCatalog };
