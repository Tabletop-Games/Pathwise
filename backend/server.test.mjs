import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createInterface } from 'node:readline';
import { test } from 'node:test';

test('HTTP server leaves publisher services unavailable by default', { timeout: 8000 }, async (t) => {
  const child = spawn(process.execPath, ['server.mjs'], {
    cwd: new URL('.', import.meta.url),
    env: {
      ...process.env, PORT: '0', PATHWISE_PLAY_VERIFIER_ENABLED: 'false',
      PATHWISE_REWARDS_ENABLED: 'false', PATHWISE_PGS_WEB_CLIENT_ID: '',
    },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const exited = once(child, 'exit');
  t.after(async () => {
    child.kill();
    await exited;
  });

  const logs = createInterface({ input: child.stdout });
  const [line] = await Promise.race([
    once(logs, 'line'),
    exited.then(() => { throw new Error('Verifier stopped before listening'); }),
  ]);
  const origin = `http://127.0.0.1:${JSON.parse(line).port}`;
  const responses = await Promise.all([
    fetch(origin + '/healthz'),
    fetch(origin + '/v1/rewards/start/refill', { method: 'POST' }),
    fetch(origin + '/v1/games/link', { method: 'POST' }),
    fetch(origin + '/v1/play/verify', { method: 'POST' }),
  ]);
  assert.deepEqual(responses.map((response) => response.status), [503, 503, 503, 403]);
  assert.equal((await responses[0].json()).status, 'disabled');
});
