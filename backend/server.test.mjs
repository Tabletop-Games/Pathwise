import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { existsSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { test } from 'node:test';

const installed = existsSync(new URL('./node_modules/@google-cloud/firestore', import.meta.url));

async function boot(t, env) {
  const child = spawn(process.execPath, ['server.mjs'], {
    cwd: new URL('.', import.meta.url), env: { ...process.env, PORT: '0', ...env }, stdio: ['ignore', 'pipe', 'inherit'],
  });
  const exited = once(child, 'exit');
  t.after(async () => { child.kill(); await exited; });
  const logs = createInterface({ input: child.stdout });
  const [line] = await Promise.race([once(logs, 'line'), exited.then(() => { throw new Error('Server stopped before listening'); })]);
  return `http://127.0.0.1:${JSON.parse(line).port}`;
}

// Needs `npm ci`: the production entry point imports the Google client libraries.
test('the service starts disabled by default and refuses to run without an environment name', { skip: !installed, timeout: 10000 }, async (t) => {
  const origin = await boot(t, { PATHWISE_ENV: 'development', PATHWISE_ONLINE_ENABLED: 'false' });
  const [health, ping, register] = await Promise.all([
    fetch(origin + '/healthz'), fetch(origin + '/v1/ping'),
    fetch(origin + '/v1/auth/register', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }),
  ]);
  assert.deepEqual([health.status, ping.status, register.status], [503, 503, 503]);
  assert.equal((await health.json()).status, 'disabled');
  await assert.rejects(boot(t, { PATHWISE_ENV: '' }));
});
