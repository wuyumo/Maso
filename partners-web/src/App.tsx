import { FormEvent, KeyboardEvent, ReactNode, useEffect, useRef, useState } from 'react'
import { CircleUser, LayoutDashboard, Receipt, Ticket } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { chooseLanguage, createT, offeredLanguages } from './i18n/index.mjs'
import {
  countText, createDisabled, emptyDemo, knownStatus, localDemo, loginDisabled,
  ratioText, settlementReady, shareLink, tabFromHash, tabLabel, tabs,
  validateCode, validateEmail, validateName, validateOtp,
} from './lib/contract.mjs'

type Dash = typeof localDemo
type Tone = '' | 'error' | 'ok'

function changeLang(next: string) {
  const url = new URL(location.href)
  url.searchParams.set('lang', next)
  location.assign(url.toString())
}

const localHost = typeof location !== 'undefined' && (location.hostname === '127.0.0.1' || location.hostname === 'localhost')
const preview = localHost ? new URLSearchParams(location.search).get('preview') || '' : ''
const navIcons = { overview: LayoutDashboard, codes: Ticket, statements: Receipt, account: CircleUser }

function initialLang() {
  const query = new URLSearchParams(location.search).get('lang')
  return chooseLanguage(query || localStorage.getItem('partner-language') || navigator.language)
}

async function api(path: string, body?: Record<string, unknown>) {
  let response: Response
  try {
    response = await fetch('/api/' + path, {
      method: body ? 'POST' : 'GET',
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined,
    })
  } catch {
    throw Error('network')
  }
  let payload: { error?: string } = {}
  try { payload = await response.json() } catch { throw Error('request_failed') }
  if (!response.ok) throw Error(payload.error || 'request_failed')
  return payload
}

