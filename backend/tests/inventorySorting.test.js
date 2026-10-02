const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const avatar = require('../src/services/avatarService');
const { inventoryFiltersSchema } = require('../src/utils/avatarValidators');

test('inventory filters whitelist sorting and preserve owned-only scope before pagination', async (t) => {
  const original = db.getClient;
  t.after(() => { db.getClient = original; });
  assert.ok(inventoryFiltersSchema.validate({ sort: 'price_asc' }).error);
  assert.ok(inventoryFiltersSchema.validate({ sort: 'rarity_desc; SELECT 1' }).error);
  assert.equal(inventoryFiltersSchema.validate({}).value.sort, 'newest');
  for (const sort of ['newest', 'rarity_asc', 'rarity_desc']) {
    let released = false;
    const { value, error } = inventoryFiltersSchema.validate({ sort, slot: 'inner_top,outer_top', rarity: 'epic', limit: 12, offset: 24 });
    assert.equal(error, undefined);
    db.getClient = async () => ({
      release() { released = true; },
      async query(sql, params) {
        if (!sql.includes('FROM user_avatar_items ui')) return { rows: [] };
        assert.deepEqual(params, ['owner-id', ['inner_top', 'outer_top'], ['epic'], 12, 24]);
        assert.match(sql, /WHERE ui.user_id = \$1/);
        assert.match(sql, /ORDER BY [\s\S]+i.id\s+LIMIT \$4 OFFSET \$5/);
        if (sort === 'newest') assert.match(sql, /ORDER BY ui.acquired_at DESC, i.name/);
        else assert.match(sql, sort === 'rarity_desc' ? /END DESC, ui.acquired_at/ : /END, ui.acquired_at/);
        return { rows: [{ item_id: 'owned-item', slot_code: 'inner_top', item_name: 'Owned shirt', rarity: 'epic', equipped: true, total_count: '25' }] };
      },
    });
    const result = await avatar.listInventory('owner-id', value);
    assert.equal(result.total, 25);
    assert.equal(result.items[0].item.id, 'owned-item');
    assert.equal(result.items[0].equipped, true);
    assert.equal(released, true);
  }
});
