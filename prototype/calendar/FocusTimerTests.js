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
    start(1, 10);
    assert(saved().total === 4200000, 'HH:MM duration');
    assert(document.body.classList.contains('focus-mode'), 'Active layout');
    now += 600000; tick();
    assert(byId('focus-digits').textContent === '1:00:00', 'Elapsed wall time');
    byId('focus-pause').click();
    assert(saved().remaining === 3600000, 'Paused remaining');
    now += 900000; tick();
    assert(byId('focus-digits').textContent === '1:00:00', 'Pause freezes timer');
    byId('focus-pause').click();
    const deadline = saved().deadline;
    window.refreshLocalDashboard();
    assert(saved().deadline === deadline, 'Refresh must preserve session');
    assert(saved().mode === 'running', 'Resume persists state');
    now += 3600001; tick();
    assert(saved().mode === 'done', 'Sleep beyond deadline completes');
    assert(!document.body.classList.contains('focus-mode'), 'Completion restores layout');
    assert(byId('focus-progress').getAttribute('aria-valuenow') === '100', 'Progress complete');
    byId('focus-reset').click();
    assert(!byId('focus-form').hidden && byId('focus-session').hidden, 'Reset shows duration input');
    byId('hero-week-link').click();
    assert(byId('rhythm-week-dialog').open && byId('workschedule-full-body').children.length > 0, 'Weekly rhythm still available');
    byId('rhythm-week-close').click();
    Date.now = realNow;
    start(0, 45);
    const card = byId('focus-timer').getBoundingClientRect();
    return JSON.stringify({pass:true, timerWidth:card.width,timerHeight:card.height,overflow:document.documentElement.scrollWidth>innerWidth});
  } finally { Date.now = realNow; localStorage.removeItem('today-focus-timer'); }
})();
