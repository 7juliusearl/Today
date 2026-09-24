export default async function handler(request) {
  const incoming = new URL(request.url);
  const state = incoming.searchParams.get('state');
  const code = incoming.searchParams.get('code');
  if (request.method !== 'GET' || !state || !/^[A-Za-z0-9_-]{32,128}$/.test(state) || !code || code.length > 4096 || incoming.searchParams.has('error')) {
    return new Response('Sign-in was cancelled or could not finish. Return to Today and try again.', {status:400,headers:{'Content-Type':'text/plain','Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
  }
  // The native app checks state and supplies its private PKCE verifier during exchange.
  const callback = new URL('today-asana://oauth');
  callback.searchParams.set('code',code); callback.searchParams.set('state',state);
  return new Response(null,{status:302,headers:{Location:callback.href,'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
}
