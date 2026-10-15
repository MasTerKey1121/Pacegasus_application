// Local-only bridge: saves asserted checkpoints and consumes a human-entered OTP.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const runtime = path.resolve(process.argv[2] || '.uat-runtime');
const output = path.resolve(process.argv[3] || '../output/uat/automated/latest');
const port = Number(process.argv[4] || 8765);
fs.mkdirSync(runtime, { recursive: true });
fs.mkdirSync(path.join(output, 'screenshots'), { recursive: true });
const checkpoints = [];
let state = 'running';
let detail = '';
let scope = 'Selected assertions only. Other UAT cases remain Not Run. No account deletion.';
const contextFile = path.join(runtime, 'live-context.json');
const allowedContext = new Set(['primaryUid', 'secondaryUid', 'clubId', 'clubName', 'friendshipId']);
function saveReport() {
  fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({
    state, detail, checkpoints,
    scope,
  }, null, 2));
  const lines = [
    '# Automated UAT — Pacegasus', '',
    `Status: **${state}**`, '', detail, '',
    'Tests run through Flutter Integration Test against the configured real API.',
    scope, '',
    'Screenshots support only the stated assertions. A completed phase does not mean all 88 UAT cases passed.', '',
    '| Step | Result | Evidence |', '| --- | --- | --- |',
    ...checkpoints.map(c => `| ${c.description.replaceAll('|', '/')} | ${c.status} | [${c.name}](screenshots/${c.name}.png) |`),
    '', '## Screenshots', '',
    ...checkpoints.flatMap(c => [`### ${c.description}`, '', `![${c.name}](screenshots/${c.name}.png)`, '']),
  ];
  fs.writeFileSync(path.join(output, 'UAT-REPORT.md'), lines.join('\n'));
}
saveReport();
http.createServer(async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'application/json');
  try {
    if (req.method === 'GET' && req.url === '/status') {
      res.end(JSON.stringify({ state, detail, checkpoints: checkpoints.length }));
      return;
    }
    if (req.method === 'GET' && req.url === '/otp') {
      const file = path.join(runtime, 'otp.txt');
      const code = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').trim() : '';
      if (/^\d{6}$/.test(code)) {
        fs.unlinkSync(file); // Consume once; never log or include OTP in reports.
        res.end(JSON.stringify({ code }));
      } else {
        res.end('{}');
      }
      return;
    }
    if (req.method === 'GET' && req.url.startsWith('/context?')) {
      const environment = new URL(req.url, 'http://localhost').searchParams.get('environment');
      const contexts = fs.existsSync(contextFile) ? JSON.parse(fs.readFileSync(contextFile, 'utf8')) : {};
      res.end(JSON.stringify(contexts[environment] || {}));
      return;
    }
    if (req.method !== 'POST') { res.writeHead(404); res.end('{}'); return; }
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 16 * 1024 * 1024) throw Error('Payload too large');
      chunks.push(chunk);
    }
    const body = JSON.parse(Buffer.concat(chunks).toString());
    if (req.url === '/checkpoint') {
      if (!/^[a-z0-9_-]+$/.test(body.name)) throw Error('Invalid checkpoint name');
      if (!['passed', 'failed', 'blocked', 'not_run'].includes(body.status)) throw Error('Invalid checkpoint status');
      const bytes = Buffer.from(body.png, 'base64');
      if (!bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw Error('Invalid PNG');
      fs.writeFileSync(path.join(output, 'screenshots', `${body.name}.png`), bytes);
      checkpoints.push({ name: body.name, description: body.description,
        status: body.status });
      console.log(`CHECKPOINT ${body.name}: ${body.status || 'passed'}`);
    } else if (req.url === '/context') {
      if (typeof body.environment !== 'string' || !body.environment) throw Error('Missing environment');
      const values = body.values;
      if (!values || Object.entries(values).some(([key, value]) => !allowedContext.has(key) || typeof value !== 'string')) throw Error('Only public UAT identifiers may be saved');
      const contexts = fs.existsSync(contextFile) ? JSON.parse(fs.readFileSync(contextFile, 'utf8')) : {};
      contexts[body.environment] = { ...contexts[body.environment], ...values };
      fs.writeFileSync(contextFile, JSON.stringify(contexts, null, 2));
    } else if (req.url === '/scope') {
      if (typeof body.description !== 'string') throw Error('Missing scope');
      scope = body.description;
    } else if (req.url === '/state') {
      state = body.state;
      detail = body.detail || '';
      console.log(`STATE ${state}: ${detail}`);
    } else { res.writeHead(404); res.end('{}'); return; }
    saveReport();
    res.end('{"ok":true}');
  } catch (error) {
    res.writeHead(400); res.end(JSON.stringify({ error: error.message }));
  }
}).listen(port, '127.0.0.1', () => {
  console.log(`UAT bridge ready on localhost:${port}`);
  console.log(`Report: ${path.join(output, 'UAT-REPORT.md')}`);
});
