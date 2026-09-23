(() => {
  const check = (value, name) => { if (!value) throw Error(name); };
  const byId = id => document.getElementById(id);
  const select = ids => {
    for (const input of byId('dashboard-section-options').querySelectorAll('input')) {
      input.checked = ids.includes(input.value); input.dispatchEvent(new Event('change'));
    }
  };
  try {
    byId('focus-reset').click();
    byId('dashboard-sections-button').click();
    check(byId('dashboard-sections-dialog').open, 'Section chooser opens');
    select(['mail', 'schedule']);
    check(document.querySelector('.hero').classList.contains('dashboard-section-hidden'), 'Welcome hidden');
    check(!document.querySelector('.bento-mail').classList.contains('dashboard-section-hidden'), 'Mail remains visible');
    check(JSON.parse(localStorage.getItem('today-dashboard-sections')).length === 2, 'Choices persisted');
    window.refreshLocalDashboard();
    check(document.querySelector('.hero').classList.contains('dashboard-section-hidden'), 'Refresh retains choice');
    byId('focus-hours').value=0; byId('focus-minutes').value=20;
    byId('focus-form').dispatchEvent(new Event('submit', {cancelable:true}));
    check(!byId('focus-timer').classList.contains('dashboard-section-hidden'), 'Active timer stays accessible');
    check(document.querySelector('.hero').classList.contains('dashboard-section-hidden'), 'Focus respects global choice');
    byId('focus-reset').click();
    check(byId('focus-timer').classList.contains('dashboard-section-hidden'), 'Reset restores hidden timer preference');
    select([]);
    check(!byId('dashboard-sections-empty').hidden, 'Empty dashboard offers recovery');
    byId('dashboard-show-all').click();
    check(document.querySelectorAll('.dashboard-section-hidden').length === 0, 'Show all restores cards');
    check(byId('dashboard-sections-empty').hidden, 'Empty state dismissed');
    select(['welcome','now','schedule','mail','timer','plan','verse','links']);
    const rect = selector => document.querySelector(selector).getBoundingClientRect();
    const mail = rect('.bento-mail'), schedule = rect('.bento-schedule'), links = rect('.quicklinks');
    check(mail.height > schedule.height, 'Mail gets a tall column');
    check(schedule.width > mail.width, 'Schedule gets a wide panel');
    check(links.width > schedule.width && links.height < 65, 'Quick links stay a compact full-width strip');
    const cards = [...document.querySelectorAll('.page .glass-card')].filter(card => !card.hidden && !card.classList.contains('dashboard-section-hidden'));
    for (let i = 0; i < cards.length; i++) for (let j = i + 1; j < cards.length; j++) {
      const a = cards[i].getBoundingClientRect(), b = cards[j].getBoundingClientRect();
      check(!(a.left < b.right - 1 && a.right > b.left + 1 && a.top < b.bottom - 1 && a.bottom > b.top + 1), 'Cards do not overlap');
    }
    byId('dashboard-sections-done').click();
    check(!byId('dashboard-sections-dialog').open, 'Done closes chooser');
    check(document.documentElement.scrollWidth <= innerWidth, 'No horizontal overflow');
    return 'PASS: section selection, persistence, refresh, focus interaction, recovery and adaptive card sizes';
  } finally { localStorage.removeItem('today-dashboard-sections'); localStorage.removeItem('today-focus-timer'); }
})();
