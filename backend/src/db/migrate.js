const fs = require('fs');
const path = require('path');
const { pool } = require('../config/db');

async function migrate() {
  const arg = process.argv[2];
  
  const filePath = arg 
    ? path.resolve(process.cwd(), arg)
    : path.join(__dirname, 'schema.sql');

  console.log(`[migrate] Resolved path: ${filePath}`);

  if (!fs.existsSync(filePath)) {
    console.error(`[migrate] File not found at: ${filePath}`);
    process.exitCode = 1;
    return;
  }

  const sql = fs.readFileSync(filePath, 'utf8');

  // PRINT FIRST 100 CHARS TO INSPECT WHAT IS BEING READ
  console.log('[migrate] First 100 chars of file:\n', sql.slice(0, 100));

  const client = await pool.connect();
  try {
    console.log(`[migrate] Running ${path.basename(filePath)} ...`);
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