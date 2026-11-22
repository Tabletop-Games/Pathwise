import { createServer } from 'node:http';

import { Firestore, FieldValue } from '@google-cloud/firestore';
import { GoogleAuth } from 'google-auth-library';

import { appPackage, verifyReceipt } from './verify.mjs';

const db = new Firestore();
const google = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/androidpublisher'],
});
const collection = db.collection('pathwise-play-purchase-grants');
const active = process.env.PATHWISE_PLAY_VERIFIER_ENABLED === 'true';
let readyUntil = 0;

async function checkReadiness() {
  if (!active) return false;
  if (Date.now() < readyUntil) return true;
  const [[probe], accessToken] = await Promise.all([
    db.getAll(collection.doc('readiness')),
    google.getAccessToken(),
  ]);
  const ready = probe.get('enabled') === true && Boolean(accessToken);
  if (ready) readyUntil = Date.now() + 15000;
  return ready;
}

async function getPurchase(token) {
  const client = await google.getClient();
  const app = encodeURIComponent(appPackage);
  const endpoint = 'https://androidpublisher.googleapis.com/androidpublisher/v3';
  const url = `${endpoint}/applications/${app}/purchases/productsv2/tokens/${encodeURIComponent(token)}`;
  try {
    return (await client.request({ url, timeout: 8000, retry: false })).data;
  } catch (error) {
    if ([400, 404, 410].includes(error.response?.status)) return null;
    throw error;
  }
}

function claim(id, grant, { consumed }) {
  const ref = collection.doc(id);
  return db.runTransaction(async (tx) => {
    const record = await tx.get(ref);
    if (record.exists) {
      return record.get('product') === grant.product && record.get('profile') === grant.profile;
    }
    if (consumed) return false;
    tx.create(ref, { ...grant, at: FieldValue.serverTimestamp() });
    return true;
  });
}

function send(response, status, body) {
  response.writeHead(status, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(JSON.stringify(body));
}

const server = createServer(async (request, response) => {
  if (request.method === 'GET' && request.url === '/healthz') {
    const ready = await checkReadiness().catch(() => false);
    send(response, ready ? 200 : 503, { status: ready ? 'ready' : 'disabled', package: appPackage, catalog: 2 });
    return;
  }
  if (request.method !== 'POST' || request.url !== '/v1/play/verify') {
    send(response, 404, { error: 'not_found' });
    return;
  }
  if (!/^Bearer [a-f0-9]{64}$/.test(request.headers.authorization ?? '') ||
      request.headers['content-type']?.split(';')[0] !== 'application/json') {
    send(response, 403, { error: 'purchase_not_verifiable' });
    return;
  }
  try {
    if (!await checkReadiness()) {
      send(response, 503, { error: 'verification_unavailable' });
      return;
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of request.iterator({ destroyOnReturn: false })) {
      size += chunk.length;
      if (size > 4096) {
        send(response, 413, { error: 'payload_too_large' });
        request.resume();
        return;
      }
      chunks.push(chunk);
    }
    const body = JSON.parse(Buffer.concat(chunks).toString());
    const result = await verifyReceipt(request.headers.authorization, body, { getPurchase, claim });
    send(response, result.status, result.body);
  } catch (error) {
    const malformed = error instanceof SyntaxError;
    send(response, malformed ? 422 : 503, {
      error: malformed ? 'invalid_purchase' : 'verification_unavailable',
    });
  }
});
server.requestTimeout = 15000;
server.headersTimeout = 10000;
server.listen(Number(process.env.PORT ?? 8080));
