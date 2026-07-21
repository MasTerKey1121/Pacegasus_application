const app = require('./app');
const env = require('./config/env');

app.listen(env.port, () => {
  // eslint-disable-next-line no-console
  console.log(`[server] Pacegasus API listening on http://localhost:${env.port}`);
  console.log(`[server] Environment: ${env.nodeEnv}`);
});
