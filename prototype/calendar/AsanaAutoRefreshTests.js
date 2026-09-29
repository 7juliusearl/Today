(async () => {
 const assert=(ok,message)=>{if(!ok)throw Error(message);};
 const tick=()=>new Promise(r=>setTimeout(r,40));
 let poll, cleared=false, requests=[], release, delay=false;
 const nativeInterval=window.setInterval, nativeClear=window.clearInterval;
 window.setInterval=(fn,ms)=>{if(ms===30000){poll=fn;return 987654;}return nativeInterval(fn,ms);};
 window.clearInterval=id=>{if(id===987654)cleared=true;else nativeClear(id);};
 Object.defineProperty(window,'webkit',{configurable:true,value:{messageHandlers:{asanaComments:{postMessage:async request=>{
 requests.push(request);
 if(delay) await new Promise(r=>release=r);
 return {comments:[{id:request.offset?'new':'old',author:'Teammate',text:request.offset?'New reply':'Original',createdAt:'2026-09-29T12:00:00Z'}],next:request.offset?'':'page2'};
 }}}}});
 showAsanaBrief({title:'Auto refresh test',url:'https://app.asana.com/0/1/2',brief:{description:'Details '.repeat(300)}});
 await tick();
 const dialog=document.getElementById('asana-brief-dialog'), input=dialog.querySelector('textarea'), content=dialog.querySelector('.asana-brief-content');
 input.value='Keep my reply';input.dispatchEvent(new Event('input'));
 content.scrollTop=150; const top=content.scrollTop;
 await poll();
 assert(requests.at(-1).offset==='page2','Automatic refresh reaches newest page');
 assert(dialog.textContent.includes('New reply'),'New comments appear automatically');
 assert(input.value==='Keep my reply'&&!input.disabled,'Draft remains editable');
 assert(content.scrollTop===top,'Scroll position preserved');
 const count=dialog.querySelectorAll('article').length;await poll();
 assert(dialog.querySelectorAll('article').length===count,'No duplicate comments');
 delay=true;const pending=poll();await tick();
 assert(!input.disabled,'Background request never disables composer');
 dialog.close();await tick(); release();await pending;
 assert(cleared,'Closing stops polling');
 const n=requests.length;await poll();assert(requests.length===n,'No requests after close');
 window.setInterval=nativeInterval;window.clearInterval=nativeClear;
 return 'PASS: automatic pagination, new replies, draft and scroll preservation, deduplication, editable composer, close cleanup.';
})()
