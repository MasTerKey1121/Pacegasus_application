// Explicit catalog-only operation. Never grants ownership or modifies wallets.
const db = require('../src/config/db');
const { items, ensureRunnerShopCatalog } = require('../src/services/runnerShopCatalog');
async function main() {
  const client = await db.getClient();
  try {
    if (process.argv.includes('--apply')) {
      await client.query('BEGIN');
      await ensureRunnerShopCatalog(client, items.filter(i => i.code === 'shop_golden_wings'));
      await client.query('COMMIT');
    }
    const { rows } = await client.query(`
      SELECT i.code, i.slot_code, i.is_default, i.is_active AS item_active,
             l.price_coins, l.is_active AS listing_active, i.render_data
      FROM avatar_items i LEFT JOIN shop_listings l ON l.item_id=i.id
      WHERE i.code='shop_golden_wings'`);
    console.log(JSON.stringify(rows));
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
main().catch(error => {
  console.error('CATALOG_REGISTRATION_FAILED', error.code || error.name);
  process.exitCode = 1;
}).finally(() => db.pool.end());
