// Run in the dashboard's WKWebView with sample data (no real calendars or mail).
(() => {
  const assert = (condition, message) => { if (!condition) throw new Error(message); };
  const byId = id => document.getElementById(id);
  const realNow = Date.now;
  let now = realNow();
  Date.now = () => now;
  const tick = () => document.dispatchEvent(new Event('visibilitychange'));
  const saved = () => JSON.parse(localStorage.getItem('today-focus-timer'));
  const start = (h, m) => {
    byId('focus-hours').value = h; byId('focus-minutes').value = m;
    byId('focus-form').dispatchEvent(new Event('submit', { cancelable: true }));
  };
  try {
    byId('focus-reset').click();
    start(0, 0);
    assert(!document.body.classList.contains('focus-mode'), 'Zero duration must not start');
    byId('focus-settings').click();
    assert(byId('focus-settings-dialog').open, 'Settings dialog opens');
    for (const input of byId('focus-section-options').querySelectorAll('input')) {
      input.checked = ['mail', 'schedule'].includes(input.value);
      input.dispatchEvent(new Event('change'));
    }
    assert(!document.querySelector('.hero').classList.contains('focus-section-hidden'), 'Idle ignores filters');
    byId('focus-settings-done').click();
    start(1, 10);
    assert(document.querySelector('.hero').classList.contains('focus-section-hidden'), 'Welcome hidden during focus');
    assert(!document.querySelector('.bento-mail').classList.contains('focus-section-hidden'), 'Selected mail visible');
    assert(JSON.parse(localStorage.getItem('today-focus-sections')).length === 2, 'Selection saved');
    assert(saved().total === 4200000, 'HH:MM duration');
    assert(document.body.classList.contains('focus-mode'), 'Active layout');
    now += 600000; tick();
    assert(byId('focus-digits').textContent === '1:00:00', 'Elapsed wall time');
    byId('focus-pause').click();
    assert(saved().remaining === 3600000, 'Paused remaining');
    assert(document.body.classList.contains('focus-filtered'), 'Pause retains selected layout');
    now += 900000; tick();
    assert(byId('focus-digits').textContent === '1:00:00', 'Pause freezes timer');
    byId('focus-pause').click();
    const deadline = saved().deadline;
    window.refreshLocalDashboard();
    assert(saved().deadline === deadline, 'Refresh must preserve session');
    assert(document.querySelector('.hero').classList.contains('focus-section-hidden'), 'Refresh preserves filters');
    assert(saved().mode === 'running', 'Resume persists state');
    now += 3600001; tick();
    assert(saved().mode === 'done', 'Sleep beyond deadline completes');
    assert(!document.body.classList.contains('focus-mode'), 'Completion restores layout');
    assert(!document.querySelector('.hero').classList.contains('focus-section-hidden'), 'Completion restores all sections');
    assert(byId('focus-progress').getAttribute('aria-valuenow') === '100', 'Progress complete');
    byId('focus-reset').click();
    assert(!byId('focus-form').hidden && byId('focus-session').hidden, 'Reset shows duration input');
    byId('hero-week-link').click();
    assert(byId('rhythm-week-dialog').open && byId('workschedule-full-body').children.length > 0, 'Weekly rhythm still available');
    byId('rhythm-week-close').click();
    Date.now = realNow;
    start(0, 45);
    for (const input of byId('focus-section-options').querySelectorAll('input')) {
      input.checked = false; input.dispatchEvent(new Event('change'));
    }
    assert(document.body.classList.contains('focus-timer-only'), 'Timer-only view');
    assert(getComputedStyle(byId('focus-timer')).display !== 'none', 'Timer stays visible');
    byId('focus-show-all').click();
    assert(!document.querySelector('.hero').classList.contains('focus-section-hidden'), 'Show all restores sections');
    for (const input of byId('focus-section-options').querySelectorAll('input')) {
      input.checked = ['mail', 'schedule'].includes(input.value); input.dispatchEvent(new Event('change'));
    }
    assert(document.body.classList.contains('focus-mail-column'), 'Tall mail enabled by default');
    byId('focus-tall-mail').checked = false;
    byId('focus-tall-mail').dispatchEvent(new Event('change'));
    assert(!document.body.classList.contains('focus-mail-column'), 'Tall mail can be disabled');
    byId('focus-tall-mail').checked = true;
    byId('focus-tall-mail').dispatchEvent(new Event('change'));
    const mail = document.querySelector('.bento-mail').getBoundingClientRect();
    const card = byId('focus-timer').getBoundingClientRect();
    if (innerWidth >= 1000 && innerHeight >= 650) assert(mail.height > card.height && mail.left >= card.right, 'Mail spans full height on right');
    return JSON.stringify({pass:true, timerWidth:card.width,timerHeight:card.height,overflow:document.documentElement.scrollWidth>innerWidth});
  } finally { Date.now = realNow; localStorage.removeItem('today-focus-timer'); localStorage.removeItem('today-focus-sections'); localStorage.removeItem('today-focus-tall-mail'); }
})();
