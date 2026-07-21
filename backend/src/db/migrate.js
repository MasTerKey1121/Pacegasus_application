/**
 * Runs schema.sql (or an additive migration file passed as an argument)
 * against the configured DATABASE_URL. Safe to re-run (uses IF NOT EXISTS / DO blocks).
 *
 * Usage:
 *   npm run migrate                                  -> runs schema.sql (fresh install / re-sync)
 *   node src/db/migrate.js migrations/002_add_otp_ref.sql   -> runs one additive migration file
 */
const fs = require('fs');
const path = require('path');
const { pool } = require('../config/db');

async function migrate() {
  const target = process.argv[2] || 'schema.sql';
  const filePath = path.join(__dirname, target);
  const sql = fs.readFileSync(filePath, 'utf8');

  const client = await pool.connect();
  try {
    console.log(`[migrate] Running ${target} ...`);
    await client.query(sql);
    console.log('[migrate] Done.');
  } catch (err) {
    console.error('[migrate] Failed:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

migrate();