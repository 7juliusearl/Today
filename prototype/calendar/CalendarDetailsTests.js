(async () => {
 const assert = (ok, message) => { if (!ok) throw new Error(message); };
 const host = document.createElement('div'); document.body.append(host);
 const ev = {id:'guests-test" data-injected="true',title:'Team meeting',start:new Date().toISOString(),end:new Date().toISOString(),attendeeCount:20,
 attendees:Array.from({length:20},(_,i)=>({name:`Guest ${i}`,email:`guest${i}@example.com`,responseStatus:'accepted'})),
 description:'<script>bad()</script>\n'+ 'Long notes '.repeat(100)+' https://example.com/file.pdf',htmlLink:'javascript:alert(1)'};
 host.innerHTML = renderEventItem(ev,false);
 assert(host.querySelectorAll('.attendee').length === 20,'Keep every guest');
 const more = host.querySelector('.attendee-overflow');
 assert(!more.open && more.querySelector('summary').textContent.includes('+14 more'),'Collapsed guest disclosure');
 more.querySelector('summary').click();
 assert(more.open,'Click expands full guest list');
 more.querySelector('summary').click(); assert(!more.open,'Click collapses guests');
 assert(host.querySelector('.event-description').textContent.includes('Long notes '.repeat(100)),'Full notes');
 assert(!host.querySelector('script'),'Notes cannot inject markup');
 assert(!host.querySelector('[data-injected]'),'Attribute values cannot inject markup');
 assert(host.querySelector('.event-description a').href === 'https://example.com/file.pdf','File links clickable');
 assert(!host.querySelector('[href^="javascript:"]'),'Unsafe event URL rejected');
 assert(host.querySelector('.attendee-response').textContent === 'Accepted','Guest RSVP visible');
 assert(host.querySelector('.attendee-email').textContent === 'guest0@example.com','Guest email visible');
 host.remove(); return 'Passed calendar details: 20 guests, expansion, full notes, safe links, RSVP and emails.';
})()