export default function App() {
  const [lang, setLang] = useState(initialLang)
  const t = createT(lang)
  const [policy, setPolicy] = useState<{ registrationOpen?: boolean, campaignReady?: boolean } | null>(null)
  const [mode, setMode] = useState<'boot' | 'public' | 'verify' | 'referral' | 'private'>('boot')
  const [tab, setTab] = useState(tabFromHash(location.hash))
  const [email, setEmail] = useState('')
  const [name, setName] = useState('')
  const [data, setData] = useState<Dash | null>(null)
  const [message, setMessage] = useState('')
  const [tone, setTone] = useState<Tone>('')
  const [busy, setBusy] = useState(false)
  const [field, setField] = useState('')
  const scroller = useRef<HTMLDivElement>(null)
  const memory = useRef<Record<string, number>>({})
  const seen = useRef(new Set<string>())

  useEffect(() => {
    document.documentElement.lang = lang
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr'
    localStorage.setItem('partner-language', lang)
  }, [lang])

  useEffect(() => {
    let cancel = false
    ;(async () => {
      try {
        const next = await api('policy') as { registrationOpen?: boolean, campaignReady?: boolean }
        if (cancel) return
        setPolicy(next)
        if (location.pathname.startsWith('/r/')) { setMode('referral'); return }
        if (preview === 'verify') { setMode('verify'); setTone('ok'); setMessage(t('verifyDemo')); return }
        if (preview === 'error') { setMode('public'); setTone('error'); setMessage(t('failed')); return }
        if (preview === 'unauthorized') { setMode('public'); setTone('error'); setMessage(t('unauthorized')); return }
        if (preview === 'loading') { setMode('public'); setBusy(true); setMessage(t('loading')); return }
        if (preview === 'dashboard' || preview === 'empty') {
          openPrivate(preview === 'empty' ? emptyDemo : localDemo, tabFromHash(location.hash))
          return
        }
        try {
          openPrivate(await api('dashboard') as Dash, tabFromHash(location.hash))
        } catch (error) {
          if ((error as Error).message !== 'sign_in_required') throw error
          setMode('public')
        }
      } catch (error) {
        setMode('public')
        setTone('error')
        setMessage(explain(error as Error, t))
      }
    })()
    return () => { cancel = true }
  }, [lang])

  useEffect(() => {
    const onHash = () => {
      if (mode !== 'private') return
      const next = tabFromHash(location.hash)
      if (next !== tab) applyTab(next, true)
    }
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [mode, tab])

  function explain(error: Error, tr = t) {
    if (error.message === 'terms_required') return tr('termsRequired')
    if (error.message === 'sign_in_required') return tr('unauthorized')
    const key = ({
      registration_not_ready: 'closed', campaign_not_ready: 'closed', code_taken_or_limit: 'codeConflict',
      invalid_or_expired_code: 'otpInvalid', rate_limited: 'rateLimited', network: 'failed', request_failed: 'failed',
    } as Record<string, string>)[error.message]
    return tr(key || 'failed')
  }

  function clearSession() {
    setData(null)
    setEmail('')
    setName('')
    memory.current = {}
    seen.current = new Set()
    setMode('public')
    if (location.hash) history.replaceState(null, '', location.pathname + location.search)
  }

  function openPrivate(next: Dash, initial: string) {
    setData({ ...next, partner: { ...next.partner }, summary: { ...next.summary }, codes: next.codes.map(code => ({ ...code })), settlements: [...next.settlements] })
    setMode('private')
    setMessage('')
    applyTab(initial, true)
    if (location.hash !== '#' + initial) history.replaceState(null, '', location.pathname + location.search + '#' + initial)
  }

  function onNavKey(event: KeyboardEvent<HTMLElement>) {
    const current = tabs.indexOf((event.target as HTMLElement).closest?.('[data-tab]')?.getAttribute('data-tab') || '')
    if (current < 0) return
    const forward = document.documentElement.dir === 'rtl' ? -1 : 1
    let next = -1
    if (event.key === 'ArrowRight') next = (current + forward + tabs.length) % tabs.length
    else if (event.key === 'ArrowLeft') next = (current - forward + tabs.length) % tabs.length
    else if (event.key === 'Home') next = 0
    else if (event.key === 'End') next = tabs.length - 1
    else return
    event.preventDefault()
    applyTab(tabs[next], false)
    document.getElementById(`tab-${tabs[next]}`)?.focus()
  }

  function applyTab(next: string, fromHash: boolean) {
    const name = tabs.includes(next) ? next : 'overview'
    if (scroller.current) memory.current[tab] = scroller.current.scrollTop
    setTab(name)
    if (!fromHash && location.hash !== '#' + name) location.hash = name
    const y = seen.current.has(name) ? memory.current[name] || 0 : 0
    seen.current.add(name)
    requestAnimationFrame(() => { if (scroller.current) scroller.current.scrollTop = y })
  }

  async function onLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const emailError = validateEmail(form.get('email'))
    const nameError = validateName(form.get('name'))
    if (emailError || nameError) { setField(emailError ? 'emailInvalid' : 'nameInvalid'); return }
    setField('')
    const nextEmail = String(form.get('email')).trim()
    const nextName = String(form.get('name')).trim()
    setBusy(true); setMessage(t('loading'))
    try {
      await api('login', { email: nextEmail })
      setEmail(nextEmail); setName(nextName); setMode('verify'); setTone('ok'); setMessage(t('sent'))
    } catch (error) { setTone('error'); setMessage(explain(error as Error)) }
    finally { setBusy(false) }
  }

  async function onVerify(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const otp = String(new FormData(event.currentTarget).get('otp') || '')
    if (validateOtp(otp)) { setField('otpInvalid'); return }
    setField(''); setBusy(true); setMessage(t('loading'))
    try {
      await api('login/verify', { email, name, otp: otp.trim() })
      openPrivate(await api('dashboard') as Dash, 'overview')
    } catch (error) { setTone('error'); setMessage(explain(error as Error)) }
    finally { setBusy(false) }
  }

  async function onCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (createDisabled(policy, data?.pilot)) { setTone('error'); setMessage(t('closed')); return }
    const form = new FormData(event.currentTarget)
    if (validateCode(form.get('code'))) { setField('codeInvalid'); return }
    if (event.currentTarget.dataset.terms !== 'yes' && !data?.acceptedTerms) { setField('termsRequired'); return }
    setField(''); setBusy(true)
    try {
      await api('codes', { code: String(form.get('code')).trim(), acceptTerms: event.currentTarget.dataset.terms === 'yes' || !!data?.acceptedTerms })
      event.currentTarget.reset()
      openPrivate(await api('dashboard') as Dash, 'codes')
    } catch (error) { setTone('error'); setMessage(explain(error as Error)) }
    finally { setBusy(false) }
  }

  async function onStatus(code: string, status: string) {
    if (status === 'disabled' && !confirm(t('disableAsk'))) return
    setBusy(true)
    try { await api('codes/status', { code, status }); openPrivate(await api('dashboard') as Dash, 'codes') }
    catch (error) { setTone('error'); setMessage(explain(error as Error)) }
    finally { setBusy(false) }
  }

  async function copy(value: string, local = false) {
    try { await navigator.clipboard.writeText(value); setTone('ok'); setMessage(local ? t('localShare') : t('copied')) }
    catch (error) { setTone('error'); setMessage(explain(error as Error)) }
  }

  async function reload(which: string) {
    if (preview === 'dashboard' || preview === 'empty') { openPrivate(preview === 'empty' ? emptyDemo : localDemo, which); return }
    setBusy(true)
    try { openPrivate(await api('dashboard') as Dash, which) }
    catch (error) {
      if ((error as Error).message === 'sign_in_required') { clearSession(); setTone('error'); setMessage(t('unauthorized')); return }
      setTone('error'); setMessage(explain(error as Error))
    } finally { setBusy(false) }
  }

  async function logout() {
    setBusy(true)
    try { await api('logout', {}); clearSession(); location.assign('/') }
    catch (error) { setTone('error'); setMessage(explain(error as Error)); setBusy(false) }
  }

  const closedLogin = loginDisabled(policy, new URLSearchParams(location.search).has('pilot'))
  const banner = message ? <Alert variant={tone === 'error' ? 'destructive' : 'default'}><AlertDescription id="message" role="status">{message}</AlertDescription></Alert> : <p id="message" className="sr-only" role="status" />

  if (mode === 'referral') {
    const code = decodeURIComponent(location.pathname.slice(3).replace(/\/$/, ''))
    return <PublicFrame lang={lang} onLang={changeLang} t={t}>{banner}<Referral code={code} t={t} onCopy={() => copy(code)} local={localHost} /></PublicFrame>
  }
  if (mode !== 'private' || !data) {
    return <PublicFrame lang={lang} onLang={changeLang} t={t}>{banner}{mode === 'verify'
      ? <Verify t={t} busy={busy} field={field} onSubmit={onVerify} />
      : <Landing t={t} busy={busy} field={field} closed={closedLogin} onSubmit={onLogin} />}</PublicFrame>
  }

  return (
    <div className="flex h-dvh bg-background">
      <aside className="hidden w-60 shrink-0 flex-col border-r bg-card lg:flex">
        <Brand />
        <nav aria-label={tabLabel(lang, 'nav')} className="flex flex-1 flex-col gap-1 p-3" onKeyDown={onNavKey}>
          {tabs.map(id => <NavButton key={id} id={id} lang={lang} active={tab === id} onSelect={() => applyTab(id, false)} desktop />)}
        </nav>
        <p className="px-4 pb-4 text-sm text-muted-foreground">{data.partner?.name || '—'}</p>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between gap-3 border-b px-4 py-3 lg:hidden">
          <Brand compact />
          <LanguageSelect lang={lang} onLang={changeLang} />
        </header>
        <div ref={scroller} className="min-h-0 flex-1 overflow-y-auto">
          <div className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-6 pb-8">
            {data.mock ? <Alert><AlertDescription>{t('localDemo')}</AlertDescription></Alert> : null}
            {banner}
            {tab === 'overview' ? <Overview data={data} t={t} lang={lang} policy={policy} busy={busy} onRefresh={() => reload('overview')} /> : null}
            {tab === 'codes' ? <Codes data={data} t={t} lang={lang} policy={policy} busy={busy} field={field} local={localHost} onCreate={onCreate} onStatus={onStatus} onCopy={copy} onRefresh={() => reload('codes')} /> : null}
            {tab === 'statements' ? <Statements data={data} t={t} lang={lang} /> : null}
            {tab === 'account' ? <Account data={data} t={t} lang={lang} busy={busy} onLang={changeLang} onLogout={logout} /> : null}
          </div>
        </div>
        <nav aria-label={tabLabel(lang, 'nav')} className="grid grid-cols-4 border-t bg-card pb-[env(safe-area-inset-bottom)] lg:hidden" onKeyDown={onNavKey}>
          {tabs.map(id => <NavButton key={id} id={id} domId={`tab-${id}`} lang={lang} active={tab === id} onSelect={() => applyTab(id, false)} />)}
        </nav>
      </div>
    </div>
  )
}

