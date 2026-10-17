const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const images = require('../src/services/clubImageService');

test('club image upload persists validated bytes and can serve them later', async (t) => {
  const original = db.query;
  t.after(() => { db.query = original; });
  const png = Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    Buffer.from([0, 0, 0, 13]), Buffer.from('IHDR'),
    Buffer.from([0, 0, 0, 1, 0, 0, 0, 1]),
  ]);
  let stored;
  db.query = async (sql, args) => {
    if (sql.startsWith('INSERT INTO club_images')) {
      assert.match(args[0], /^[0-9a-f-]{36}$/);
      assert.equal(args[1], 'image/png');
      assert.deepEqual(args[2], png);
      stored = { id: args[0], content_type: args[1], image_data: args[2] };
      return { rows: [] };
    }
    assert.equal(args[0], stored.id);
    return { rows: [stored] };
  };
  const id = await images.saveImage(png.toString('base64'));
  assert.deepEqual(await images.getImage(id), stored);
  await assert.rejects(images.saveImage('not an image'), { statusCode: 400 });
});
