const test = require('node:test');
const assert = require('node:assert/strict');

// Temporary tables shadow production tables on this connection only. All data
// is rolled back; no real accounts, runs or club memberships are changed.
test('weekly rankings: top 50, ties, week boundaries and guild contribution', {
  skip: process.env.RUN_LEADERBOARD_INTEGRATION !== '1', timeout: 30000,
}, async () => {
  const db = require('../src/config/db');
  const service = require('../src/services/leaderboardService');
  const client = await db.getClient();
  const original = db.query;
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL statement_timeout = '5s'");
    await client.query(`
      CREATE TEMP TABLE users (id uuid, display_name text, avatar_url text, status text) ON COMMIT DROP;
      CREATE TEMP TABLE clubs (id uuid, name text, image_url text) ON COMMIT DROP;
      CREATE TEMP TABLE club_members (club_id uuid, user_id uuid, joined_at timestamptz) ON COMMIT DROP;
      CREATE TEMP TABLE running_sessions (user_id uuid, status text, started_at timestamptz, ended_at timestamptz, distance_km numeric) ON COMMIT DROP;
      INSERT INTO users SELECT md5(n::text)::uuid, 'Runner ' || n, NULL, 'active' FROM generate_series(1,51) n;
      INSERT INTO running_sessions SELECT id, 'completed',
        (date_trunc('week', now() AT TIME ZONE 'Asia/Bangkok') AT TIME ZONE 'Asia/Bangkok') + interval '1 hour',
        (date_trunc('week', now() AT TIME ZONE 'Asia/Bangkok') AT TIME ZONE 'Asia/Bangkok') + interval '2 hours',
        substring(display_name from '[0-9]+')::numeric FROM users;
    `);
    db.query = (...args) => client.query(...args);
    const users = (await client.query('SELECT id, display_name FROM users')).rows;
    const idOf = n => users.find(u => u.display_name === `Runner ${n}`).id;
    let board = await service.weeklyDistance(idOf(1), 'individual');
    assert.equal(board.entries.length, 50);
    assert.equal(board.myEntry.rank, null);
    assert.equal(board.myEntry.distanceKm, 1);
    assert.equal(board.entries[0].id, idOf(51));
    assert.equal(board.entries.at(-1).rank, 50);
    board = await service.weeklyDistance(idOf(51), 'individual');
    assert.equal(board.myEntry.rank, 1);
    // Ties use UUID order, giving unique stable positions rather than 51 top rows.
    await client.query('UPDATE running_sessions SET distance_km = 51 WHERE user_id = $1', [idOf(50)]);
    board = await service.weeklyDistance(idOf(51), 'individual');
    const tied = [idOf(50), idOf(51)].sort();
    assert.deepEqual(board.entries.slice(0,2).map(e => e.id), tied);
    // Last week's runs, the next week's boundary and abandoned runs do not count.
    await client.query(`INSERT INTO running_sessions VALUES
      ($1, 'completed', $2::timestamptz - interval '2 hours', $2::timestamptz - interval '1 hour', 1000),
      ($1, 'completed', $3::timestamptz - interval '1 hour', $3::timestamptz, 1000),
      ($1, 'abandoned', $2::timestamptz + interval '1 hour', $2::timestamptz + interval '2 hours', 1000)`,
      [idOf(1), board.period.startsAt, board.period.endsAt]);
    assert.equal((await service.weeklyDistance(idOf(1), 'individual')).myEntry.distanceKm, 1);
    await client.query('INSERT INTO clubs VALUES ($1, $2, NULL)', [idOf(51), 'Test guild']);
    await client.query(`INSERT INTO club_members VALUES
      ($1, $1, $3::timestamptz), ($1, $2, $3::timestamptz),
      ($1, $4, $3::timestamptz + interval '3 hours')`, [idOf(51), idOf(50), board.period.startsAt, idOf(1)]);
    const guild = await service.weeklyDistance(idOf(51), 'guild');
    assert.equal(guild.entries[0].distanceKm, 102);
    assert.equal(guild.myEntry.rank, 1);
    assert.equal((await service.weeklyDistance(idOf(2), 'guild')).myEntry, null);
  } finally {
    db.query = original;
    try { await client.query('ROLLBACK'); } finally { client.release(); await db.pool.end(); }
  }
});
