import test from 'node:test';
import assert from 'node:assert/strict';
import token from './netlify/functions/asana-token.mjs';
import callback from './netlify/functions/asana-callback.mjs';
test('token endpoint rejects invalid input',async()=>{
  assert.equal((await token(new Request('https://example.com'))).status,405);
  assert.equal((await token(new Request('https://example.com',{method:'POST',body:'hello'}))).status,415);
});
test('token exchange fixes destination and never returns the app secret',async()=>{
  process.env.ASANA_CLIENT_ID='test'; process.env.ASANA_CLIENT_SECRET='private'; process.env.ASANA_REDIRECT_URI='https://example.com/callback';
  const original=globalThis.fetch;
  globalThis.fetch=async(url,options)=>{
    assert.equal(url,'https://app.asana.com/-/oauth_token');
    assert.equal(options.redirect,'error');
    assert.equal(options.body.get('redirect_uri'),'https://example.com/callback');
    return Response.json({access_token:'access',refresh_token:'refresh',client_secret:'private'});
  };
  try {
    const response=await token(new Request('https://example.com',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({grant_type:'authorization_code',code:'code',code_verifier:'a'.repeat(43),redirect_uri:'https://evil.example'})}));
    assert.equal(response.status,200); assert.equal(response.headers.get('cache-control'),'no-store');
    assert.deepEqual(await response.json(),{access_token:'access',refresh_token:'refresh'});
  } finally { globalThis.fetch=original; }
});
test('callback only redirects to Today and preserves state for native validation',async()=>{
  const state='a'.repeat(43);
  const response=await callback(new Request('https://example.com?code=test&state='+state+'&redirect_uri=https://evil.example'));
  const url=new URL(response.headers.get('location'));
  assert.equal(url.protocol,'today-asana:');assert.equal(url.hostname,'oauth');assert.equal(url.searchParams.get('state'),state);
  assert.equal((await callback(new Request('https://example.com?code=test'))).status,400);
});
