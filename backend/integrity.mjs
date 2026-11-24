import { createHash } from 'node:crypto';

/** Nonce the Android client must pass to the Play Integrity API for a given server challenge. */
export const nonceFor = (challenge) => createHash('sha256').update(challenge).digest('base64url');

/**
 * Play Integrity verification for registration and recovery. `decode` calls
 * playintegrity.googleapis.com decodeIntegrityToken using the Cloud Run service
 * identity. Disabled unless PATHWISE_INTEGRITY_REQUIRED=true.
 */
export function createIntegrity({ required, packageName, certDigests = [], decode, now = Date.now }) {
  return {
    required,
    async verify(token, challenge) {
      if (!required) return true;
      if (typeof token !== 'string' || token.length < 20 || token.length > 8192 || typeof challenge !== 'string') return false;
      let payload;
      try { payload = (await decode(token, packageName))?.tokenPayloadExternal; } catch { return false; }
      if (!payload) return false;
      const request = payload.requestDetails ?? {};
      const app = payload.appIntegrity ?? {};
      const device = payload.deviceIntegrity?.deviceRecognitionVerdict ?? [];
      const age = now() - Number(request.timestampMillis);
      return request.requestPackageName === packageName && request.nonce === nonceFor(challenge) &&
        Number.isFinite(age) && age >= -60000 && age <= 5 * 60000 &&
        app.appRecognitionVerdict === 'PLAY_RECOGNIZED' &&
        (certDigests.length === 0 || (app.certificateSha256Digest ?? []).some((d) => certDigests.includes(d))) &&
        device.includes('MEETS_DEVICE_INTEGRITY');
    },
  };
}

export const googleDecoder = (google) => async (token, packageName) => {
  const client = await google.getClient();
  const url = `https://playintegrity.googleapis.com/v1/${encodeURIComponent(packageName)}:decodeIntegrityToken`;
  return (await client.request({ url, method: 'POST', data: { integrity_token: token }, timeout: 8000, retry: false })).data;
};