function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <a href="/" className={compact ? 'flex items-center gap-2' : 'flex items-center gap-3 px-4 py-5'}>
      <img src="/logo.svg" alt="" className="h-8 w-8 rounded-md bg-primary p-1" />
      <span className="text-sm font-semibold tracking-wide">MASSO <span className="font-normal text-muted-foreground">Partners</span></span>
    </a>
  )
}

function LanguageSelect({ lang, onLang }: { lang: string, onLang: (value: string) => void }) {
  return (
    <Select value={lang} onValueChange={onLang}>
      <SelectTrigger aria-label="Language" className="h-11 w-[9.5rem]"><SelectValue /></SelectTrigger>
      <SelectContent>
        {Object.entries(offeredLanguages).map(([value, label]) => <SelectItem key={value} value={value}>{label as string}</SelectItem>)}
      </SelectContent>
    </Select>
  )
}

function PublicFrame({ lang, onLang, t, children }: { lang: string, onLang: (value: string) => void, t: (key: string) => string, children: ReactNode }) {
  return (
    <div className="mx-auto flex min-h-dvh w-full max-w-lg flex-col gap-6 px-4 py-8">
      <div className="flex items-center justify-between gap-3"><Brand compact /><LanguageSelect lang={lang} onLang={onLang} /></div>
      {children}
      <p className="text-xs text-muted-foreground">Masso Partners · <a className="text-primary underline-offset-4 hover:underline" href="/terms">{t('terms')}</a></p>
    </div>
  )
}

