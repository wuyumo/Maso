#!/usr/bin/env python3
"""i18n lint — 扫 Swift 代码里的 LocalizedStringKey 字面量, 跟 Localizable.strings 比对.

报告 3 类问题:
  1. Unregistered: swift 用了字面量但 Localizable.strings 没注册 → 所有语言看英文
  2. Missing translations: en.lproj 有但其它 lproj 没的 key → 该语言用户看英文
  3. Untranslated (warn): 翻译跟 English 一字不差 (品牌名除外)

用法:
    python3 scripts/lint_translations.py                  # 全 report
    python3 scripts/lint_translations.py --check          # CI 模式 (有问题 exit 1)
    python3 scripts/lint_translations.py --emit-missing   # 输出缺失 key 列表给 auto_translate.py
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT_ROOT = ROOT / "Maso"
RESOURCES = ROOT / "Maso/Resources"

LANGS = [
    "en", "zh-Hans", "zh-Hant", "ja", "ko",
    "es", "fr", "de", "it", "pt-BR", "ru", "ar",
]

# 提取 swift 字面量的 regex.
# 注意: 仅匹配 LocalizedStringKey 参数 (Text("..."), Button("..."), .navigationTitle("..."), 等).
# String 参数的 init (e.g. Text(stringVar)) 我们 grep 不到 — 这种用户得保证用 displayName / NSLocalizedString.
LOC_PATTERNS = [
    re.compile(r'\bText\(\s*"([^"\\]+)"\s*\)'),
    re.compile(r'\bButton\(\s*"([^"\\]+)"'),
    re.compile(r'\bLabel\(\s*"([^"\\]+)"\s*,\s*systemImage'),
    re.compile(r'\bToggle\(\s*"([^"\\]+)"'),
    re.compile(r'\bPicker\(\s*"([^"\\]+)"'),
    re.compile(r'\bTextField\(\s*"([^"\\]+)"'),
    re.compile(r'\bSecureField\(\s*"([^"\\]+)"'),
    re.compile(r'\bSection\(\s*"([^"\\]+)"'),
    re.compile(r'\bProgressView\(\s*"([^"\\]+)"'),
    re.compile(r'\bLabeledContent\(\s*"([^"\\]+)"'),
    re.compile(r'\.alert\(\s*"([^"\\]+)"'),
    re.compile(r'\.confirmationDialog\(\s*"([^"\\]+)"'),
    re.compile(r'\.navigationTitle\(\s*"([^"\\]+)"'),
    re.compile(r'\.accessibilityLabel\(\s*"([^"\\]+)"\s*\)'),
    re.compile(r'NSLocalizedString\(\s*"([^"\\]+)"'),
    re.compile(r'String\(format:\s*NSLocalizedString\(\s*"([^"\\]+)"'),
]

# 不需要翻译的字面量 — 品牌 / SF Symbol / a11y identifier
SKIP_LITERALS = {
    "MASSO", "Masso", "PRO",  # 品牌
    "exercise-set",         # accessibility identifier
    "XXXX-XXXX-XXXX",      # placeholder / storefront test input
    "from $2.50/mo", "FROM $2.50/MO",  # 营销硬编码
    "Active forever — thanks for buying.",  # subscription mock
    "·", "•", "—", "–", "✓", "🏆",  # 单符号 separator / icon, 不需翻
}

# Keep this aligned with printf-style formats used by Localizable.strings. Whitespace is not
# accepted before the conversion letter, so ordinary percentages like "45% / 55%" are ignored.
PRINTF_PATTERN = re.compile(
    r"%(?:\d+\$)?[-+#0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|z|t|j|L)?"
    r"(d|i|u|o|x|X|f|F|e|E|g|G|a|A|c|C|s|S|p|@|%)"
)


def format_arguments(value: str) -> list[str]:
    """Return format conversion types, allowing translators to reorder positional arguments."""
    return sorted(arg for arg in PRINTF_PATTERN.findall(value) if arg != "%")


def parse_strings(path: Path) -> dict:
    """解析 .strings 文件成 dict. 忽略 comment + 空行."""
    if not path.exists():
        return {}
    txt = path.read_text(encoding="utf-8")
    # 跳过 /* ... */ comments (line / block)
    txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.DOTALL)
    pattern = re.compile(r'"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"', re.MULTILINE)
    return dict(pattern.findall(txt))


def extract_swift_literals() -> tuple[set, dict]:
    """扫 swift 文件提取字面量. 返回 (set of literals, dict file→keys)."""
    literals: set[str] = set()
    file_keys: dict[str, set] = {}
    for swift in SWIFT_ROOT.rglob("*.swift"):
        txt = swift.read_text(encoding="utf-8")
        for pat in LOC_PATTERNS:
            for m in pat.findall(txt):
                m = m.strip()
                if not m or m in SKIP_LITERALS:
                    continue
                # 过滤 SF Symbol 名字 (e.g. "play.fill" — 但 ContentShape 这种不在 SF Symbol)
                if re.fullmatch(r'[\w]+(\.[\w]+)+', m):
                    # 多个 dot → 大概率 SF Symbol
                    continue
                if re.fullmatch(r'[\d.,\s%]+', m):
                    continue
                if any(c in m for c in ["://", "%@", "$0", "$1"]):
                    continue
                literals.add(m)
                rel = str(swift.relative_to(ROOT))
                file_keys.setdefault(rel, set()).add(m)
    return literals, file_keys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="CI mode — exit 1 if any unregistered / missing translations")
    parser.add_argument("--emit-missing", action="store_true",
                        help="Emit JSON: {lang: [missing keys]} for auto_translate.py")
    args = parser.parse_args()

    literals, file_keys = extract_swift_literals()
    en_strings = parse_strings(RESOURCES / "en.lproj/Localizable.strings")
    en_keys = set(en_strings.keys())

    # 1. Unregistered — swift 用了但 en.lproj 没注册
    unregistered = literals - en_keys

    # 2. Missing per language
    per_lang_missing = {}
    per_lang_untranslated = {}
    per_lang_placeholder_mismatch = {}
    for lang in LANGS:
        if lang == "en":
            continue
        strs = parse_strings(RESOURCES / f"{lang}.lproj/Localizable.strings")
        missing = sorted(en_keys - set(strs.keys()))
        per_lang_missing[lang] = missing
        placeholder_mismatch = []
        for key in en_keys & set(strs.keys()):
            placeholders_en = format_arguments(en_strings[key])
            placeholders_localized = format_arguments(strs[key])
            if placeholders_en != placeholders_localized:
                placeholder_mismatch.append(key)
        per_lang_placeholder_mismatch[lang] = sorted(placeholder_mismatch)
        # 译文跟 en 一字不差 — 可能是占位漏翻
        untranslated = sorted([
            k for k in en_keys
            if k in strs and strs[k] == en_strings[k] and k not in SKIP_LITERALS
        ])
        per_lang_untranslated[lang] = untranslated

    # --emit-missing → JSON 给 auto_translate.py
    if args.emit_missing:
        out = {
            "unregistered_in_en": sorted(unregistered),
            "missing_per_language": per_lang_missing,
        }
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0

    # Human-readable report
    print("=" * 70)
    print(f"i18n Audit Report — Masso")
    print("=" * 70)
    print(f"\nSwift literals scanned:      {len(literals)}")
    print(f"en.lproj registered keys:    {len(en_keys)}")
    print()

    has_issue = False

    if unregistered:
        has_issue = True
        print(f"🔴 UNREGISTERED ({len(unregistered)}) — swift 用了字面量但 en.lproj 没 key:")
        print("   (这些 string 在所有语言下都 fallback 字面量, 中文用户也看英文)")
        for s in sorted(unregistered):
            files = [f for f, ks in file_keys.items() if s in ks]
            print(f"  • {s!r}")
            for f in files[:2]:
                print(f"      ↳ {f}")
        print()

    total_missing = sum(len(v) for v in per_lang_missing.values())
    if total_missing > 0:
        has_issue = True
        print(f"🟡 MISSING TRANSLATIONS — en 有但其它 lproj 漏:")
        for lang, missing in per_lang_missing.items():
            if missing:
                print(f"  {lang}: {len(missing)} missing")
        print()
    else:
        print("✅ All languages have all en.lproj keys")

    total_placeholder_mismatch = sum(len(v) for v in per_lang_placeholder_mismatch.values())
    if total_placeholder_mismatch:
        has_issue = True
        print("🔴 PLACEHOLDER MISMATCH — translated strings must preserve format arguments:")
        for lang, keys in per_lang_placeholder_mismatch.items():
            if keys:
                print(f"  {lang}: {len(keys)} mismatched")
                for key in keys[:5]:
                    print(f"      • {key!r}")
        print()

    # The bundled exercise catalog is also localized data; check every map alongside UI copy.
    exercise_path = RESOURCES / "exercises.json"
    exercise_data = json.loads(exercise_path.read_text(encoding="utf-8"))
    exercise_fields = ("name", "instructions", "danger_warnings")
    exercise_missing = {lang: 0 for lang in LANGS if lang != "en"}
    for exercise in exercise_data:
        maps = [exercise.get(field) for field in exercise_fields]
        localized_base = (exercise.get("nameParts") or {}).get("localizedBase")
        if isinstance(localized_base, dict):
            maps.append(localized_base)
        for mapping in maps:
            if not isinstance(mapping, dict) or not mapping.get("en"):
                continue
            for lang in exercise_missing:
                if lang not in mapping or mapping[lang] in (None, "", []):
                    exercise_missing[lang] += 1
    total_exercise_missing = sum(exercise_missing.values())
    if total_exercise_missing:
        has_issue = True
        print("🟡 MISSING EXERCISE LOCALIZATIONS:")
        for lang, count in exercise_missing.items():
            if count:
                print(f"  {lang}: {count} missing localized exercise fields")
        print()
    else:
        print(f"✅ Exercise names, instructions and cautions are localized ({len(exercise_data)} records)")

    total_untranslated = sum(len(v) for v in per_lang_untranslated.values())
    if total_untranslated > 0:
        print(f"⚠️  UNTRANSLATED — 翻译值跟 English 一样 (大概率占位漏翻):")
        for lang, ut in per_lang_untranslated.items():
            if ut:
                print(f"  {lang}: {len(ut)} keys identical to English")
        print()

    print("=" * 70)
    if has_issue:
        print("Next step: run `python3 scripts/auto_translate.py` to fill missing.")
    else:
        print("All good ✓")

    if args.check and (unregistered or total_missing > 0 or total_placeholder_mismatch > 0 or total_exercise_missing > 0):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
