(async () => {
 const link=document.createElement('link');link.rel='stylesheet';link.href='overview.css';
 await new Promise((resolve,reject)=>{link.onload=resolve;link.onerror=reject;document.head.append(link);});
 const assert=(ok,message)=>{if(!ok)throw Error(message);};
 const now=new Date(), time=m=>new Date(now.getTime()+m*60000).toISOString();
 const upcoming=[{id:'a',title:'Nearest',start:time(13),end:time(18)},{id:'b',title:'Later',start:time(18),end:time(78)}];
 const size=el=>parseFloat(getComputedStyle(el.querySelector('.now-countdown-number')).fontSize);
 for(const focus of [false,true]){
 document.body.classList.toggle('focus-mode',focus);
 DATA.calendar={events:upcoming};renderHappeningNow(now);
 let rows=document.querySelectorAll('.now-event');
 assert(size(rows[0])>size(rows[1]),'Nearest upcoming is larger when idle');
 assert(document.querySelectorAll('.now-event-featured').length===1,'Only nearest upcoming is promoted');
 DATA.calendar.events=[{id:'c',title:'Current',start:time(-30),end:time(5)},...upcoming];renderHappeningNow(now);
 rows=document.querySelectorAll('.now-event');
 assert(size(rows[0])>size(rows[1])&&size(rows[1])===30,'Active event takes priority; upcoming stays small');
 renderHappeningNow(new Date(now.getTime()+6*60000));
 assert(document.querySelector('.now-event-featured h3').textContent==='Nearest','Promote next when current ends');
 renderHappeningNow(new Date(now.getTime()+13*60000));
 assert(!document.querySelector('.now-event-featured')&&document.querySelector('.now-event-current'),'Upcoming becomes current at start time');
 }
 return 'PASS: idle, active, focus, event-end and event-start countdown priority.';
})()