function Landing({ t, busy, field, closed, onSubmit }: { t: (key: string) => string, busy: boolean, field: string, closed: boolean, onSubmit: (event: FormEvent<HTMLFormElement>) => void }) {
  return (
    <>
      <div className="space-y-2">
        <p className="text-sm font-medium text-primary">{t('tagline')}</p>
        <h1 className="text-3xl font-semibold tracking-tight">{t('title')}</h1>
        <p className="text-sm leading-6 text-muted-foreground">{t('intro')}</p>
      </div>
      <Alert><AlertDescription>{t('pendingFigures')}</AlertDescription></Alert>
      <p className="text-sm text-muted-foreground">{t('downloadFree')}</p>
      <Card>
        <CardHeader><CardTitle className="text-base">{t('email')}</CardTitle><CardDescription>{t('privacy')}</CardDescription></CardHeader>
        <CardContent>
          <form id="login" className="grid gap-4" onSubmit={onSubmit} aria-busy={busy}>
            <div className="grid gap-2"><Label htmlFor="email">{t('email')}</Label><Input id="email" name="email" type="email" autoComplete="email" required maxLength={254} aria-invalid={field === 'emailInvalid'} /></div>
            <div className="grid gap-2"><Label htmlFor="name">{t('creator')}</Label><Input id="name" name="name" autoComplete="nickname" required maxLength={80} aria-invalid={field === 'nameInvalid'} /></div>
            {field ? <p className="text-sm text-destructive" role="alert">{t(field)}</p> : null}
            {closed ? <Badge id="policy-closed" variant="secondary">{t('closed')}</Badge> : null}
            <Button variant={closed ? 'secondary' : 'default'} className="h-11" disabled={busy || closed} aria-describedby={closed ? 'policy-closed' : undefined}>{busy ? t('loading') : t('send')}</Button>
          </form>
        </CardContent>
      </Card>
    </>
  )
}

function Verify({ t, busy, field, onSubmit }: { t: (key: string) => string, busy: boolean, field: string, onSubmit: (event: FormEvent<HTMLFormElement>) => void }) {
  return (
    <Card>
      <CardHeader><CardTitle>{t('signin')}</CardTitle><CardDescription>{t('missing')}</CardDescription></CardHeader>
      <CardContent>
        <form id="verify" className="grid gap-4" onSubmit={onSubmit} aria-busy={busy}>
          <div className="grid gap-2"><Label htmlFor="otp">{t('otp')}</Label><Input id="otp" name="otp" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required aria-invalid={field === 'otpInvalid'} /></div>
          {field ? <p className="text-sm text-destructive" role="alert">{t(field)}</p> : null}
          <Button className="h-11" disabled={busy}>{busy ? t('loading') : t('signin')}</Button>
        </form>
      </CardContent>
    </Card>
  )
}

