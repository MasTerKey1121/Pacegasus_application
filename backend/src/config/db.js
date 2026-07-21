const { Pool } = require('pg');
const env = require('./env');

const pool = new Pool({
  connectionString: env.databaseUrl,
  ssl: env.dbSsl ? { rejectUnauthorized: false } : false,
});

pool.on('error', (err) => {
  // eslint-disable-next-line no-console
  console.error('[db] Unexpected error on idle client', err);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  getClient: () => pool.connect(),
  pool,
};
