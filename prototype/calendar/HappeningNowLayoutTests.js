(async () => {
 const link=document.createElement('link');link.rel='stylesheet';link.href='overview.css';
 await new Promise((resolve,reject)=>{link.onload=resolve;link.onerror=reject;document.head.append(link);});
 const assert=(ok,message)=>{if(!ok)throw Error(message);};
 const now=new Date(), time=m=>new Date(now.getTime()+m*60000).toISOString();
 const active={id:'active',title:'Current meeting',start:time(-15),end:time(45)};
 const next=Array.from({length:4},(_,i)=>({id:'next'+i,title:'Upcoming meeting with a long title '+i,start:time(50+i),end:time(90+i)}));
 document.body.classList.remove('focus-mode');
 for(const filtered of [false,true]){
 document.body.classList.toggle('dashboard-filtered',filtered);
 const panel=document.querySelector('.happening-now'), hero=document.querySelector('.hero');
 const arrange=()=>{if(filtered)arrangeDashboardSections([['welcome',hero],['now',panel],['schedule',document.querySelector('.bento-schedule')]]);};
 DATA.calendar={events:[active]};renderHappeningNow(now);arrange();
 const initial=panel.getBoundingClientRect().height;
 DATA.calendar.events=[active,...next];renderHappeningNow(now);arrange();
 let bounds=panel.getBoundingClientRect();
 assert(bounds.height>initial,'Event card grows with additional events');
 assert(Math.abs(bounds.height-hero.getBoundingClientRect().height)<2,'Welcome grows to match');
 for(const el of panel.querySelectorAll('.now-countdown')){
 const box=el.getBoundingClientRect();assert(box.bottom<=bounds.bottom&&box.top>=bounds.top,'Every countdown stays inside the card');
 }
 assert(panel.scrollHeight<=panel.clientHeight+2,'No internal clipping or scroll required');
 DATA.calendar.events=[active];renderHappeningNow(now);arrange();
 assert(panel.getBoundingClientRect().height<bounds.height,'Row shrinks when events leave');
 }
 return 'PASS: event row grows and shrinks, Welcome matches, all countdowns fit in standard and selected-section layouts.';
})()
