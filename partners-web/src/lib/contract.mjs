// Relative API already used by the public partner page.
// This module does not add routes, secrets, or live figures.

export const routes = [
  {id: 'policy', method: 'GET', path: '/api/policy'},
  {id: 'login', method: 'POST', path: '/api/login', body: ['email']},
  {id: 'verify', method: 'POST', path: '/api/login/verify', body: ['email', 'name', 'otp']},
  {id: 'logout', method: 'POST', path: '/api/logout'},
  {id: 'dashboard', method: 'GET', path: '/api/dashboard'},
  {id: 'codes', method: 'POST', path: '/api/codes', body: ['code', 'acceptTerms']},
  {id: 'codeStatus', method: 'POST', path: '/api/codes/status', body: ['code', 'status']},
  {id: 'qr', method: 'GET', path: '/qr/{code}.svg'}
];

export const summaryFields = [
  'attributed', 'trialing', 'paid', 'monthlyTrialing', 'yearlyTrialing',
  'monthlyPaid', 'yearlyPaid', 'monthly', 'yearly', 'refunded', 'trialConversion'
];

export const codeFields = ['code', 'status', 'visits', 'bound'];
export const settlementFields = ['created', 'commission_minor', 'currency', 'status'];
export const codeStatuses = ['active', 'creating', 'disabling', 'disabled', 'failed', 'archived'];

export const errorI18n = {
  registration_not_ready: 'closed',
  campaign_not_ready: 'closed',
  code_taken_or_limit: 'codeConflict',
  invalid_or_expired_code: 'otpInvalid',
  rate_limited: 'rateLimited',
  network: 'failed',
  request_failed: 'failed'
};

export const notices = {
  pendingFigures: 'Pending confirmation: the price and 20% first-payment sentences already on this page are not an approved commercial term.',
  downloadFree: 'The Masso app download is free. Any discount, once confirmed, applies to an eligible Pro subscription, not to downloading the app.',
  localDemo: 'Local mock. Not a live partner account. No code was created and nothing was sent. These figures are not Apple-reconciled revenue and not a payable statement.',
  localLink: 'Local preview link only. Not a public share link and not a scannable code.',
  notScannable: 'Not a scannable code.',
  unauthorized: 'Sign-in required.',
  loading: 'Loading.',
  codesEmpty: 'No codes on this account.',
  settlementReadonly: 'Statements are read-only. This page cannot confirm or send a payout.',
  termsRequired: 'Accept the program terms before creating a code.',
  emailInvalid: 'Enter a valid email address.',
  nameInvalid: 'Enter a creator name.',
  otpInvalid: 'Enter the six-digit code.',
  codeInvalid: 'Use 4–20 letters and digits, starting with a letter.',
  localShare: 'Copied a local preview link. It is not a public share link.',
  verifyDemo: 'Local demonstration of the sign-in step. No email was sent.'
};

// Fields the influencer loop needs and this relative API does not return.
export const gaps = [
  {id: 'instagram-invite', step: 'Instagram invite', missing: 'No invite channel, Instagram account, or inviter in the client payload.'},
  {id: 'registration-vs-login', step: 'Email registration and login', missing: 'POST /api/login and POST /api/login/verify do not say whether the email is new.'},
  {id: 'otp-email', step: 'Email registration and login', missing: 'The page is not given delivery, expiry, or provider result for the email code.'},
  {id: 'session', step: 'Email registration and login', missing: 'The public client has no session body. This preview returns sign_in_required and does not invent a cookie.'},
  {id: 'code-create', step: 'Exclusive code', missing: 'POST /api/codes is refused here. A real code waits for the backend.'},
  {id: 'apple-redeem', step: 'Fan Apple redemption', missing: 'No redemption event, transaction id, product, or StoreKit result is in the dashboard payload.'},
  {id: 'apple-net', step: 'Reconciliation', missing: 'A statement has commission_minor, currency, created, and status only. It has no Apple net proceeds.'},
  {id: 'refund-detail', step: 'Refunds', missing: 'summary.refunded is a count. Amount, date, and transaction are absent.'},
  {id: 'trial-window', step: 'Trials', missing: 'Trial counts and trialConversion have no start or end dates.'},
  {id: 'manual-confirm', step: 'Manual settlement confirmation', missing: 'No route to confirm, mark paid, or record who approved a payout.'},
  {id: 'isolation', step: 'Private influencer page', missing: 'partner.name is the only identity field. The payload does not prove which influencer a session is isolated to.'},
  {id: 'commission-approval', step: 'Commission copy', missing: 'policy.commissionBps and the existing 20% sentence are pending confirmation, not an approved term.'}
];

