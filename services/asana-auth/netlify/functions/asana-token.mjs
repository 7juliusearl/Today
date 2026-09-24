// This service exchanges credentials only. Task content never passes through it.
const headers = {'Content-Type':'application/json', 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff'};
const reply = (status, body) => new Response(JSON.stringify(body), {status, headers});
export default async function handler(request) {
  if (request.method !== 'POST') return reply(405, {error:'Use POST.'});
  if (!request.headers.get('content-type')?.startsWith('application/json')) return reply(415, {error:'Use JSON.'});
  if (Number(request.headers.get('content-length') || 0) > 16384) return reply(413, {error:'Request too large.'});
  let input;
  try {
    // Bound reads even when Content-Length is absent or incorrect.
    const reader = request.body?.getReader(); if (!reader) return reply(400, {error:'Missing request.'});
    let size = 0; const chunks = [];
    while (true) { const {done,value} = await reader.read(); if(done) break; size += value.length;
      if (size > 16384) { await reader.cancel(); return reply(413, {error:'Request too large.'}); } chunks.push(value); }
    input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch { return reply(400, {error:'Invalid request.'}); }
  const client = process.env.ASANA_CLIENT_ID, secret = process.env.ASANA_CLIENT_SECRET;
  const redirect = process.env.ASANA_REDIRECT_URI;
  if (!client || !secret || !redirect?.startsWith('https://')) return reply(503, {error:'Sign-in is not configured yet.'});
  const form = new URLSearchParams({client_id:client, client_secret:secret});
  if (input?.grant_type === 'authorization_code' && typeof input.code === 'string' && input.code.length > 0 && input.code.length <= 4096 && typeof input.code_verifier === 'string' && /^[A-Za-z0-9._~-]{43,128}$/.test(input.code_verifier)) {
    form.set('grant_type','authorization_code'); form.set('code',input.code);
    form.set('code_verifier',input.code_verifier); form.set('redirect_uri',redirect);
  } else if (input?.grant_type === 'refresh_token' && typeof input.refresh_token === 'string' && input.refresh_token.length > 0 && input.refresh_token.length <= 8192) {
    form.set('grant_type','refresh_token'); form.set('refresh_token',input.refresh_token);
  } else { return reply(400, {error:'Invalid authorization request.'}); }
  try {
    const result = await fetch('https://app.asana.com/-/oauth_token', {
      method:'POST', redirect:'error', signal:AbortSignal.timeout(20000),
      headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:form
    });
    if (!result.ok) return reply(result.status === 429 ? 429 : 401, {error:'Asana sign-in could not be renewed. Please reconnect.'});
    const token = await result.json();
    if (typeof token.access_token !== 'string') return reply(502,{error:'Asana returned an invalid response.'});
    // Explicit allowlist: never echo upstream errors, client secrets or arbitrary fields.
    return reply(200,{access_token:token.access_token,refresh_token:token.refresh_token,expires_in:token.expires_in});
  } catch { return reply(502,{error:'Asana is unavailable. Please try again.'}); }
}
