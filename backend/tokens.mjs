import { createHmac, randomBytes, timingSafeEqual, createHash } from 'node:crypto';

const b64 = (value) => Buffer.from(value).toString('base64url');
export const sha256 = (value) => createHash('sha256').update(value).digest('hex');
export const randomToken = (bytes = 32) => randomBytes(bytes).toString('hex');

/**
 * Key ring format: "kid:secret,kid2:secret2". The first entry signs; every
 * entry verifies, so keys can be rotated without invalidating live sessions.
 * Secrets come from Secret Manager (PATHWISE_SESSION_KEYS), never from the repo.
 */
export function parseKeyRing(text) {
  const keys = new Map();
  for (const entry of String(text ?? '').split(',').map((part) => part.trim()).filter(Boolean)) {
    const index = entry.indexOf(':');
    const kid = entry.slice(0, index);
    const secret = entry.slice(index + 1);
    if (index < 1 || !/^[A-Za-z0-9_-]{1,16}$/.test(kid) || secret.length < 32) {
      throw new Error('Invalid PATHWISE_SESSION_KEYS entry');
    }
    keys.set(kid, secret);
  }
  if (keys.size === 0) throw new Error('PATHWISE_SESSION_KEYS is required');
  return keys;
}

export function createSigner(keys, { now = Date.now } = {}) {
  const ring = keys instanceof Map ? keys : parseKeyRing(keys);
  const [currentId, currentSecret] = ring.entries().next().value;
  const mac = (secret, text) => createHmac('sha256', secret).update(text).digest();
  return {
    sign(kind, claims, ttlMs) {
      const issued = now();
      const body = b64(JSON.stringify({ k: kind, ...claims, iat: issued, exp: issued + ttlMs }));
      const head = `${currentId}.${body}`;
      return `pw1.${head}.${b64(mac(currentSecret, head))}`;
    },
    verify(kind, token) {
      if (typeof token !== 'string' || token.length > 2048) return null;
      const parts = token.split('.');
      if (parts.length !== 4 || parts[0] !== 'pw1') return null;
      const secret = ring.get(parts[1]);
      if (!secret) return null;
      const head = `${parts[1]}.${parts[2]}`;
      const expected = mac(secret, head);
      let given;
      try { given = Buffer.from(parts[3], 'base64url'); } catch { return null; }
      if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
      let claims;
      try { claims = JSON.parse(Buffer.from(parts[2], 'base64url').toString()); } catch { return null; }
      if (claims?.k !== kind || !Number.isFinite(claims.exp) || now() >= claims.exp || claims.iat > now() + 60000) return null;
      return claims;
    },
  };
}