export const tabs = ['overview', 'codes', 'statements', 'account'];

export const tabLabels = {
  en: {nav: 'Sections', overview: 'Overview', codes: 'Codes', statements: 'Statements', account: 'Account'},
  'zh-Hans': {nav: '分区', overview: '概览', codes: '优惠码', statements: '结算', account: '账户'},
  'zh-Hant': {nav: '分區', overview: '概覽', codes: '優惠碼', statements: '結算', account: '帳戶'},
  ja: {nav: 'セクション', overview: '概要', codes: 'コード', statements: '明細', account: 'アカウント'},
  ko: {nav: '구역', overview: '개요', codes: '코드', statements: '명세', account: '계정'},
  de: {nav: 'Bereiche', overview: 'Übersicht', codes: 'Codes', statements: 'Abrechnung', account: 'Konto'},
  es: {nav: 'Secciones', overview: 'Resumen', codes: 'Códigos', statements: 'Extracto', account: 'Cuenta'},
  fr: {nav: 'Sections', overview: 'Aperçu', codes: 'Codes', statements: 'Relevés', account: 'Compte'},
  it: {nav: 'Sezioni', overview: 'Riepilogo', codes: 'Codici', statements: 'Rendiconti', account: 'Account'},
  pt: {nav: 'Seções', overview: 'Resumo', codes: 'Códigos', statements: 'Extrato', account: 'Conta'},
  ru: {nav: 'Разделы', overview: 'Обзор', codes: 'Коды', statements: 'Отчёты', account: 'Аккаунт'},
  ar: {nav: 'أقسام', overview: 'نظرة', codes: 'رموز', statements: 'كشوف', account: 'الحساب'}
};

export function tabFromHash(hash) {
  const name = String(hash || '').replace(/^#/, '');
  return tabs.includes(name) ? name : 'overview';
}

export function tabLabel(lang, key) {
  const pack = tabLabels[lang] || tabLabels.en;
  return pack[key] || tabLabels.en[key] || key;
}

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const codePattern = /^[A-Za-z][A-Za-z0-9]{3,19}$/;

export function validateEmail(value) {
  const email = String(value ?? '').trim();
  if (!email || email.length > 254 || !emailPattern.test(email)) return 'email';
  return '';
}
export function validateName(value) {
  const name = String(value ?? '').trim();
  if (!name || name.length > 80) return 'name';
  return '';
}
export function validateOtp(value) {
  return /^[0-9]{6}$/.test(String(value ?? '').trim()) ? '' : 'otp';
}
export function validateCode(value) {
  return codePattern.test(String(value ?? '').trim()) ? '' : 'code';
}

export function loginDisabled(policy, pilotQuery) {
  return !policy?.registrationOpen && !pilotQuery;
}
export function createDisabled(policy, pilot) {
  return !policy?.campaignReady && !pilot;
}
export function knownStatus(status) {
  return codeStatuses.includes(status) ? status : '';
}
export function countText(value, locale) {
  return typeof value === 'number' && Number.isFinite(value) ? value.toLocaleString(locale) : '—';
}
export function ratioText(numerator, denominator, locale) {
  if (typeof numerator !== 'number' || typeof denominator !== 'number') return '—';
  if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator <= 0) return '—';
  return new Intl.NumberFormat(locale, {style: 'percent', maximumFractionDigits: 1}).format(numerator / denominator);
}
export function settlementReady(row) {
  return !!(row && Number.isFinite(row.commission_minor) && typeof row.currency === 'string' && row.currency && row.created && row.status);
}
export function shareLink(origin, code) {
  return origin + '/r/' + encodeURIComponent(code);
}

const blankSummary = Object.fromEntries(summaryFields.map(key => [key, null]));

export const localDemo = {
  mock: true,
  acceptedTerms: false,
  pilot: false,
  partner: {name: 'Local demo'},
  updatedAt: '2026-11-13T00:00:00.000Z',
  summary: {...blankSummary},
  codes: [
    {code: 'LOCALONLY', status: 'active', visits: null, bound: null},
    {code: 'LOCALOFF', status: 'disabled', visits: null, bound: null}
  ],
  settlements: []
};

export const emptyDemo = {
  mock: true,
  acceptedTerms: false,
  pilot: false,
  partner: {name: 'Local demo'},
  updatedAt: '2026-11-13T00:00:00.000Z',
  summary: {...blankSummary},
  codes: [],
  settlements: []
};
