// Run with a mock native message bridge and sample dashboard data in WKWebView.
(() => {
  const check = (value, message) => { if (!value) throw Error(message); };
  check(document.querySelectorAll('.native-control').length === 3, 'Native buttons inserted');
  const buttons = [...document.querySelector('.top-controls').querySelectorAll('button')].map(x => x.id);
  check(buttons.indexOf('native-pin') > buttons.indexOf('refresh-btn') && buttons.indexOf('native-settings') < buttons.indexOf('theme-toggle'), 'Controls beside Refresh');
  document.getElementById('native-pin').click();
  document.getElementById('native-options').click();
  document.getElementById('native-settings').click();
  check(['pin','options','settings'].every(value => window.nativeMessages.includes(value)), 'Native actions dispatched');
  window.todayNativeState({pinned:true, updateAvailable:true, spaceWarning:true});
  check(document.getElementById('native-pin').getAttribute('aria-pressed') === 'true', 'Native pin state reflected');
  check(document.querySelectorAll('.native-attention').length === 2, 'Update and permission badges');
  const toggle = document.getElementById('theme-toggle');
  toggle.click();
  check(window.nativeMessages.at(-1) === document.documentElement.dataset.theme, 'Appearance sent to native app');
  toggle.click();
  check(window.nativeMessages.at(-1) === document.documentElement.dataset.theme, 'Both appearances synchronized');
  window.todayNativeState({pinned:false, updateAvailable:false, spaceWarning:false});
  check(document.getElementById('native-pin').getAttribute('aria-pressed') === 'false', 'Pin disabled state');
  check(document.querySelectorAll('.native-attention').length === 0, 'Badges clear');
  return 'PASS: native controls, actions, state and both theme messages';
})();
