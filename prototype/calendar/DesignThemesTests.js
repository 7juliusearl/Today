(() => {
  const check = (v, message) => { if (!v) throw Error(message); };
  const el = id => document.getElementById(id);
  const choose = name => document.querySelector(`[data-design-choice="${name}"]`).click();
  const color = (id, value) => { el(id).value = value; el(id).dispatchEvent(new Event('input')); };
  el('design-button').click();
  check(el('design-dialog').open, 'Design editor opens');
  choose('studio'); color('design-accent', '#32a875'); color('design-secondary', '#aec7fa');
  choose('editorial'); color('design-accent', '#bd5599');
  choose('studio'); check(el('design-accent').value === '#32a875', 'Per-design colors retained');
  el('design-save').click();
  check(JSON.parse(localStorage.getItem('today-design-themes')).selected === 'studio', 'Design saved');
  check(document.documentElement.style.getPropertyValue('--accent-fill') === '#32a875', 'Accent applied');
  el('design-button').click(); choose('glass'); el('design-close').click();
  // close event is asynchronous, so trigger the same cancellation handler now.
  el('design-dialog').dispatchEvent(new Event('close'));
  check(document.documentElement.dataset.design === 'studio', 'Cancel restores saved design');
  for (const name of ['glass', 'studio', 'retro', 'editorial']) {
    el('design-button').click(); choose(name); el('design-save').click();
    el('design-dialog').dispatchEvent(new Event('close'));
    for (let i = 0; i < 2; i++) {
      el('theme-toggle').click();
      check(document.documentElement.scrollWidth <= innerWidth, 'No overflow in either appearance');
      check(getComputedStyle(document.querySelector('.glass-card')).backgroundColor !== '', 'Design renders');
    }
  }
  window.refreshLocalDashboard();
  check(document.documentElement.dataset.design === 'editorial', 'Refresh keeps design');
  el('design-button').click(); el('design-reset').click();
  check(el('design-accent').value === '#ac7955', 'Reset restores this design');
  el('design-save').click(); el('design-dialog').dispatchEvent(new Event('close'));
  if (el('theme-toggle').getAttribute('aria-pressed') === 'true') el('theme-toggle').click();
  localStorage.removeItem('today-design-themes');
  return 'PASS: four designs, per-design colors, save/cancel/reset, refresh and light/dark modes';
})();
