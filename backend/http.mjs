export class HttpError extends Error {
  constructor(status, code, extra = {}) { super(code); this.status = status; this.code = code; this.extra = extra; }
}

export async function readJson(request, limit = 8192) {
  const type = request.headers['content-type']?.split(';')[0].trim();
  if (type !== 'application/json') throw new HttpError(415, 'unsupported_media_type');
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > limit) { request.resume(); throw new HttpError(413, 'payload_too_large'); }
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('shape');
    return value;
  } catch { throw new HttpError(422, 'invalid_json'); }
}

export function send(response, status, body, headers = {}) {
  response.writeHead(status, {
    'Content-Type': 'application/json', 'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff', ...headers,
  });
  response.end(JSON.stringify(body));
}

/** Per-instance fixed-window limiter. Cheap guard; Firestore guards protect scarce endpoints. */
export function memoryLimiter({ limit, windowMs, now = Date.now, max = 5000 }) {
  const buckets = new Map();
  return (key) => {
    const time = now();
    const bucket = buckets.get(key);
    if (!bucket || time - bucket.start >= windowMs) {
      if (buckets.size >= max) buckets.delete(buckets.keys().next().value);
      buckets.set(key, { start: time, count: 1 });
      return true;
    }
    bucket.count++;
    return bucket.count <= limit;
  };
}

/** Durable limiter used for registration and other abuse-sensitive endpoints. */
export async function durableLimit(db, name, key, { limit, windowMs, now = Date.now }) {
  const ref = db.collection(name).doc(key);
  const time = now();
  return db.runTransaction(async (tx) => {
    const prior = await tx.get(ref);
    const start = prior.get('start') ?? 0;
    const inWindow = time - start < windowMs;
    const count = inWindow ? prior.get('count') ?? 0 : 0;
    if (count >= limit) return false;
    tx.set(ref, { start: inWindow ? start : time, count: count + 1, expiresAt: new Date(time + 2 * windowMs) });
    return true;
  });
}

export const clientAddress = (request) => {
  const forwarded = String(request.headers['x-forwarded-for'] ?? '').split(',');
  // Cloud Run appends the real client as the last entry that it controls.
  return (forwarded[forwarded.length - 1] || request.socket?.remoteAddress || 'unknown').trim();
};
