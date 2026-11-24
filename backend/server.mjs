import { createServer } from 'node:http';

import { Firestore } from '@google-cloud/firestore';
import { GoogleAuth, OAuth2Client } from 'google-auth-library';

import { createApp } from './app.mjs';
import { createAuth } from './auth.mjs';
import { appPackages } from './economy-config.mjs';
import { verifiedGamePlayer } from './games.mjs';
import { HttpError } from './http.mjs';
import { createIntegrity, googleDecoder } from './integrity.mjs';
import { createPlayApi, createPurchases } from './purchases.mjs';
import { createRewards } from './rewards.mjs';
import { createSigner, parseKeyRing } from './tokens.mjs';

const env = process.env.PATHWISE_ENV;
if (!Object.hasOwn(appPackages, env ?? '')) {
  console.error(JSON.stringify({ severity: 'CRITICAL', event: 'config', error: 'PATHWISE_ENV must be production or development' }));
  process.exit(1);
}
const onlineEnabled = process.env.PATHWISE_ONLINE_ENABLED === 'true';
if (onlineEnabled && !process.env.PATHWISE_SESSION_KEYS) {
  console.error(JSON.stringify({ severity: 'CRITICAL', event: 'config', error: 'PATHWISE_SESSION_KEYS is required' }));
  process.exit(1);
}

const db = new Firestore({ ignoreUndefinedProperties: true });
const google = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher',
  'https://www.googleapis.com/auth/playintegrity'] });
const packageName = appPackages[env];
const signer = createSigner(onlineEnabled ? parseKeyRing(process.env.PATHWISE_SESSION_KEYS) : new Map([['x', 'x'.repeat(32)]]));
const integrity = createIntegrity({
  required: process.env.PATHWISE_INTEGRITY_REQUIRED === 'true', packageName,
  certDigests: (process.env.PATHWISE_APP_CERT_SHA256 ?? '').split(',').map((v) => v.trim()).filter(Boolean),
  decode: googleDecoder(google),
});
const oauth = { clientId: process.env.PATHWISE_PGS_WEB_CLIENT_ID, secret: process.env.PATHWISE_PGS_WEB_CLIENT_SECRET };
const verifyGamesCode = async (code) => (oauth.clientId && oauth.secret ? verifiedGamePlayer(code, oauth) : null);
const auth = createAuth({ db, signer, env, integrity, verifyGamesCode });
const purchases = createPurchases({ db, play: createPlayApi(google, packageName), env });
const rewards = createRewards({ db });

// Pub/Sub push and Cloud Scheduler authenticate with Google-signed OIDC tokens.
const oidc = new OAuth2Client();
const pushIdentities = {
  rtdn: [process.env.PATHWISE_RTDN_AUDIENCE, process.env.PATHWISE_RTDN_SERVICE_ACCOUNT],
  reconcile: [process.env.PATHWISE_RECONCILE_AUDIENCE, process.env.PATHWISE_RECONCILE_SERVICE_ACCOUNT],
};
async function verifyPush(request, kind) {
  const [audience, account] = pushIdentities[kind];
  const header = request.headers.authorization ?? '';
  if (!audience || !account || !header.startsWith('Bearer ')) throw new HttpError(403, 'forbidden');
  try {
    const ticket = await oidc.verifyIdToken({ idToken: header.slice(7), audience });
    const payload = ticket.getPayload();
    if (payload?.email !== account || payload.email_verified !== true) throw new Error('identity');
  } catch { throw new HttpError(403, 'forbidden'); }
}

let healthUntil = 0;
async function health() {
  if (Date.now() < healthUntil) return true;
  await db.collection('pathwise-system').doc('health').get();
  healthUntil = Date.now() + 15000;
  return true;
}

const handle = createApp({
  db, env, auth, purchases, rewards, verifyPush, health, onlineEnabled,
  minBuild: Number(process.env.PATHWISE_MIN_BUILD ?? 0),
});
const server = createServer((request, response) => { void handle(request, response); });
server.requestTimeout = 15000;
server.headersTimeout = 10000;
server.listen(Number(process.env.PORT ?? 8080), () => {
  console.log(JSON.stringify({ severity: 'INFO', event: 'listening', port: server.address().port, env }));
});