function Referral({ code, t, onCopy, local }: { code: string, t: (key: string) => string, onCopy: () => void, local: boolean }) {
  return (
    <>
      <div className="space-y-2">
        <p className="text-sm font-medium text-primary">{t('invite')}</p>
        <h1 className="text-3xl font-semibold tracking-tight">{t('train')}</h1>
      </div>
      <Alert><AlertDescription>{t('pendingFigures')}</AlertDescription></Alert>
      <p className="text-sm text-muted-foreground">{t('downloadFree')}</p>
      <Card><CardHeader><CardDescription>{t('code')}</CardDescription><CardTitle id="public-code" className="font-mono text-2xl" dir="ltr">{code}</CardTitle></CardHeader>
        <CardContent className="grid gap-4">
          <p className="text-sm text-muted-foreground">{t('offer')}</p>
          <p className="text-sm text-muted-foreground">{t('use')}</p>
          {local ? <p className="text-sm">{t('localLink')}</p> : null}
          <div className="flex flex-col gap-2 sm:flex-row">
            <Button id="copy-public" className="h-11" onClick={onCopy}>{t('copy')}</Button>
            <Button className="h-11" variant="secondary" asChild><a href="https://apps.apple.com/app/id6776689750">{t('appstore')}</a></Button>
          </div>
          <p className="text-xs text-muted-foreground">{t('availability')}</p>
        </CardContent>
      </Card>
    </>
  )
}

function Overview({ data, t, lang, policy, busy, onRefresh }: { data: Dash, t: (key: string) => string, lang: string, policy: { campaignReady?: boolean } | null, busy: boolean, onRefresh: () => void }) {
  const bound = (data.codes || []).reduce((sum, code) => sum + (typeof code.bound === 'number' ? code.bound : Number.NaN), 0)
  const summary = data.summary || {}
  const rows: [string, string][] = [
    ['attributed', countText(summary.attributed, lang)], ['trialing', countText(summary.trialing, lang)], ['paid', countText(summary.paid, lang)],
    ['monthlyTrial', countText(summary.monthlyTrialing, lang)], ['yearlyTrial', countText(summary.yearlyTrialing, lang)],
    ['monthlyPaid', countText(summary.monthlyPaid, lang)], ['yearlyPaid', countText(summary.yearlyPaid, lang)],
    ['monthlyActive', countText(summary.monthly, lang)], ['yearlyActive', countText(summary.yearly, lang)], ['refunded', countText(summary.refunded, lang)],
    ['referralPaid', ratioText(summary.paid, bound, lang)],
    ['trialPaid', summary.trialConversion == null ? '—' : ratioText(summary.trialConversion, 1, lang)],
  ]
  return (
    <section id="panel-overview" className="grid gap-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div><p className="text-sm font-medium text-primary">{t('dashboard')}</p><h1 id="greeting" className="text-2xl font-semibold tracking-tight">{t('welcome')}, {data.partner?.name || '—'}</h1><p className="text-sm text-muted-foreground">{data.updatedAt ? `${t('synced')} ${new Date(data.updatedAt).toLocaleString(lang)}` : ''}</p></div>
        <Button id="refresh" variant="secondary" className="h-11" disabled={busy} onClick={onRefresh}>{t('refresh')}</Button>
      </div>
      {!policy?.campaignReady && !data.pilot ? <Badge variant="secondary">{t('closed')}</Badge> : null}
      <div id="metrics" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {rows.map(([key, value]) => <Card key={key}><CardHeader className="space-y-1 p-4"><CardDescription>{t(key)}</CardDescription><CardTitle className="text-2xl tabular-nums">{value}</CardTitle></CardHeader></Card>)}
      </div>
      <p className="text-sm leading-6 text-muted-foreground">{t('trialNote')}</p>
    </section>
  )
}

