const test = require('node:test');
const assert = require('node:assert/strict');
const { items, ensureStarterCatalog } = require('../src/services/starterAvatarCatalog');

test('seven starter items include both shirts and every equipped part', async () => {
  assert.equal(items.length, 7);
  assert.equal(new Set(items.map(i => i.id)).size, 7);
  assert.deepEqual(new Set(items.map(i => i.slot)), new Set(['hair','face','inner_top','pants','socks','shoes']));
  const white = items.find(i => i.code === 'starter_tee_white');
  assert.equal(white.render.variant, 'starter_tee_white');
  assert.equal(white.render.starterEquipped, false);
  assert.equal(items.find(i => i.code === 'starter_tee_black').render.starterEquipped, true);
  let calls = 0;
  await ensureStarterCatalog({ async query(sql, params) {
    calls++;
    assert.match(sql, /ON CONFLICT \(code\) DO UPDATE/);
    assert.match(sql, /is_default = true/);
    assert.doesNotMatch(sql, /DELETE|TRUNCATE|user_avatar_equipment/);
    assert.deepEqual(JSON.parse(params[0]), items);
  }});
  assert.equal(calls, 1);
});

test('starter thumbnails and model are shipped with the frontend', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const root = path.resolve(__dirname, '../../frontend');
  for (const item of items) {
    assert.ok(fs.existsSync(path.join(root, item.thumbnail.slice(6))), item.code);
    assert.ok(fs.existsSync(path.join(root, item.asset.slice(6))));
  }
});

test('first avatar access grants every default but never overwrites an existing outfit', async (t) => {
  const db = require('../src/config/db');
  const service = require('../src/services/avatarService');
  const original = db.getClient; t.after(() => { db.getClient = original; });
  const queries = [];
  let released = false;
  db.getClient = async () => ({ release() { released = true; }, async query(sql, params) {
    queries.push(sql);
    if (sql.includes('INSERT INTO user_avatar_items')) {
      assert.match(sql, /WHERE i.is_default AND i.is_active/);
      assert.match(sql, /ON CONFLICT \(user_id, item_id\) DO NOTHING/);
      assert.deepEqual(params, ['user-id']);
    }
    if (sql.includes('INSERT INTO user_avatar_equipment')) {
      assert.match(sql, /starterEquipped/);
      assert.match(sql, /ON CONFLICT \(user_id, slot_code\) DO NOTHING/);
    }
    return { rows: [] };
  }});
  await service.getMyAvatar('user-id');
  assert.ok(queries.some(sql => sql.includes('INSERT INTO avatar_items')));
  assert.ok(queries.some(sql => sql.includes('INSERT INTO user_avatar_equipment')));
  assert.equal(released, true);
});

test('white material variant modifies only the shirt and preserves the animation binary', () => {
  const fs = require('node:fs'); const path = require('node:path');
  const root = path.resolve(__dirname, '../../frontend/assets/models');
  const original = fs.readFileSync(path.join(root,'pacegasus_wave_male_v8.glb'));
  const updated = fs.readFileSync(path.join(root,'pacegasus_starter_v9.glb'));
  const doc = JSON.parse(updated.subarray(20,20+updated.readUInt32LE(12)).toString());
  assert.deepEqual(updated.subarray(20+updated.readUInt32LE(12)),original.subarray(20+original.readUInt32LE(12)));
  assert.deepEqual(doc.animations.map(a=>a.name).sort(),['Idle_Loop','Wave_Greeting']);
  const shirt = doc.nodes.find(n=>n.name==='Top_RunningTee').mesh;
  for (let i=0;i<doc.meshes.length;i++) {
    for (const p of doc.meshes[i].primitives) {
      if (p.extensions?.KHR_materials_variants) assert.equal(i,shirt);
    }
  }
  assert.equal(doc.extensions.KHR_materials_variants.variants[0].name,'starter_tee_white');
});
