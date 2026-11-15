#!/usr/bin/env python3
"""Rebuild Masso's zh-Hant (Traditional Chinese for Taiwan) from zh-Hans.

Why: the shipped zh-Hant content was machine translated from English
(Argos). Names such as bench_press_barbell became 「座椅出版社」 and many
strings kept Simplified characters. This script derives zh-Hant from the
Simplified Chinese source instead, then fixes Taiwan wording.

Pipeline per string:
  1. OpenCC `s2twp`  simplified -> Traditional with Taiwan phrase mapping
  2. scripts/zh_hant_tw_terms.tsv  domain words OpenCC lacks
     (热身->暖身, 卷腹->捲腹, 平板支撑->棒式, 泡沫轴->泡棉滾筒 ...)
  3. Chinese punctuation normalisation (，。：；？！ and no space after)

Files rewritten (only the zh-Hant side):
  * Maso/Resources/exercises.json
      name / instructions / danger_warnings / nameParts.localizedBase
  * Maso/Resources/zh-Hant.lproj/Localizable.strings
  * MasoWidgets/zh-Hant.lproj/Localizable.strings
  * MasoWatch/zh-Hant.lproj/Localizable.strings

zh-Hant.lproj/InfoPlist.strings is human written and already correct; it is
only verified, never regenerated.

Usage:
  python3 scripts/rebuild_zh_hant.py                 # dry run + report
  python3 scripts/rebuild_zh_hant.py --apply         # write the files
  python3 scripts/rebuild_zh_hant.py --report PATH   # custom report path

Requires: python3 -m pip install opencc-python-reimplemented
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

import opencc

ROOT = Path(__file__).resolve().parents[1]
TSV = ROOT / 'scripts/zh_hant_tw_terms.tsv'
EXERCISES = ROOT / 'Maso/Resources/exercises.json'

STRINGS_PAIRS = [
    ('Maso/Resources/zh-Hans.lproj/Localizable.strings',
     'Maso/Resources/zh-Hant.lproj/Localizable.strings'),
    ('MasoWidgets/zh-Hans.lproj/Localizable.strings',
     'MasoWidgets/zh-Hant.lproj/Localizable.strings'),
    ('MasoWatch/zh-Hans.lproj/Localizable.strings',
     'MasoWatch/zh-Hant.lproj/Localizable.strings'),
]

VERIFY_ONLY = ['Maso/Resources/zh-Hant.lproj/InfoPlist.strings']

EXERCISE_SCALARS = [('name', lambda ex: ex.get('name')),
                    ('nameParts.localizedBase',
                     lambda ex: (ex.get('nameParts') or {}).get('localizedBase'))]
EXERCISE_LISTS = ['instructions', 'danger_warnings']

# The wording table swaps 绳索->滑輪 and 拉伸->伸展 everywhere, which is right for
# "Cable" machine names but wrong in the few sentences that mean the rope itself
# or double up the verb. Those sentences are pinned here, by exact list index, so
# the pipeline stays idempotent instead of drifting back to the table output.
EXERCISE_ZH_HANT_FIXES: dict[tuple[str, str, int], str] = {
    # 绳索->滑輪: 「高位滑輪, 绳索」 became 「高位滑輪，滑輪」 — the rope attachment.
    ('cable_row_face_pull_style', 'instructions', 0): '高位滑輪，繩索，拉至臉位。',
    # 绳索->滑輪: 「腦後握绳索」 is grabbing the rope, not the pulley.
    ('cable_extension_behind_back', 'instructions', 0): '背對滑輪，腦後握繩索。',
    # 拉伸->伸展: 「緩慢伸展, 充分伸展」 repeats; the rep ends on the return.
    ('lat_pulldown', 'instructions', 2): '緩慢回放，充分伸展。',
}

HEADER_COMMENT = (
    '/* Traditional Chinese (Taiwan). Generated from zh-Hans by '
    'scripts/rebuild_zh_hant.py — edit zh-Hans and re-run, do not patch '
    'this file alone. */'
)
ADDED_COMMENT = '/* Added from zh-Hans: keys missing in this file. */'

KV_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
CJK_RE = re.compile(r'[\u3400-\u9fff]')
# Chinese sentence context also includes the full-width punctuation and the
# 「」『』— marks: 「（1-3 塊）, 槓鈴」 is a Chinese comma, not a Latin one.
CJK_CTX_RE = re.compile(r'[\u3400-\u9fff\u300c\u300d\u300e\u300f\uff08\uff09'
                        r'\u3001\uff0c\u3002\uff1a\uff1b\uff1f\uff01\u2014]')
LATIN_RE = re.compile(r'[A-Za-z]{3,}')
PUNCT = {',': '，', ':': '：', ';': '；', '?': '？', '!': '！'}
TW = timezone(timedelta(hours=8))

# Tokens that are intentionally Latin in a Chinese build.
LATIN_OK = {
    'AI', 'HIIT', 'TRX', 'RKC', 'EMOM', 'CAR', 'GHD', 'PVC', 'RPM', 'RTO',
    'AMRAP', 'Pro', 'Masso', 'Apple', 'Health', 'HealthKit', 'Watch', 'Polar',
    'QR', 'Code', 'iOS', 'iPad', 'iPhone', 'kg', 'lb', 'lbs', 'min', 'sec',
    'kcal', 'BPM', 'bpm', 'PR', 'VO2', 'max', 'Cybex', 'Hammer', 'Strength',
    'Pallof', 'Smith', 'Landmine', 'Bulgarian', 'Nordic', 'Arnold', 'Zercher',
    'Jefferson', 'Kroc', 'Helms', 'RDL', 'LISS', 'TUT', '1RM', 'EZ', 'SMR',
    'SPARTA', 'COSS', 'ABS', 'MVP', 'PDF', 'CSV', 'API', 'URL', 'http',
    'https', 'www', 'Maso', 'Widget', 'Live', 'Activity', 'Series', 'Duo',
}


class Taiwanizer:
    """Simplified -> Taiwan Traditional with the project term table."""

    def __init__(self) -> None:
        self.opencc = opencc.OpenCC('s2twp')
        self.table: dict[str, str] = {}
        self.rows: list[tuple[str, str, str]] = []
        self.active = 0
        for line in TSV.read_text(encoding='utf-8').splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) < 2:
                continue
            cn, tw = parts[0].strip(), parts[1].strip()
            if not cn or not tw:
                continue
            key = self.opencc.convert(cn)
            self.rows.append((cn, key, tw))
            if key != tw:
                self.active += 1
            # Identity rows are kept on purpose: they are "shields" that let a
            # longer phrase win over a shorter rule (e.g. 已記錄 before 記錄).
            self.table[key] = tw
        self.keys = sorted(self.table, key=len, reverse=True)
        self.pattern = (re.compile('|'.join(re.escape(k) for k in self.keys))
                        if self.keys else None)
        self.hits: Counter[str] = Counter()

    def convert(self, text: str) -> str:
        if not text:
            return text
        out = self.opencc.convert(text)
        if self.pattern is None:
            return out

        def sub(m: re.Match) -> str:
            hit = m.group(0)
            target = self.table[hit]
            if target != hit:
                self.hits[hit] += 1
            # A replacement can put a Latin word next to Chinese (掃碼獲取 ->
            # 掃描 QR Code取得). Keep one space at that seam.
            before = out[m.start() - 1] if m.start() else ''
            after = out[m.end()] if m.end() < len(out) else ''
            if CJK_RE.match(before or ' ') and re.match(r'[A-Za-z0-9]', target[:1] or ' '):
                target = ' ' + target
            if CJK_RE.match(after or ' ') and re.match(r'[A-Za-z0-9]', target[-1:] or ' '):
                target = target + ' '
            return target

        return self.pattern.sub(sub, out)


def taiwan_punctuation(text: str) -> str:
    """Half-width , : ; ? ! next to Chinese become full-width, space dropped."""
    if not text:
        return text
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        mapped = PUNCT.get(ch)
        if mapped:
            prev = text[i - 1] if i else ''
            nxt = text[i + 1] if i + 1 < n else ''
            if CJK_CTX_RE.match(prev or ' ') or CJK_CTX_RE.match(nxt or ' '):
                out.append(mapped)
                i += 1
                while i < n and text[i] == ' ':
                    i += 1
                continue
        out.append(ch)
        i += 1
    return re.sub(r'\.\s*$', '。', ''.join(out))


# "week" is 週 in Taiwan, but OpenCC only rewrites a few fixed phrases
# (週末, 週一 ...), so 4 周 / 每 2 周 / 周目標 survive as 周. 周 stays correct
# where it is not about a week: 周圍, 周邊, 周全, 周到, 週折/周折, 周身, 周而...
WEEK_ZHOU = re.compile(r'周(?![圍围邊边全到折身而遭知正])')


def taiwan_week(text: str) -> str:
    return WEEK_ZHOU.sub('週', text) if text else text


# Taiwan typeset quotes with 「」 (and 『』 when nested); “” is the mainland style.
QUOTES = {'“': '「', '”': '」', '‘': '『', '’': '』'}


def taiwan_quotes(text: str) -> str:
    return ''.join(QUOTES.get(ch, ch) for ch in text) if text else text


# Chinese does not separate words with spaces; a space between two Han
# characters or full-width brackets is a source typo ("“%@” 会被" keeps one).
CJK_SPACE = re.compile(r'(?<=[\u3400-\u9fff\u300c\u300d\u300e\u300f]) '
                       r'+(?=[\u3400-\u9fff\u300c\u300d\u300e\u300f])')


def taiwan_spacing(text: str) -> str:
    return CJK_SPACE.sub('', text) if text else text


# A Chinese parenthesis group uses （）in Taiwan; a group that only wraps Latin,
# a number or a unit keeps the half-width pair the Latin sentence already had
# ("重量 (kg)" stays, "羅馬尼亞式(屈髖直膝)" becomes "羅馬尼亞式（屈髖直膝）").
SPEC_ONLY = re.compile(r'%[@dfsu]|[\s\d.]')


def taiwan_parens(text: str) -> str:
    if not text or '(' not in text:
        return text
    out = list(text)
    stack: list[int] = []
    for index, char in enumerate(text):
        if char == '(':
            stack.append(index)
        elif char == ')' and stack:
            start = stack.pop()
            inside = text[start + 1:index]
            before = text[start - 1] if start else ''
            if CJK_RE.search(inside) or (
                    CJK_RE.search(before or ' ')
                    and not SPEC_ONLY.sub('', inside)):
                out[start] = '（'
                out[index] = '）'
    return ''.join(out)


SPACE_BEFORE_WIDE = re.compile(r'(?<=\S) +(?=（)')
SPACE_AFTER_WIDE = re.compile(r'(?<=）) +(?=[\u3400-\u9fff—，。、！？：；])')


def taiwan_tidy(text: str) -> str:
    """A full-width group never needs the space the half-width one did."""
    if not text:
        return text
    return SPACE_AFTER_WIDE.sub('', SPACE_BEFORE_WIDE.sub('', text))


def taiwanize(tz: Taiwanizer, text: str) -> str:
    # Parens run before punctuation: once ")" is "）" it counts as Chinese
    # context, so a Latin comma right after it ("（1-3 塊）, 槓鈴") is seen as
    # sandwiched in Chinese text and becomes "），".
    return taiwan_tidy(taiwan_punctuation(taiwan_parens(
        taiwan_spacing(taiwan_week(taiwan_quotes(tz.convert(text)))))))


S2T = opencc.OpenCC('s2t')

# Characters that OpenCC maps to a "preferred" glyph variant but that are also
# correct in Traditional Chinese (划船, 峰值, 游泳, 群組, 公里 ...). They are not
# Simplified leftovers, so they must not fail the check.
VARIANT_OK = set('划峰游吃床群里岩麻痴杯栖汹')


def simplified_chars(text: str) -> set[str]:
    found = set()
    for ch in text:
        if ch in VARIANT_OK:
            continue
        if CJK_RE.match(ch) and S2T.convert(ch) != ch:
            found.add(ch)
    return found


def latin_residue(text: str) -> Counter:
    hits: Counter[str] = Counter()
    for tok in LATIN_RE.findall(text):
        if tok not in LATIN_OK and tok.upper() not in LATIN_OK:
            hits[tok] += 1
    return hits


def read_kv(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        m = KV_RE.match(line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def rebuild_exercises(tz: Taiwanizer) -> tuple[str, dict]:
    data = json.loads(EXERCISES.read_text(encoding='utf-8'))
    stats = {'entries': len(data), 'scalars': 0, 'list_items': 0,
             'filled_missing': 0, 'pinned': 0, 'skipped': [], 'samples': []}
    for ex in data:
        ex_id = ex.get('id', '?')
        for label, getter in EXERCISE_SCALARS:
            node = getter(ex)
            if not isinstance(node, dict):
                stats['skipped'].append(f'{ex_id}.{label}: no container')
                continue
            src = (node.get('zh-Hans') or '').strip()
            if not src:
                stats['skipped'].append(f'{ex_id}.{label}: empty zh-Hans')
                continue
            new = taiwanize(tz, src)
            if node.get('zh-Hant') != new:
                stats['scalars'] += 1
                if len(stats['samples']) < 40:
                    stats['samples'].append({
                        'id': ex_id, 'field': label,
                        'zh-Hans': src,
                        'zh-Hant.before': node.get('zh-Hant'),
                        'zh-Hant.after': new})
                node['zh-Hant'] = new
        for field in EXERCISE_LISTS:
            node = ex.get(field)
            if not isinstance(node, dict):
                continue
            src_list = node.get('zh-Hans') or []
            if not src_list:
                stats['skipped'].append(f'{ex_id}.{field}: empty zh-Hans')
                continue
            had = bool(node.get('zh-Hant'))
            new_list = [taiwanize(tz, s) for s in src_list]
            for index, pinned in EXERCISE_ZH_HANT_FIXES.items():
                if index[0] == ex_id and index[1] == field and index[2] < len(new_list):
                    new_list[index[2]] = pinned
                    stats['pinned'] += 1
            if not had:
                stats['filled_missing'] += 1
            if node.get('zh-Hant') != new_list:
                stats['list_items'] += len(new_list)
                node['zh-Hant'] = new_list
    text = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    return text, stats


def rebuild_strings(tz: Taiwanizer, hans: Path, hant: Path) -> tuple[str, dict]:
    hans_kv = read_kv(hans)
    lines = hant.read_text(encoding='utf-8').splitlines()
    # Drop the tail block a previous run appended, so re-running is idempotent:
    # those keys are in the file now and must be re-emitted in place below.
    marker = next((i for i, l in enumerate(lines)
                   if l.strip() == ADDED_COMMENT), None)
    if marker is not None:
        start = marker
        while start > 0 and not lines[start - 1].strip():
            start -= 1
        lines = lines[:start] + lines[marker + 1:]
    while lines and not lines[0].strip():
        lines.pop(0)
    stats = {'keys_hans': len(hans_kv), 'keys_hant': 0, 'values_rewritten': 0,
             'from_hans': 0, 'from_old_hant': 0, 'added': [], 'samples': []}
    out: list[str] = []
    header_done = False
    seen: set[str] = set()
    for line in lines:
        m = KV_RE.match(line)
        if not m:
            stripped = line.strip()
            if stripped == HEADER_COMMENT:
                # Collapse any duplicated generated headers left by an older run.
                if not header_done:
                    out.append(HEADER_COMMENT)
                    header_done = True
                continue
            if not header_done and stripped.startswith('/*'):
                # Replace whatever header the file had (the old Argos note, or a
                # header a previous run wrote) with exactly one generated note.
                out.append(HEADER_COMMENT)
                header_done = True
                continue
            out.append(line)
            continue
        if not header_done:
            out.append(HEADER_COMMENT)
            header_done = True
        key, old = m.group(1), m.group(2)
        seen.add(key)
        stats['keys_hant'] += 1
        if key in hans_kv:
            new = taiwanize(tz, hans_kv[key])
            stats['from_hans'] += 1
        else:
            new = taiwanize(tz, old)
            stats['from_old_hant'] += 1
        if new != old:
            stats['values_rewritten'] += 1
            if len(stats['samples']) < 40:
                stats['samples'].append({'key': key, 'before': old,
                                         'after': new,
                                         'source': 'zh-Hans' if key in hans_kv
                                         else 'old zh-Hant'})
        out.append(f'"{key}" = "{new}";')
    missing = [k for k in hans_kv if k not in seen]
    if missing:
        out.append('')
        out.append(ADDED_COMMENT)
        for key in missing:
            out.append(f'"{key}" = "{taiwanize(tz, hans_kv[key])}";')
            stats['added'].append(key)
    return '\n'.join(out) + '\n', stats


def exercise_corpus(text: str) -> list[str]:
    """Only the zh-Hant values of exercises.json (other langs are not ours)."""
    parts: list[str] = []
    for ex in json.loads(text):
        for _, getter in EXERCISE_SCALARS:
            node = getter(ex) or {}
            if isinstance(node, dict) and node.get('zh-Hant'):
                parts.append(node['zh-Hant'])
        for field in EXERCISE_LISTS:
            node = ex.get(field) or {}
            if isinstance(node, dict):
                parts.extend(node.get('zh-Hant') or [])
    return parts


def strings_corpus(text: str) -> list[str]:
    return [m.group(2) for m in
            (KV_RE.match(line) for line in text.splitlines()) if m]


def verify_text(name: str, parts: list[str]) -> dict:
    simple: set[str] = set()
    latin: Counter[str] = Counter()
    samples: list[str] = []
    for part in parts:
        chars = simplified_chars(part)
        if chars:
            simple |= chars
            if len(samples) < 30:
                samples.append(part)
        latin.update(latin_residue(part))
    return {'file': name,
            'items': len(parts),
            'simplified_chars': ''.join(sorted(simple)),
            'simplified_count': len(simple),
            'simplified_samples': samples,
            'latin_residue': dict(latin.most_common(30)),
            'latin_total': sum(latin.values())}


def corpus_for(rel: str, text: str) -> list[str]:
    return (exercise_corpus(text) if rel.endswith('exercises.json')
            else strings_corpus(text))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true', help='write the files')
    ap.add_argument('--report', default='docs/zh-hant-tw-2026-11-09/report.json')
    args = ap.parse_args()

    tz = Taiwanizer()
    outputs: dict[str, str] = {}
    report: dict = {
        'generatedAt': datetime.now(TW).isoformat(timespec='seconds'),
        'tool': 'scripts/rebuild_zh_hant.py',
        'pipeline': ['opencc s2twp', 'scripts/zh_hant_tw_terms.tsv',
                     'taiwan punctuation'],
        'terms': {'rows': len(tz.rows), 'active': tz.active,
                  'shields': len(tz.table) - tz.active},
        'exercises': None,
        'strings': {},
        'verification': [],
        'term_hits': {},
    }

    before_src = {
        'Maso/Resources/exercises.json': EXERCISES.read_text(encoding='utf-8'),
        'Maso/Resources/zh-Hant.lproj/Localizable.strings':
            (ROOT / STRINGS_PAIRS[0][1]).read_text(encoding='utf-8'),
        'MasoWidgets/zh-Hant.lproj/Localizable.strings':
            (ROOT / STRINGS_PAIRS[1][1]).read_text(encoding='utf-8'),
        'MasoWatch/zh-Hant.lproj/Localizable.strings':
            (ROOT / STRINGS_PAIRS[2][1]).read_text(encoding='utf-8'),
    }
    for rel, text in before_src.items():
        report['verification'].append(
            {'stage': 'before', **verify_text(rel, corpus_for(rel, text))})

    text, stats = rebuild_exercises(tz)
    outputs['Maso/Resources/exercises.json'] = text
    report['exercises'] = stats

    for hans_rel, hant_rel in STRINGS_PAIRS:
        text, st = rebuild_strings(tz, ROOT / hans_rel, ROOT / hant_rel)
        outputs[hant_rel] = text
        report['strings'][hant_rel] = st

    for rel, text in outputs.items():
        report['verification'].append(
            {'stage': 'after', **verify_text(rel, corpus_for(rel, text))})
    for rel in VERIFY_ONLY:
        report['verification'].append(
            {'stage': 'verify-only',
             **verify_text(rel, corpus_for(rel, (ROOT / rel).read_text(encoding='utf-8')))})
    report['term_hits'] = dict(tz.hits.most_common())

    if args.apply:
        for rel, text in outputs.items():
            (ROOT / rel).write_text(text, encoding='utf-8')
        report['applied'] = True
    else:
        report['applied'] = False

    path = ROOT / args.report
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n',
                    encoding='utf-8')

    print(f'terms: {len(tz.rows)} rows, {tz.active} active,'
          f' {len(tz.table) - tz.active} shields')
    print(f'exercises: {stats["scalars"]} scalars, {stats["list_items"]} list items,'
          f' {stats["filled_missing"]} filled, {stats["pinned"]} pinned,'
          f' {len(stats["skipped"])} skipped')
    for rel, st in report['strings'].items():
        print(f'{rel}: {st["values_rewritten"]}/{st["keys_hant"]} values rewritten,'
              f' {st["from_old_hant"]} keys not in zh-Hans, +{len(st["added"])} added')
    for row in report['verification']:
        print(f'[{row["stage"]}] {row["file"]}: simplified {row["simplified_count"]}'
              f' latin {row["latin_total"]}')
    print('term hits:', dict(Counter(report['term_hits']).most_common(15)))
    print('report:', path, '| applied' if args.apply else '| dry run')


if __name__ == '__main__':
    main()