function Codes({ data, t, lang, policy, busy, field, local, onCreate, onStatus, onCopy, onRefresh }: { data: Dash, t: (key: string) => string, lang: string, policy: { campaignReady?: boolean } | null, busy: boolean, field: string, local: boolean, onCreate: (event: FormEvent<HTMLFormElement>) => void, onStatus: (code: string, status: string) => void, onCopy: (value: string, local?: boolean) => void, onRefresh: () => void }) {
  const [accepted, setAccepted] = useState(false)
  const disabled = createDisabled(policy, data.pilot)
  const codes = Array.isArray(data.codes) ? data.codes : []
  return (
    <section id="panel-codes" className="grid gap-6">
      <h1 className="text-2xl font-semibold tracking-tight">{t('codes')}</h1>
      <Card>
        <CardHeader><CardTitle className="text-base">{t('newcode')}</CardTitle><CardDescription>{t('codeNote')}</CardDescription></CardHeader>
        <CardContent>
          <form id="create" className="grid gap-4" data-terms={accepted ? 'yes' : ''} onSubmit={onCreate}>
            <div className="grid gap-2"><Label htmlFor="code">{t('newcode')}</Label><Input id="code" name="code" dir="ltr" autoComplete="off" required minLength={4} maxLength={20} pattern="[A-Za-z][A-Za-z0-9]{3,19}" placeholder="ALEXFIT" aria-invalid={field === 'codeInvalid'} /></div>
            {!data.acceptedTerms ? <div className="flex items-start gap-3"><Checkbox id="terms" checked={accepted} onCheckedChange={value => setAccepted(value === true)} aria-invalid={field === 'termsRequired'} /><Label htmlFor="terms" className="text-sm font-normal leading-5">{t('accept')} <a className="text-primary underline-offset-4 hover:underline" href="/terms">{t('terms')}</a></Label></div> : null}
            {field ? <p className="text-sm text-destructive" role="alert">{t(field)}</p> : null}
            {disabled ? <p id="create-closed" className="text-sm text-muted-foreground">{t('closed')}</p> : null}
            <Button variant={disabled ? 'secondary' : 'default'} className="h-11" disabled={busy || disabled} aria-describedby={disabled ? 'create-closed' : undefined}>{t('create')}</Button>
          </form>
        </CardContent>
      </Card>
      {codes.length ? codes.map(code => {
        const status = knownStatus(code.status)
        const link = shareLink(location.origin, code.code || '')
        return (
          <Card key={code.code}>
            <CardHeader className="flex-row items-start justify-between space-y-0"><CardTitle className="font-mono text-lg" dir="ltr">{code.code || '—'}</CardTitle><Badge variant={status === 'failed' ? 'destructive' : status === 'active' ? 'default' : 'secondary'}>{status ? t(status) : '—'}</Badge></CardHeader>
            <CardContent className="grid gap-3 text-sm text-muted-foreground">
              <p>{t('visits')}: {countText(code.visits, lang)} · {t('bindings')}: {countText(code.bound, lang)}</p>
              <p dir="ltr">{link}</p>
              {local ? <p>{t('localLink')}</p> : null}
              {local && status === 'active' ? <div className="rounded-md border border-dashed px-4 py-8 text-center text-xs text-foreground">{t('notScannable')}</div> : null}
              <div className="flex flex-wrap gap-2">
                <Button type="button" variant="secondary" className="h-11" onClick={() => onCopy(code.code || '')}>{t('copy')}</Button>
                {status === 'active' ? <Button type="button" variant="secondary" className="h-11" onClick={() => onCopy(link, local)}>{t('share')}</Button> : null}
                {status === 'active' ? <Button type="button" variant="outline" className="h-11" disabled={busy} onClick={() => onStatus(code.code, 'disabled')}>{t('disable')}</Button> : null}
                {status === 'disabled' || status === 'failed' ? <Button type="button" variant="outline" className="h-11" disabled={busy} onClick={() => onStatus(code.code, 'archived')}>{t('archive')}</Button> : null}
                {status === 'creating' || status === 'disabling' ? <Button type="button" variant="secondary" className="h-11" disabled={busy} onClick={onRefresh}>{t('refresh')}</Button> : null}
                {status === 'disabling' ? <Button type="button" variant="outline" className="h-11" disabled={busy} onClick={() => onStatus(code.code, 'disabled')}>{t('retry')}</Button> : null}
              </div>
            </CardContent>
          </Card>
        )
      }) : <Card className="border-dashed"><CardContent className="py-10 text-center text-sm text-muted-foreground">{t('codesEmpty')}</CardContent></Card>}
    </section>
  )
}

