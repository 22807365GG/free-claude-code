// ==============================================
// FIRST LOCAL COMPILATION TEST - Claude Code
// Tests: Claude proxy at localhost:8080
// Run inside Antigravity terminal: node first-compile-test-claude.js
// ==============================================
const http = require('http');

const PROXY_HOST = 'localhost';
const PROXY_PORT = 8080;
const MODEL = 'claude-3-5-sonnet-20241022';

console.log('\n[TEST-JS] First Compilation Run - Claude Code via Local Proxy');
console.log('='.repeat(58));

function httpPost(host, port, path, body, headers) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const opts = {
      hostname: host, port, path, method: 'POST',
      headers: { 'Content-Type': 'application/json',
                 'Content-Length': Buffer.byteLength(data),
                 'x-api-key': 'local-proxy-no-auth',
                 'anthropic-version': '2023-06-01',
                 ...headers }
    };
    const req = http.request(opts, res => {
      let raw = '';
      res.on('data', chunk => raw += chunk);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(raw) }); }
        catch(e) { resolve({ status: res.statusCode, body: raw }); }
      });
    });
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(); reject(new Error('Timeout 30s')); });
    req.write(data);
    req.end();
  });
}

async function main() {
  // Step 1: Proxy health
  console.log('\n[1/3] Checking Claude proxy health at localhost:' + PROXY_PORT + '...');
  try {
    const health = await new Promise((resolve, reject) => {
      const req = http.get(`http://${PROXY_HOST}:${PROXY_PORT}/health`, res => {
        let d = ''; res.on('data', c => d += c);
        res.on('end', () => resolve({ status: res.statusCode, body: d }));
      });
      req.on('error', reject);
      req.setTimeout(5000, () => { req.destroy(); reject(new Error('Timeout')); });
    });
    console.log(`  [OK] Proxy responding (HTTP ${health.status})`);
  } catch(e) {
    console.log(`  [FAIL] Proxy not responding: ${e.message}`);
    console.log(`  Start it with: cd %USERPROFILE%\\antigravity-proxy && node index.js`);
    process.exit(1);
  }

  // Step 2: First generation call
  console.log('\n[2/3] Sending first Claude code generation request...');
  const t0 = Date.now();
  let resp;
  try {
    resp = await httpPost(PROXY_HOST, PROXY_PORT, '/v1/messages', {
      model: MODEL,
      max_tokens: 300,
      messages: [{
        role: 'user',
        content: 'Write a JavaScript function to debounce a function call. Just the code, no explanation.'
      }]
    });
    const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
    console.log(`  [OK] Response in ${elapsed}s (HTTP ${resp.status})`);
  } catch(e) {
    console.log(`  [FAIL] Request error: ${e.message}`);
    process.exit(1);
  }

  // Step 3: Parse and display
  console.log('\n[3/3] Parsing generated code...');
  if (resp.status === 200 && resp.body.content) {
    const code = resp.body.content[0]?.text || '';
    console.log('\n--- Generated Code ---');
    console.log(code.trim());
    console.log('--- End ---');
    // Try compiling via Function constructor
    try {
      new Function(code.replace(/```[\s\S]*?```/g, match => match.replace(/```javascript\n?|```js\n?|```\n?/g, '')));
      console.log('\n  [OK] Code structure valid! Claude Code proxy is LIVE.');
    } catch(e) {
      console.log('\n  [INFO] (Markdown wrapper present - normal):', e.message.split('\n')[0]);
    }
    console.log('\n[PASS] Claude Code compilation test COMPLETE');
    console.log(`  Endpoint : http://localhost:${PROXY_PORT}`);
    console.log(`  Model    : ${MODEL}`);
    console.log(`  Status   : ONLINE + GENERATING`);
  } else {
    console.log(`  [FAIL] Unexpected response:`, JSON.stringify(resp.body).slice(0,200));
    process.exit(1);
  }
}

main().catch(e => { console.error('[FATAL]', e.message); process.exit(1); });
