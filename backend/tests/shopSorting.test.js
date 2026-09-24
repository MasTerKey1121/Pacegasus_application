const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const shop = require('../src/services/shopService');
const { shopItemFiltersSchema } = require('../src/utils/shopValidators');

test('shop sorting validates and orders before pagination with a stable tie break', async (t) => {
  const original = db.query;
  t.after(() => { db.query = original; });
  for (const sort of ['price_asc', 'price_desc', 'rarity_asc', 'rarity_desc']) {
    const { value, error } = shopItemFiltersSchema.validate({ sort, slot: 'inner_top,outer_top', rarity: 'epic', offset: 30 });
    assert.equal(error, undefined);
    db.query = async (sql, params) => {
      assert.deepEqual(params.slice(1), [['inner_top', 'outer_top'], ['epic'], 30, 30]);
      assert.match(sql, /ORDER BY [\s\S]+, l.id\s+LIMIT/);
      if (sort.startsWith('rarity')) {
        assert.match(sql, /WHEN 'common' THEN 0 WHEN 'rare' THEN 1 WHEN 'epic' THEN 2 WHEN 'legendary' THEN 3/);
        assert.match(sql, sort === 'rarity_desc' ? /END DESC, l.price_coins/ : /END, l.price_coins/);
      } else {
        assert.match(sql, sort === 'price_desc' ? /ORDER BY l.price_coins DESC/ : /ORDER BY l.price_coins,/);
      }
      return { rows: [] };
    };
    assert.deepEqual(await shop.listItems('test-user', value), { items: [], total: 0 });
  }
  assert.ok(shopItemFiltersSchema.validate({ sort: 'rarity; DROP TABLE shop_listings' }).error);
});
