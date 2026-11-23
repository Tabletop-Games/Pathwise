import { createHash } from 'node:crypto';

const hash = (value) => createHash('sha256').update(value).digest('hex');

export async function verifiedGamePlayer(code, oauth, fetcher = fetch) {
  const token = await fetcher('https://oauth2.googleapis.com/token', {
    method: 'POST', signal: AbortSignal.timeout(6000),
    body: new URLSearchParams({
      code, client_id: oauth.clientId, client_secret: oauth.secret,
      grant_type: 'authorization_code', redirect_uri: '',
    }),
  });
  if (!token.ok) return null;
  const { access_token: access } = await token.json();
  if (typeof access !== 'string' || !access) return null;
  const profile = await fetcher('https://games.googleapis.com/games/v1/players/me', {
    headers: { Authorization: `Bearer ${access}` }, signal: AbortSignal.timeout(6000),
  });
  if (!profile.ok) return null;
  const { playerId } = await profile.json();
  return typeof playerId === 'string' && playerId.length > 0 && playerId.length <= 256 ? playerId : null;
}

export async function linkGameAccount(request, db) {
  const clientId = process.env.PATHWISE_PGS_WEB_CLIENT_ID;
  const secret = process.env.PATHWISE_PGS_WEB_CLIENT_SECRET;
  if (!clientId || !secret) return [503, { error: 'disabled' }];
  const key = /^Bearer ([a-f0-9]{64})$/.exec(request.headers.authorization ?? '')?.[1];
  if (!key) return [403, { error: 'unauthorized' }];
  const owner = hash(key);
  const guards = db.collection('pathwise-games-link-rate').doc(owner);
  const now = Date.now();
  const permit = await db.runTransaction(async (tx) => {
    const prior = await tx.get(guards);
    if (now < (prior.get('next') ?? 0)) return false;
    tx.set(guards, { next: now + 15000, expiresAt: new Date(now + 86400000) });
    return true;
  });
  if (!permit) return [429, { error: 'rate_limit' }];
  let size = 0;
  const chunks = [];
  for await (const chunk of request.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > 4096) return [413, { error: 'payload_too_large' }];
    chunks.push(chunk);
  }
  let code;
  try { ({code} = JSON.parse(Buffer.concat(chunks).toString())); }
  catch (_) { return [422, { error: 'invalid_payload' }]; }
  if (typeof code !== 'string' || code.length < 8 || code.length > 2048) return [422, { error: 'invalid_code' }];
  const player = await verifiedGamePlayer(code, { clientId, secret });
  if (!player) return [403, { error: 'account_unavailable' }];
  const playerKey = hash(player);
  const account = db.collection('pathwise-games-accounts').doc(playerKey);
  const profile = db.collection('pathwise-games-profiles').doc(owner);
  const linked = await db.runTransaction(async (tx) => {
    const [a, p] = await tx.getAll(account, profile);
    if ((a.exists && a.get('owner') !== owner) || (p.exists && p.get('account') !== playerKey)) return false;
    tx.set(account, { owner });
    tx.set(profile, { account: playerKey });
    return true;
  });
  return linked ? [200, { linked: true }] : [409, { error: 'already_linked' }];
}
