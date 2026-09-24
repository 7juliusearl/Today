(() => {
  const check = (condition, label) => { if (!condition) throw Error(label); };
  const scope = 'sticky-test-' + Date.now();
  const old = DATA.mail;
  const dismissed = localStorage.getItem('dashboard-dismissed-notes');
  const item = {id:'note1', messageID:'note1@test', sender:'Alex <alex@example.test>', subject:'sticky note', stickyBody:'You’ve got this! <img src=x onerror=alert(1)>', receivedAt:new Date().toISOString(), isRead:false, attachmentCount:0};
  DATA.mail = {stickyNotesEnabled:true, stickyScope:scope, items:[item], label:'Test', updatedAt:new Date().toISOString()};
  renderMail(); renderStickyNotes();
  check(document.querySelectorAll('.sticky-note').length === 1, 'Render email as note');
  check(getComputedStyle(document.getElementById('sticky-notes')).display !== 'none' && document.querySelector('.sticky-note').getBoundingClientRect().width > 0, 'Note must actually be visible in the packaged app');
  check(!document.querySelector('.sticky-note img'), 'Body must be plain text');
  check(!document.querySelector('#mail-list .mail-item'), 'Exclude notes from mail');
  check(document.querySelector('#mail-list').textContent.includes('0 messages today'), 'Exclude notes from count');
  renderStickyNotes();
  check(document.querySelectorAll('.sticky-note').length === 1, 'Refresh does not duplicate');
  DATA.mail.items = []; renderStickyNotes();
  check(document.querySelectorAll('.sticky-note').length === 1, 'Keep received note after date rollover');
  DATA.mail.items = [item]; DATA.mail.stickyNotesEnabled = false; renderMail(); renderStickyNotes();
  check(!document.querySelector('.sticky-note') && document.querySelector('#mail-list .mail-item'), 'Disable restores mail');
  DATA.mail.stickyNotesEnabled = true; renderStickyNotes();
  document.querySelector('.sticky-note-dismiss').click(); renderStickyNotes();
  check(!document.querySelector('.sticky-note'), 'Dismissal survives refresh');
  localStorage.removeItem('today-email-notes:' + scope);
  if (dismissed === null) localStorage.removeItem('dashboard-dismissed-notes'); else localStorage.setItem('dashboard-dismissed-notes', dismissed);
  DATA.mail = old; renderMail(); renderStickyNotes();
  return 'PASS sticky email rendering, plain-text safety, filtering/counts, deduplication, persistence, toggle and dismissal';
})()
