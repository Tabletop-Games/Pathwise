import assert from 'node:assert/strict';
import { test } from 'node:test';
import { verifiedGamePlayer } from './games.mjs';

test('account link uses the server-verified player, not input identity', async () => {
  const paths = [];
  const player = await verifiedGamePlayer('test-authorization-code', {clientId:'client',secret:'secret'},
    async (uri, options) => {
      paths.push(uri);
      if (paths.length === 1) {
        assert.equal(options.body.get('grant_type'), 'authorization_code');
        return new Response(JSON.stringify({access_token:'temporary'}));
      }
      assert.equal(options.headers.Authorization, 'Bearer temporary');
      return new Response(JSON.stringify({playerId:'verified-player'}));
    });
  assert.deepEqual(paths, ['https://oauth2.googleapis.com/token','https://games.googleapis.com/games/v1/players/me']);
  assert.equal(player, 'verified-player');
  assert.equal(await verifiedGamePlayer('bad', {}, async () => new Response('{}', {status:403})), null);
});
