// Refreshes sutra-stats.json (follower count and reel views for the Builds panel)
// from the Instagram API with Instagram Login. Needs IG_TOKEN: a long-lived token for
// @sutra.theory with instagram_business_basic and instagram_business_manage_insights.
// Run by .github/workflows/sutra-stats.yml every hour; safe to run by hand too:
//   IG_TOKEN=... node scripts/sutra-stats.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const API = 'https://graph.instagram.com/v22.0';
const token = process.env.IG_TOKEN;
if (!token) { console.log('IG_TOKEN not set; keeping the current numbers.'); process.exit(0); }

const get = async (path, params = {}) => {
  const u = new URL(API + path);
  for (const [k, v] of Object.entries({ ...params, access_token: token })) u.searchParams.set(k, v);
  const r = await fetch(u);
  const j = await r.json();
  if (!r.ok || j.error) throw new Error(`${path}: ${j.error ? j.error.message : r.status}`);
  return j;
};

const file = new URL('../sutra-stats.json', import.meta.url);
const stats = JSON.parse(readFileSync(file, 'utf8'));
const wanted = new Set(Object.keys(stats.reels));

const me = await get('/me', { fields: 'followers_count' });
stats.followers = me.followers_count;

// Walk the media list until every reel shown on the site has been found.
let page = await get('/me/media', { fields: 'id,shortcode', limit: '50' });
const ids = {};
while (page) {
  for (const m of page.data) if (wanted.has(m.shortcode)) ids[m.shortcode] = m.id;
  if (Object.keys(ids).length === wanted.size || !page.paging || !page.paging.next) break;
  const r = await fetch(page.paging.next); page = await r.json();
}
for (const [code, id] of Object.entries(ids)) {
  try {
    const ins = await get(`/${id}/insights`, { metric: 'views' });
    const v = ins.data && ins.data[0] && ins.data[0].values && ins.data[0].values[0].value;
    if (typeof v === 'number') stats.reels[code] = v;
  } catch (e) { console.log('views for', code, 'failed:', e.message); }
}
stats.updated = new Date().toISOString();
stats.source = 'instagram';
writeFileSync(file, JSON.stringify(stats, null, 2) + '\n');
console.log('followers', stats.followers, stats.reels);

// Keep the token alive: a long-lived token lasts 60 days, and refreshing it starts a new 60 days.
// If Instagram hands back a different string, the workflow stores it as the new IG_TOKEN secret.
try {
  const r = await fetch('https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=' + encodeURIComponent(token));
  const j = await r.json();
  if (j.access_token && j.access_token !== token) writeFileSync('.ig-token-new', j.access_token);
} catch (e) { console.log('token refresh failed:', e.message); }
