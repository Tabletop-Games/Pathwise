import { createHash, randomBytes, verify } from 'node:crypto';

const placements = {
  coins: 'PATHWISE_ADMOB_REWARDED',
  hint: 'PATHWISE_ADMOB_EXTRA_HINT',
  refill: 'PATHWISE_ADMOB_HINT_REFILL',
};
export const consoleProbe = 'pathwise-console-check';
const unitId = (value) => /^(?:ca-app-pub-\d{16}\/)?(\d{10})$/.exec(value ?? '')?.[1];
const digest = (value) => createHash('sha256').update(value).digest('hex');

export function decodeReward(query, keyFor, now = Date.now(), allowProbe = false) {
  const match = /^(.*)&signature=([A-Za-z0-9_%=-]+)&key_id=(\d+)$/.exec(query);
  if (!match) return null;
  const [_, message, encoded, keyId] = match;
  const data = new URLSearchParams(message);
  const fields = ['transaction_id','custom_data','ad_unit','timestamp'];
  if (fields.some((field) => data.getAll(field).length !== 1)) return null;
  const token = data.get('custom_data');
  const transaction = data.get('transaction_id');
  const time = Number(data.get('timestamp'));
  const unit = unitId(data.get('ad_unit'));
  const isProbe = allowProbe && token === consoleProbe;
  if ((!isProbe && !/^[a-f0-9]{64}$/.test(token)) || !transaction || transaction.length > 256 ||
      !unit || !Number.isSafeInteger(time) || Math.abs(now - time) > 3600000) return null;
  const key = keyFor(keyId);
  if (!key || !verify('sha256', Buffer.from(message), key,
    Buffer.from(decodeURIComponent(encoded), 'base64url'))) return null;
  return { token, id: digest(transaction), unit, time };
}

let cached, loadedAt = 0;
async function googleKeys(force = false) {
  if (!force && cached && Date.now() - loadedAt < 3600000) return cached;
  const response = await fetch('https://www.gstatic.com/admob/reward/verifier-keys.json',
    { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error('Verifier keys unavailable');
  const { keys } = await response.json();
  cached = new Map(keys.map((key) => [String(key.keyId), key.pem]));
  loadedAt = Date.now();
  return cached;
}

export async function rewardRequest(request, db) {
  const path = request.url.split('?')[0];
  if (!path.startsWith('/v1/rewards/')) return null;
  if (process.env.PATHWISE_REWARDS_ENABLED !== 'true') return [503, { error: 'disabled' }];
  const configuredUnits = Object.values(placements).map((name) => unitId(process.env[name]));
  if (configuredUnits.some((unit) => !unit) || new Set(configuredUnits).size !== configuredUnits.length) {
    return [503, { error: 'placement_unavailable' }];
  }
  const sessions = db.collection('pathwise-ad-sessions');
  const now = Date.now();
  if (request.method === 'GET' && path === '/v1/rewards/callback') {
    const query = request.url.slice(path.length + 1);
    if (query.length > 4800) return [422, { error: 'invalid_callback' }];
    let keys = await googleKeys();
    const keyId = /&key_id=(\d+)$/.exec(query)?.[1];
    if (keyId && !keys.has(keyId) && now - loadedAt > 60000) keys = await googleKeys(true);
    const reward = decodeReward(query, (id) => keys.get(id), now, true);
    if (!reward || !configuredUnits.includes(reward.unit)) return [403, { error: 'invalid_signature' }];
    if (reward.token === consoleProbe) return [200, { verified: true, probe: true }];
    const session = sessions.doc(reward.token);
    const receipt = db.collection('pathwise-ad-receipts').doc(reward.id);
    const applied = await db.runTransaction(async (tx) => {
      const [saved, existing] = await tx.getAll(session, receipt);
      if (existing.exists) return existing.get('session') === reward.token;
      if (!saved.exists || saved.get('unit') !== reward.unit || saved.get('receipt') ||
          reward.time < saved.get('created') - 10000 || reward.time > saved.get('created') + 900000) return false;
      tx.create(receipt, { session: reward.token, expiresAt: new Date(now + 7 * 86400000) });
      tx.update(session, { receipt: reward.id });
      return true;
    });
    return applied ? [200, { verified: true }] : [403, { error: 'invalid_session' }];
  }
  const bearer = /^Bearer ([a-f0-9]{64})$/.exec(request.headers.authorization ?? '')?.[1];
  if (!bearer) return [403, { error: 'unauthorized' }];
  const owner = digest(bearer);
  const issue = /^\/v1\/rewards\/start\/(coins|hint|refill)$/.exec(path)?.[1];
  if (request.method === 'POST' && issue) {
    const unit = unitId(process.env[placements[issue]]);
    if (!unit) return [503, { error: 'placement_unavailable' }];
    const token = randomBytes(32).toString('hex');
    const rate = db.collection('pathwise-ad-rate').doc(owner);
    const created = await db.runTransaction(async (tx) => {
      const previous = await tx.get(rate);
      if (now < (previous.get('next') ?? 0)) return false;
      tx.set(rate, { next: now + 15000, expiresAt: new Date(now + 86400000) });
      tx.create(sessions.doc(token), { owner, unit, issue, created: now, expiresAt: new Date(now + 86400000) });
      return true;
    });
    return created ? [200, { token }] : [429, { error: 'rate_limit' }];
  }
  const token = /^\/v1\/rewards\/status\/([a-f0-9]{64})$/.exec(path)?.[1];
  if (request.method === 'GET' && token) {
    const saved = await sessions.doc(token).get();
    if (saved.get('owner') !== owner || now - saved.get('created') > 86400000) return [404, { error: 'not_found' }];
    const id = saved.get('receipt');
    return id ? [200, { id, placement: saved.get('issue') }] : [202, { pending: true }];
  }
  return [404, { error: 'not_found' }];
}