function Statements({ data, t, lang }: { data: Dash, t: (key: string) => string, lang: string }) {
  const rows = ((Array.isArray(data.settlements) ? data.settlements : []) as { created: string, commission_minor: number, currency: string, status: string }[]).filter(settlementReady)
  return (
    <section id="panel-statements" className="grid gap-4">
      <h1 className="text-2xl font-semibold tracking-tight">{t('statements')}</h1>
      <Alert><AlertDescription>{t('payout')} <a className="text-primary underline-offset-4 hover:underline" href="mailto:wuyumoawuyumo@gmail.com">Masso Support</a></AlertDescription></Alert>
      <p className="text-sm leading-6 text-muted-foreground">{t('statementNote')}</p>
      <Alert><AlertDescription>{t('pendingFigures')}</AlertDescription></Alert>
      <p className="text-sm text-muted-foreground">{t('settlementReadonly')}</p>
      {rows.length ? (
        <Card><CardContent className="p-0"><Table>
          <TableHeader><TableRow><TableHead>{t('colDate')}</TableHead><TableHead>{t('colCurrency')}</TableHead><TableHead className="text-end">{t('colAmount')}</TableHead><TableHead>{t('status')}</TableHead></TableRow></TableHeader>
          <TableBody>{rows.map((row, index) => <TableRow key={index}><TableCell>{new Date(row.created).toLocaleDateString(lang)}</TableCell><TableCell>{row.currency}</TableCell><TableCell className="text-end tabular-nums">{new Intl.NumberFormat(lang, { style: 'currency', currency: row.currency }).format(row.commission_minor / 100)}</TableCell><TableCell>{t(row.status === 'paid' ? 'paidStatus' : row.status === 'refund adjustment' ? 'adjustment' : row.status)}</TableCell></TableRow>)}</TableBody>
        </Table></CardContent></Card>
      ) : <Card className="border-dashed"><CardContent className="py-10 text-center text-sm text-muted-foreground">{t('empty')}</CardContent></Card>}
    </section>
  )
}

function Account({ data, t, lang, busy, onLang, onLogout }: { data: Dash, t: (key: string) => string, lang: string, busy: boolean, onLang: (value: string) => void, onLogout: () => void }) {
  return (
    <section id="panel-account" className="grid gap-4">
      <h1 className="text-2xl font-semibold tracking-tight">{tabLabel(lang, 'account')}</h1>
      <Card>
        <CardHeader><CardDescription>{t('creator')}</CardDescription><CardTitle id="account-name">{data.partner?.name || '—'}</CardTitle></CardHeader>
        <CardContent className="grid gap-4">
          <Separator />
          <div className="grid gap-2"><Label>{(offeredLanguages as Record<string, string>)[lang] || 'Language'}</Label><LanguageSelect lang={lang} onLang={onLang} /></div>
          <a className="text-sm text-primary underline-offset-4 hover:underline" href="/terms">{t('terms')}</a>
          <a className="text-sm text-primary underline-offset-4 hover:underline" href="mailto:wuyumoawuyumo@gmail.com">Masso Support</a>
          <Button id="logout" variant="secondary" className="h-11 w-fit" disabled={busy} onClick={onLogout}>{t('logout')}</Button>
        </CardContent>
      </Card>
    </section>
  )
}

function NavButton({ id, lang, active, onSelect, desktop = false, domId }: { id: string, lang: string, active: boolean, onSelect: () => void, desktop?: boolean, domId?: string }) {
  const Icon = navIcons[id as keyof typeof navIcons]
  return (
    <Button id={domId} data-tab={id} type="button" variant={active ? 'secondary' : 'ghost'} aria-current={active ? 'page' : undefined} className={desktop ? 'h-11 justify-start' : 'h-14 flex-col gap-1 rounded-none px-1 text-[11px]'} onClick={onSelect}>
      <Icon aria-hidden="true" />
      <span>{tabLabel(lang, id)}</span>
    </Button>
  )
}
