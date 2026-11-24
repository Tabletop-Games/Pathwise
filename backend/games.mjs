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
