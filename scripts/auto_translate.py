#!/usr/bin/env python3
"""i18n auto-translate — 用 Anthropic Claude API 把 en.lproj 的 key 自动翻译到其它 11 个语言.

工作流:
1. 跑 `python3 scripts/lint_translations.py --emit-missing` 拿 missing key list
2. 跑这个脚本: `python3 scripts/auto_translate.py`
3. Review diff: `git diff Maso/Resources/*.lproj/`
4. Build + test: `xcodebuild ...`

需要:
    export ANTHROPIC_API_KEY=sk-ant-xxx
    pip install anthropic

或者用 OpenAI (用 --backend openai + OPENAI_API_KEY).

成本估算:
    Claude Sonnet 4 — 约 $3/MTok input, $15/MTok output
    24 missing keys × 11 langs × 平均 30 tokens output = ~8K tokens 总 = $0.12
    实际上 prompt + output 加起来不到 $1, 不用心疼.

用法:
    # 用 anthropic claude (推荐, 翻译质量高)
    export ANTHROPIC_API_KEY=sk-ant-xxx
    python3 scripts/auto_translate.py

    # 干跑看会改啥不写入
    python3 scripts/auto_translate.py --dry-run

    # 指定语言 (默认全部)
    python3 scripts/auto_translate.py --lang ja --lang ko
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Maso/Resources"

LANG_NAMES = {
    "zh-Hans": "Simplified Chinese (mainland China audience)",
    "zh-Hant": "Traditional Chinese (Taiwan / Hong Kong audience)",
    "ja": "Japanese (Japan audience)",
    "ko": "Korean (Korea audience)",
    "es": "Spanish (Spain / Latin America)",
    "fr": "French (France)",
    "de": "German (Germany)",
    "it": "Italian (Italy)",
    "pt-BR": "Brazilian Portuguese",
    "ru": "Russian",
    "ar": "Arabic",
}


def parse_strings(path: Path) -> dict:
    if not path.exists():
        return {}
    txt = path.read_text(encoding="utf-8")
    txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.DOTALL)
    pattern = re.compile(r'"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"', re.MULTILINE)
    return dict(pattern.findall(txt))


def call_lint_for_missing() -> dict:
    """跑 lint_translations.py --emit-missing 拿 JSON."""
    result = subprocess.run(
        ["python3", str(ROOT / "scripts/lint_translations.py"), "--emit-missing"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print("lint_translations.py failed:")
        print(result.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def translate_anthropic(keys: list[str], lang: str, lang_name: str) -> dict[str, str]:
    """用 Anthropic Claude 翻译一批 key 到指定语言. 返回 {key: translation}."""
    try:
        from anthropic import Anthropic
    except ImportError:
        print("ERROR: pip install anthropic")
        sys.exit(1)

    client = Anthropic()  # 自动读 ANTHROPIC_API_KEY env

    # 构造 prompt — 让 Claude 输出 JSON, 严格按 input order, 不解释.
    prompt = f"""You are translating UI strings for a fitness mobile app called "Maso".
Target language: {lang_name}.

Rules:
1. Output ONLY a JSON object. No prose, no markdown fences, just JSON.
2. Keep placeholders intact: %@, %d, %lld, %.1f, etc.
3. Keep brand names untranslated: Maso, MASO.
4. Match the tone of a friendly fitness app — concise, energetic, not formal.
5. Keep punctuation conventions of the target language (e.g. Chinese 。, French «», Arabic RTL).
6. If a string is a short button label, keep it short in translation.

Translate these {len(keys)} strings:
{json.dumps({k: k for k in keys}, ensure_ascii=False, indent=2)}

