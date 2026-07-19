/**
 * Runs schema.sql against the configured DATABASE_URL to (re)create
 * the Pacegasus tables. Safe to re-run (uses IF NOT EXISTS / DO blocks).
 *
 * Usage: npm run migrate
 */
const fs = require('fs');
const path = require('path');
const { pool } = require('../config/db');

async function migrate() {
  const schemaPath = path.join(__dirname, 'schema.sql');
  const sql = fs.readFileSync(schemaPath, 'utf8');

  const client = await pool.connect();
  try {
    console.log('[migrate] Running schema.sql ...');
    await client.query(sql);
    console.log('[migrate] Done. Tables are ready.');
  } catch (err) {
    console.error('[migrate] Failed:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

migrate();
