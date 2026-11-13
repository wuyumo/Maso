import { notices } from './notices.mjs'
import { offeredLanguages, PARTNER_STRINGS } from './strings.mjs'

export { offeredLanguages, PARTNER_STRINGS }

export function chooseLanguage(value) {
  const raw = String(value || '')
  if (/^zh/i.test(raw)) return /Hant|TW|HK/i.test(raw) ? 'zh-Hant' : 'zh-Hans'
  const base = raw.split('-')[0]
  return PARTNER_STRINGS[base] ? base : 'en'
}

export function createT(lang) {
  return (key) => PARTNER_STRINGS[lang]?.[key] || PARTNER_STRINGS.en[key] || notices[lang]?.[key] || notices.en[key] || key
}
