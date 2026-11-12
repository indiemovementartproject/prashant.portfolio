// Refreshes sutra-stats.json (the follower count on the Builds panel).
// Needs IG_TOKEN for @sutra.theory, which can be either kind of token Meta hands out:
//   - Instagram API with Instagram Login (60-day token, graph.instagram.com, /me)
//   - Instagram API with Unified login (system-user token that never expires,
//     graph.facebook.com, addressed by the Instagram account id below)
// Only basic profile access is needed.
// Run by .github/workflows/sutra-stats.yml every hour; safe to run by hand too:
//   IG_TOKEN=... node scripts/sutra-stats.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const token = process.env.IG_TOKEN;
if (!token) { console.log('IG_TOKEN not set; keeping the current numbers.'); process.exit(0); }
// @sutra.theory's Instagram account id, as shown in the Meta app dashboard.
const IG_USER = process.env.IG_USER_ID || '17841435384074038';

const call = async (api, path, params = {}) => {
  const u = new URL(api + path);
  for (const [k, v] of Object.entries({ ...params, access_token: token })) u.searchParams.set(k, v);
  const r = await fetch(u);
  const j = await r.json();
  if (!r.ok || j.error) throw new Error(`${path}: ${j.error ? j.error.message : r.status}`);
  return j;
};

// Work out which API this token belongs to.
let api, user, kind;
try {
  api = 'https://graph.instagram.com/v22.0'; user = 'me';
  await call(api, '/me', { fields: 'id' });
  kind = 'instagram-login';
} catch (e1) {
  try {
    api = 'https://graph.facebook.com/v22.0'; user = IG_USER;
    await call(api, `/${user}`, { fields: 'id' });
    kind = 'facebook-graph';
  } catch (e2) {
    console.error('The token works with neither API.\n  Instagram:', e1.message, '\n  Facebook:', e2.message);
    process.exit(1);
  }
}
console.log('token type:', kind);
const get = (path, params) => call(api, path, params);

const file = new URL('../sutra-stats.json', import.meta.url);
const stats = JSON.parse(readFileSync(file, 'utf8'));
const me = await get(`/${user}`, { fields: 'followers_count' });
stats.followers = me.followers_count;
stats.updated = new Date().toISOString();
stats.source = 'instagram';
writeFileSync(file, JSON.stringify(stats, null, 2) + '\n');
console.log('followers', stats.followers);

// A 60-day Instagram Login token is kept alive by refreshing it. If Instagram hands back a
// different string, the workflow stores it as the new IG_TOKEN secret. System-user tokens never expire.
if (kind === 'instagram-login') {
  try {
    const r = await fetch('https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=' + encodeURIComponent(token));
    const j = await r.json();
    if (j.access_token && j.access_token !== token) writeFileSync('.ig-token-new', j.access_token);
  } catch (e) { console.log('token refresh failed:', e.message); }
}