Output JSON: {{"<english>": "<{lang} translation>", ...}}"""

    response = client.messages.create(
        model="claude-sonnet-4-5",
        max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
    )
    text = response.content[0].text.strip()
    # 兼容 Claude 偶尔输出 ```json fence
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"  ✗ JSON parse failed for {lang}: {e}")
        print(f"     Raw response: {text[:500]}")
        return {}


def translate_openai(keys: list[str], lang: str, lang_name: str) -> dict[str, str]:
    try:
        from openai import OpenAI
    except ImportError:
        print("ERROR: pip install openai")
        sys.exit(1)
    client = OpenAI()  # 读 OPENAI_API_KEY

    prompt = f"""Translate these fitness app UI strings to {lang_name}.

Rules:
- Output ONLY a JSON object, no other text.
- Keep placeholders intact: %@, %d, %lld, %.1f.
- Keep brand names "Maso" / "MASO" untranslated.
- Concise & friendly tone (fitness app for everyday users).
- Match target language punctuation conventions.

Strings to translate ({len(keys)} total):
{json.dumps({k: k for k in keys}, ensure_ascii=False, indent=2)}

Output JSON: {{"english_key": "translation"}}"""

    resp = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
    )
    text = resp.choices[0].message.content
    return json.loads(text)


def append_to_strings_file(path: Path, translations: dict[str, str], header_comment: str):
    """把 translations append 到 .strings 文件. 不去重 — caller 确保 key 不存在."""
    lines = ["", f"/* {header_comment} */"]
    for en, tr in translations.items():
        # 转义 " 和 \
        tr_safe = tr.replace("\\", "\\\\").replace('"', '\\"')
        en_safe = en.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'"{en_safe}" = "{tr_safe}";')
    with path.open("a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", choices=["anthropic", "openai"], default="anthropic",
                        help="LLM backend (default: anthropic / Claude)")
    parser.add_argument("--lang", action="append", default=None,
                        help="只翻译指定语言 (可多次), 默认全部")
    parser.add_argument("--dry-run", action="store_true",
                        help="只打印翻译, 不写入文件")
    args = parser.parse_args()

    # 检查 API key
    key_env = "ANTHROPIC_API_KEY" if args.backend == "anthropic" else "OPENAI_API_KEY"
    if not os.environ.get(key_env):
        print(f"ERROR: export {key_env} first")
        sys.exit(1)

    # 拿 missing keys
    audit = call_lint_for_missing()
    missing_per_lang = audit["missing_per_language"]

    target_langs = args.lang or sorted(missing_per_lang.keys())
    print(f"Backend: {args.backend}")
    print(f"Target languages: {', '.join(target_langs)}")
    print()

    translate_fn = translate_anthropic if args.backend == "anthropic" else translate_openai
    total_translated = 0

    for lang in target_langs:
        missing = missing_per_lang.get(lang, [])
        if not missing:
            print(f"[{lang}] no missing keys, skip")
            continue
        lang_name = LANG_NAMES.get(lang, lang)
        print(f"[{lang}] {len(missing)} missing → translating to {lang_name}…")

        translations = translate_fn(missing, lang, lang_name)
        if not translations:
            print(f"  ✗ skipped (empty/failed)")
            continue

        # 打印 sample
        for en in list(missing)[:3]:
            tr = translations.get(en, "?")
            print(f"    {en!r} → {tr!r}")
        if len(missing) > 3:
            print(f"    ... +{len(missing) - 3} more")

        if args.dry_run:
            print(f"  (dry-run, not writing)")
            continue

        path = RESOURCES / f"{lang}.lproj/Localizable.strings"
        # 只 append 实际拿到的 translation (跳过 LLM 漏的)
        actual = {k: v for k, v in translations.items() if k in missing}
        append_to_strings_file(
            path, actual,
            header_comment=f"Auto-translated by scripts/auto_translate.py ({args.backend})",
        )
        print(f"  ✓ appended {len(actual)} keys to {path.name}")
        total_translated += len(actual)
        print()

    print(f"\nTotal: {total_translated} translations added")
    if not args.dry_run and total_translated > 0:
        print("\nNext: review with `git diff Maso/Resources/*.lproj/Localizable.strings`")
        print("      build:  `xcodebuild ... build`")


if __name__ == "__main__":
    main()
