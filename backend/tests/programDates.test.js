const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const program = require('../src/services/programService');

test('training DATE values stay calendar dates when JSON is sent to the app', async (t) => {
  const originalQuery = db.query;
  const originalTimezone = process.env.TZ;
  process.env.TZ = 'Asia/Bangkok';
  t.after(() => {
    db.query = originalQuery;
    if (originalTimezone === undefined) delete process.env.TZ;
    else process.env.TZ = originalTimezone;
  });
  const start = new Date('2026-10-01T00:00:00+07:00');
  const end = new Date('2026-10-07T00:00:00+07:00');
  db.query = async (sql) => {
    if (sql.includes('SELECT EXISTS')) return { rows: [{ schedule_saved: true }] };
    if (sql.includes('AS week_start')) return { rows: [{ week_number: 0, week_start: start, week_end: end }] };
    if (sql.includes('FROM main_quest_instances')) return { rows: [{ id: 'quest', scheduled_date: start, status: 'completed' }] };
    return { rows: [{ id: 'program', start_date: start, schedule_mode: 'manual', template_level: 'beginner' }] };
  };
  const result = JSON.parse(JSON.stringify(await program.getCurrentWeek('owner')));
  assert.equal(result.startDate, '2026-10-01');
  assert.equal(result.weekStart, '2026-10-01');
  assert.equal(result.weekEnd, '2026-10-07');
  assert.equal(result.quests[0].scheduled_date, '2026-10-01');
  assert.equal(result.scheduleSaved, true);
  const range = JSON.parse(JSON.stringify(await program.getQuestsInRange('owner')));
  assert.equal(range.from, '2026-10-01');
  assert.equal(range.to, '2026-10-07');
  assert.equal(range.quests[0].scheduled_date, '2026-10-01');
});
