const $ = id => document.getElementById(id);
let policy, email = '', name = '', acceptedTerms = false, dashboardPilot = false;
const localPreview = location.hostname === '127.0.0.1' || location.hostname === 'localhost';
const preview = localPreview ? new URLSearchParams(location.search).get('preview') : '';

for (const [value, label] of Object.entries(offeredLanguages)) {
  const o = document.createElement('option');
  o.value = value;
  o.textContent = label;
  $('language').append(o);
}
$('language').value = partnerLang;
$('language').onchange = () => {
  localStorage.setItem('partner-language', $('language').value);
  const u = new URL(location.href);
  u.searchParams.set('lang', $('language').value);
  location.assign(u);
};
function boot() {
const {
  notices, errorI18n, localDemo, emptyDemo, knownStatus, countText, ratioText,
  settlementReady, shareLink, validateEmail, validateName, validateOtp, validateCode,
  loginDisabled, createDisabled, tabs, tabFromHash, tabLabel
} = globalThis.MassoPartnerContract;
localize();
applyTabLabels();
bindTabs();

async function api(path, body) {
  let response;
  try {
    response = await fetch('/api/' + path, {
      method: body ? 'POST' : 'GET',
      headers: body ? {'Content-Type': 'application/json'} : {},
      body: body ? JSON.stringify(body) : undefined
    });
  } catch {
    throw Error('network');
  }
  let payload = {};
  try { payload = await response.json(); }
  catch { throw Error('request_failed'); }
  if (!response.ok) throw Error(payload.error || 'request_failed');
  return payload;
}
function say(text, tone) {
  const node = $('message');
  node.textContent = text;
  node.className = tone || '';
}
function el(tag, text) {
  const node = document.createElement(tag);
  node.textContent = text;
  return node;
}
function fieldError(id, input, message) {
  const node = $(id);
  if (input) input.setAttribute('aria-invalid', message ? 'true' : 'false');
  if (!node) return;
  node.hidden = !message;
  node.textContent = message || '';
}
function button(key, fn) {
  const control = el('button', tr(key));
  control.type = 'button';
  control.className = 'secondary';
  control.onclick = () => run(control, fn);
  return control;
}
async function run(control, fn) {
  control.disabled = true;
  control.setAttribute('aria-busy', 'true');
  say(notices.loading);
  try { await fn(); }
  catch (error) { say(errorText(error), 'error'); }
  finally {
    control.removeAttribute('aria-busy');
    control.disabled = control.dataset.keepDisabled === 'true';
  }
}
function errorText(error) {
  if (error.message === 'terms_required') return notices.termsRequired;
  if (error.message === 'sign_in_required') return notices.unauthorized;
  const key = errorI18n[error.message];
  return tr(key || 'failed');
}
function note(parent, className, text) {
  const node = el('p', text);
  node.className = className;
  parent.prepend(node);
  return node;
}
function showPolicy() {
  const box = $('policy');
  box.replaceChildren();
  note(box, 'notice', notices.pendingFigures);
  box.append(el('p', notices.downloadFree), el('p', tr('offer')), el('p', tr('commission')));
  if (!policy.registrationOpen) {
    const closed = el('p', tr('closed'));
    closed.className = 'closed';
    closed.id = 'policy-closed';
    box.append(closed);
  }
}
function markDemo(text) {
  const banner = $('demo-banner');
  if (!banner) return;
  banner.hidden = false;
  banner.textContent = text;
}
function gateLogin() {
  const control = $('login').querySelector('button');
  const disabled = loginDisabled(policy, new URLSearchParams(location.search).has('pilot'));
  control.disabled = disabled;
  control.dataset.keepDisabled = disabled ? 'true' : 'false';
  if (disabled) control.setAttribute('aria-describedby', 'policy-closed');
}
function gateCreate() {
  const control = $('create').querySelector('button');
  const disabled = createDisabled(policy, dashboardPilot);
  control.disabled = disabled;
  control.dataset.keepDisabled = disabled ? 'true' : 'false';
  const closed = $('create-closed');
  closed.hidden = !disabled;
  closed.textContent = disabled ? tr('closed') : '';
  if (disabled) control.setAttribute('aria-describedby', 'create-closed');
}
function applyTabLabels() {
  const nav = $('tabs');
  if (nav) nav.setAttribute('aria-label', tabLabel(partnerLang, 'nav'));
  for (const node of document.querySelectorAll('[data-tab-label]')) node.textContent = tabLabel(partnerLang, node.dataset.tabLabel);
}
function moveLanguage(privateView) {
  const select = $('language');
  const slot = privateView ? $('account-language') : $('header-tools');
  if (select && slot && select.parentElement !== slot) slot.append(select);
}
const panelScroll = {};
const panelSeen = {};
function clearPrivate() {
  $('metrics').replaceChildren();
  $('codes').replaceChildren();
  $('settlements').replaceChildren();
  $('greeting').textContent = '';
  $('account-name').textContent = '';
  $('updated').textContent = '';
  $('overview-status').hidden = true;
  $('overview-status').textContent = '';
  $('create').reset();
  for (const id of tabs) {
    delete panelScroll[id];
    delete panelSeen[id];
  }
}
function showTab(name, fromHash) {
  const tab = tabs.includes(name) ? name : 'overview';
  const current = tabs.find(id => !$('panel-' + id).hidden);
  if (current) panelScroll[current] = window.scrollY;
  for (const id of tabs) {
    const on = id === tab;
    $('panel-' + id).hidden = !on;
    const button = $('tab-' + id);
    button.setAttribute('aria-selected', on ? 'true' : 'false');
    button.tabIndex = on ? 0 : -1;
    if (on) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  }
  const y = panelSeen[tab] ? (panelScroll[tab] || 0) : 0;
  panelSeen[tab] = true;
  if (!fromHash && location.hash !== '#' + tab) location.hash = tab;
  fitTabs();
  requestAnimationFrame(() => window.scrollTo(0, y));
}
function fitTabs() {
  const bar = $('tabs');
  if (!bar) return;
  document.documentElement.style.setProperty('--tab-h', Math.ceil(bar.getBoundingClientRect().height) + 'px');
}
function onTabKey(event) {
  const current = tabs.indexOf(event.target.closest?.('[data-tab]')?.dataset.tab);
  if (current < 0) return;
  const forward = document.documentElement.dir === 'rtl' ? -1 : 1;
  let next = null;
  if (event.key === 'ArrowRight') next = (current + forward + tabs.length) % tabs.length;
  else if (event.key === 'ArrowLeft') next = (current - forward + tabs.length) % tabs.length;
  else if (event.key === 'Home') next = 0;
  else if (event.key === 'End') next = tabs.length - 1;
  else return;
  event.preventDefault();
  showTab(tabs[next], false);
  $('tab-' + tabs[next]).focus();
}
function bindTabs() {
  if (bindTabs.done) return;
  bindTabs.done = true;
  $('tabs').addEventListener('click', event => {
    const button = event.target.closest('[data-tab]');
    if (!button) return;
    showTab(button.dataset.tab, false);
    if (event.detail > 0) button.blur();
  });
  $('tabs').addEventListener('keydown', onTabKey);
  window.addEventListener('hashchange', () => {
    if ($('dashboard').hidden) return;
    const next = tabFromHash(location.hash);
    const current = tabs.find(id => !$('panel-' + id).hidden);
    if (current === next) return;
    showTab(next, true);
  });
  document.addEventListener('focusin', event => {
    if (event.target.matches('input, select, textarea')) {
      event.target.style.scrollMarginBottom = 'calc(var(--tab-h, 62px) + var(--keyboard, 0px) + 16px)';
      event.target.style.scrollMarginTop = '72px';
      event.target.scrollIntoView({block: 'nearest', inline: 'nearest'});
    }
  });
  if (window.visualViewport) {
    const fit = () => {
      const overlap = Math.max(0, window.innerHeight - visualViewport.height - visualViewport.offsetTop);
      document.documentElement.style.setProperty('--keyboard', overlap + 'px');
    };
    visualViewport.addEventListener('resize', fit);
    visualViewport.addEventListener('scroll', fit);
  }
  window.addEventListener('resize', fitTabs);
}
function showLoggedOut() {
  clearPrivate();
  $('dashboard').hidden = true;
  document.body.classList.remove('has-tabs');
  $('landing').hidden = false;
  $('logout').hidden = true;
  moveLanguage(false);
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
  gateLogin();
}

$('login').onsubmit = event => {
  event.preventDefault();
  const form = event.target;
  const data = new FormData(form);
  const emailInput = form.querySelector('[name=email]');
  const nameInput = form.querySelector('[name=name]');
  const emailProblem = validateEmail(data.get('email'));
  const nameProblem = validateName(data.get('name'));
  emailInput.setAttribute('aria-invalid', emailProblem ? 'true' : 'false');
  nameInput.setAttribute('aria-invalid', nameProblem ? 'true' : 'false');
  fieldError('login-error', null, emailProblem ? notices.emailInvalid : nameProblem ? notices.nameInvalid : '');
  if (emailProblem || nameProblem) return;
  email = String(data.get('email')).trim();
  name = String(data.get('name')).trim();
  run(event.submitter, async () => {
    form.setAttribute('aria-busy', 'true');
    try {
      await api('login', {email});
      $('verify').hidden = false;
      $('verify').querySelector('input').focus();
      say(tr('sent'), 'ok');
    } finally { form.removeAttribute('aria-busy'); }
  });
};
$('verify').onsubmit = event => {
  event.preventDefault();
  const form = event.target;
  const input = form.querySelector('[name=otp]');
  const problem = validateOtp(new FormData(form).get('otp'));
  fieldError('verify-error', input, problem ? notices.otpInvalid : '');
  if (problem) return;
  run(event.submitter, async () => {
    form.setAttribute('aria-busy', 'true');
    try {
      await api('login/verify', {email, name, otp: input.value.trim()});
      await dashboard('verify');
    } finally { form.removeAttribute('aria-busy'); }
  });
};
$('logout').onclick = event => run(event.target, async () => {
  await api('logout', {});
  location.assign('/');
});
$('refresh').onclick = event => run(event.target, () => dashboard('refresh'));
$('create').onsubmit = event => {
  event.preventDefault();
  const form = event.target;
  const input = form.querySelector('[name=code]');
  if (createDisabled(policy, dashboardPilot)) {
    say(tr('closed'), 'error');
    return;
  }
  const problem = validateCode(new FormData(form).get('code'));
  fieldError('create-error', input, problem ? notices.codeInvalid : '');
  if (problem) return;
  const accepted = !!new FormData(form).get('terms');
  if (!accepted && !acceptedTerms) {
    fieldError('create-error', form.querySelector('[name=terms]'), notices.termsRequired);
    return;
  }
  run(event.submitter, async () => {
    form.setAttribute('aria-busy', 'true');
    try {
      await api('codes', {code: input.value.trim(), acceptTerms: accepted});
      form.reset();
      await dashboard('create');
    } finally { form.removeAttribute('aria-busy'); }
  });
};

function renderDashboard(data) {
  acceptedTerms = !!data.acceptedTerms;
  dashboardPilot = !!data.pilot;
  const consent = $('create').querySelector('[name=terms]');
  consent.required = !acceptedTerms;
  consent.closest('label').hidden = acceptedTerms;
  clearPrivate();
  $('landing').hidden = true;
  $('dashboard').hidden = false;
  document.body.classList.add('has-tabs');
  $('logout').hidden = false;
  moveLanguage(true);
  const partnerName = data.partner?.name || '—';
  $('greeting').textContent = tr('welcome') + ', ' + partnerName;
  $('account-name').textContent = partnerName;
  $('updated').textContent = data.updatedAt ? tr('synced') + ' ' + new Date(data.updatedAt).toLocaleString(partnerLang) : '';
  const summary = data.summary || {};
  $('metrics').replaceChildren();
  const rows = [
    ['attributed', countText(summary.attributed, partnerLang)],
    ['trialing', countText(summary.trialing, partnerLang)],
    ['paid', countText(summary.paid, partnerLang)],
    ['monthlyTrial', countText(summary.monthlyTrialing, partnerLang)],
    ['yearlyTrial', countText(summary.yearlyTrialing, partnerLang)],
    ['monthlyPaid', countText(summary.monthlyPaid, partnerLang)],
    ['yearlyPaid', countText(summary.yearlyPaid, partnerLang)],
    ['monthlyActive', countText(summary.monthly, partnerLang)],
    ['yearlyActive', countText(summary.yearly, partnerLang)],
    ['refunded', countText(summary.refunded, partnerLang)],
    ['referralPaid', ratioText(summary.paid, (data.codes || []).reduce((sum, code) => sum + (typeof code.bound === 'number' ? code.bound : NaN), 0), partnerLang)],
    ['trialPaid', summary.trialConversion === null || summary.trialConversion === undefined ? '—' : ratioText(summary.trialConversion, 1, partnerLang)]
  ];
  for (const [label, value] of rows) {
    const card = el('div', '');
    card.className = 'metric';
    card.append(el('span', tr(label)), el('strong', value));
    $('metrics').append(card);
  }
  $('codes').replaceChildren();
  const codes = Array.isArray(data.codes) ? data.codes : [];
  if (!codes.length) $('codes').append(el('p', notices.codesEmpty));
  for (const code of codes) {
    const status = knownStatus(code.status);
    const box = el('article', '');
    box.className = 'code';
    const link = shareLink(location.origin, code.code || '');
    const heading = el('h3', code.code || '—');
    heading.dir = 'ltr';
    const address = el('p', link);
    address.dir = 'ltr';
    box.append(heading, el('p', `${tr('status')}: ${status ? tr(status) : '—'} · ${tr('visits')}: ${countText(code.visits, partnerLang)} · ${tr('bindings')}: ${countText(code.bound, partnerLang)}`), address);
    if (localPreview) box.append(el('p', notices.localLink));
    if (status === 'active') {
      const image = document.createElement('img');
      image.src = '/qr/' + encodeURIComponent(code.code || '') + '.svg';
      image.width = 180;
      image.height = 180;
      if (localPreview) {
        image.className = 'local-mark';
        image.alt = notices.notScannable + ' ' + (code.code || '');
        box.append(image, el('p', notices.notScannable));
      } else {
        image.alt = tr('code') + ' ' + (code.code || '');
        box.append(image);
      }
      box.append(
        button('copy', async () => { await navigator.clipboard.writeText(code.code || ''); say(tr('copied'), 'ok'); }),
        button('share', async () => {
          await navigator.clipboard.writeText(link);
          say(localPreview ? notices.localShare : tr('copied'), 'ok');
        }),
        button('disable', async () => {
          if (confirm(tr('disableAsk'))) {
            await api('codes/status', {code: code.code, status: 'disabled'});
            await dashboard('status');
          }
        })
      );
    }
    if (status === 'creating' || status === 'disabling') box.append(button('refresh', () => dashboard('refresh')));
    if (status === 'disabling') box.append(button('retry', async () => {
      await api('codes/status', {code: code.code, status: 'disabled'});
      await dashboard('status');
    }));
    if (status === 'disabled' || status === 'failed') box.append(button('archive', async () => {
      await api('codes/status', {code: code.code, status: 'archived'});
      await dashboard('status');
    }));
    $('codes').append(box);
  }
  $('settlements').replaceChildren(el('p', notices.pendingFigures), el('p', notices.settlementReadonly));
  const settlements = (Array.isArray(data.settlements) ? data.settlements : []).filter(settlementReady);
  if (!settlements.length) $('settlements').append(el('p', tr('empty')));
  for (const row of settlements) {
    const status = tr(row.status === 'paid' ? 'paidStatus' : row.status === 'refund adjustment' ? 'adjustment' : row.status);
    const line = el('p', `${new Date(row.created).toLocaleDateString(partnerLang)} · ${new Intl.NumberFormat(partnerLang, {style: 'currency', currency: row.currency}).format(row.commission_minor / 100)} · ${status}`);
    line.className = 'statement';
    $('settlements').append(line);
  }
  const status = $('overview-status');
  status.hidden = !createDisabled(policy, dashboardPilot);
  status.textContent = status.hidden ? '' : tr('closed');
  gateCreate();
  const tab = tabFromHash(location.hash);
  showTab(tab, true);
  if (location.hash !== '#' + tab) history.replaceState(null, '', location.pathname + location.search + '#' + tab);
}

async function dashboard(source) {
  if (preview === 'dashboard' || preview === 'empty') {
    markDemo(notices.localDemo);
    renderDashboard(preview === 'empty' ? emptyDemo : localDemo);
    say('');
    return;
  }
  try {
    renderDashboard(await api('dashboard'));
    say('');
  } catch (error) {
    if (error.message === 'sign_in_required') {
      showLoggedOut();
      if (source === 'refresh') say(notices.unauthorized, 'error');
      return;
    }
    throw error;
  }
}

async function start() {
  try {
    policy = await api('policy');
    showPolicy();
    gateLogin();
    if (location.pathname.startsWith('/r/')) {
      const code = decodeURIComponent(location.pathname.slice(3).replace(/\/$/, ''));
      $('landing').hidden = true;
      $('referral').hidden = false;
      $('public-code').textContent = code;
      note($('referral'), 'notice', notices.pendingFigures);
      $('referral').append(el('p', notices.downloadFree));
      if (localPreview) markDemo(notices.localLink);
      $('copy-public').onclick = event => run(event.target, async () => {
        await navigator.clipboard.writeText(code);
        say(tr('copied'), 'ok');
      });
      return;
    }
    if (preview === 'verify') {
      $('verify').hidden = false;
      const otp = $('verify').querySelector('input');
      otp.focus();
      otp.scrollIntoView({block: 'center'});
      markDemo(notices.verifyDemo);
      say(tr('sent'), 'ok');
      return;
    }
    if (preview === 'error') {
      say(tr('failed'), 'error');
      return;
    }
    if (preview === 'unauthorized') {
      say(notices.unauthorized, 'error');
      return;
    }
    if (preview === 'loading') {
      $('login').setAttribute('aria-busy', 'true');
      say(notices.loading);
      return;
    }
    if (preview === 'dashboard' || preview === 'empty') {
      await dashboard(preview);
      return;
    }
    await dashboard('start');
  } catch (error) {
    say(errorText(error), 'error');
  }
}
start();
}
if (globalThis.MassoPartnerContract) boot();
else document.addEventListener('partner-contract', boot, {once: true});
