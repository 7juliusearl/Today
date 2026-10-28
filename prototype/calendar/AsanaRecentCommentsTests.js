(async () => {
  const assert = (ok, message) => { if (!ok) throw Error(message); };
  const requests = [];
  const comment = n => ({id:String(n),author:'Coworker',text:'Comment '+n,createdAt:`2026-10-28T09:${String(n).padStart(2,'0')}:00Z`});
  Object.defineProperty(window,'webkit',{configurable:true,value:{messageHandlers:{asanaComments:{postMessage:async request => {
    requests.push(request);
    return request.offset ? {comments:[5,6,7,8,9,10].map(comment),next:''} : {comments:[1,2,3,4].map(comment),next:'older-first-page2'};
  }}}}});
  showAsanaBrief({title:'Recent comments',url:'https://app.asana.com/0/0/1',brief:{description:'Test'}});
  await new Promise(resolve => setTimeout(resolve,60));
  const dialog=document.getElementById('asana-brief-dialog');
  const visible=()=>[...dialog.querySelectorAll('article')].filter(el=>!el.hidden).map(el=>el.querySelector('p').textContent);
  assert(requests.length===2,'Read through final API page to find latest comments');
  assert(visible().join(',')==='Comment 7,Comment 8,Comment 9,Comment 10','Only newest four shown initially');
  const more=dialog.querySelector('.asana-previous-comments');more.click();
  assert(visible().length===8 && !more.hidden,'Reveal four older comments');more.click();
  assert(visible().length===10 && more.hidden,'All earlier comments reachable without duplicate requests');
  dialog.close();
  return 'PASS: newest four across API pages, previous comments four at a time.';
})();
