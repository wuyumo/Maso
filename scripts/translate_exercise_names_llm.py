#!/usr/bin/env python3
"""用 Anthropic Claude API 把 873 个动作名翻译到 ExerciseNames.strings.

替代 translate_exercise_names.py (keyword pattern 那个) — LLM 能正确处理
"Standing Bradford Press" 这种"姿势 + 人名 + 动作"的复合 entry, 不会因为
人名部分英文太多被 skip.

工作方式:
1. 读 exercises.json 拿 873 unique names
2. 读现有 {lang}.lproj/ExerciseNames.strings 拿已翻译的 keys (skip 不重翻)
3. 把 missing 的批量 (每批 30 个) 喂给 Claude 翻译
4. Append 翻译结果到 strings 文件

成本: Sonnet 4.5 — 873 names × ~30 tokens × $15/MTok output ≈ $0.40 全语言.
单语言 (zh-Hans) 约 $0.04.

用法:
    export ANTHROPIC_API_KEY=sk-ant-xxx
    pip install anthropic

    # 默认只翻译 zh-Hans (用户主要看)
    python3 scripts/translate_exercise_names_llm.py

    # 全 12 语言
    python3 scripts/translate_exercise_names_llm.py --all-langs

    # 只一个语言
    python3 scripts/translate_exercise_names_llm.py --lang ja

    # 干跑
    python3 scripts/translate_exercise_names_llm.py --dry-run
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JSON_PATH = ROOT / "Maso/Resources/exercises.json"

LANG_NAMES = {
    "zh-Hans": "Simplified Chinese (mainland China audience)",
    "zh-Hant": "Traditional Chinese (Taiwan / Hong Kong)",
    "ja": "Japanese",
    "ko": "Korean",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
    "it": "Italian",
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


def translate_batch(names: list[str], lang: str, lang_name: str) -> dict[str, str]:
    """一批 names (~30 个) 翻到指定语言."""
    from anthropic import Anthropic
    client = Anthropic()

    prompt = f"""You are translating fitness exercise names from English to {lang_name}.

Rules:
1. Output ONLY a JSON object: {{"<english name>": "<{lang} translation>"}}. No prose, no fences.
2. Keep brand / person names in original Latin script (e.g. "Bradford", "Rocky", "Zercher", "Arnold", "Bulgarian", "Romanian", "Carioca").
   Translate the rest of the name. Example: "Standing Bradford Press" → "站姿 Bradford 推举" (zh-Hans).
3. Keep equipment loanwords if standard in the target language (e.g. Japanese "バーベル" not "杠铃").
4. Use established fitness terminology of the target language audience.
5. Concise — names appear as chips/labels, keep them short.
6. Special cases:
   - "SMR" = self-myofascial release, translate as e.g. 中文"肌筋膜放松", 日本語"筋膜リリース"
   - "Pull-Up" / "Pullup" / "Pull Up" all mean the same — translate consistently
   - "Stretch" → 中文"拉伸", 日本語"ストレッチ"

Translate these {len(names)} exercise names:
{json.dumps({n: n for n in names}, ensure_ascii=False, indent=2)}

Output JSON:"""

    response = client.messages.create(
        model="claude-sonnet-4-5",
        max_tokens=8000,
        messages=[{"role": "user", "content": prompt}],
    )
    text = response.content[0].text.strip()
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"  ✗ JSON parse failed: {e}")
        print(f"     Raw: {text[:500]}")
        return {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", action="append", default=None,
                        help="只翻译指定语言. 可多次. 默认只 zh-Hans.")
    parser.add_argument("--all-langs", action="store_true",
                        help="覆盖 --lang, 翻译全部 11 个非英语 lproj")
    parser.add_argument("--batch-size", type=int, default=30,
                        help="每批 API call 的 names 数量 (默认 30, 大 = 快 / 小 = 稳)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--retranslate-all", action="store_true",
                        help="忽略已存在的翻译, 全 873 个重翻 (覆盖 keyword-based 旧翻译)")
    args = parser.parse_args()

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ERROR: export ANTHROPIC_API_KEY first")
        sys.exit(1)

    # 决定要翻的语言
    if args.all_langs:
        target_langs = list(LANG_NAMES.keys())
    elif args.lang:
        target_langs = args.lang
    else:
        target_langs = ["zh-Hans"]
    print(f"Target languages: {', '.join(target_langs)}")

    # 读 873 names
    with open(JSON_PATH) as f:
        exercises = json.load(f)
    all_names = sorted(set(e["name"] for e in exercises))
    print(f"Total exercise names: {len(all_names)}")

    for lang in target_langs:
        lang_name = LANG_NAMES.get(lang, lang)
        strings_path = ROOT / f"Maso/Resources/{lang}.lproj/ExerciseNames.strings"
        existing = parse_strings(strings_path) if not args.retranslate_all else {}

        missing = [n for n in all_names if n not in existing]
        print(f"\n[{lang}] {len(existing)} already translated, {len(missing)} missing")
        if not missing:
            print(f"  ✓ nothing to do")
            continue

        # 分批
        all_new: dict[str, str] = {}
        for i in range(0, len(missing), args.batch_size):
            batch = missing[i:i + args.batch_size]
            print(f"  [{lang}] batch {i // args.batch_size + 1}/{(len(missing) + args.batch_size - 1) // args.batch_size}"
                  f" ({len(batch)} names)…", flush=True)
            result = translate_batch(batch, lang, lang_name)
            # 只保留这一批 missing 的 key (LLM 偶尔 hallucinate)
            for n in batch:
                if n in result and result[n].strip():
                    all_new[n] = result[n].strip()
            # 显示 sample
            for k in list(batch)[:2]:
                tr = result.get(k, "?")
                print(f"      {k!r} → {tr!r}")

        print(f"  → got {len(all_new)} new translations (out of {len(missing)} missing)")

        if args.dry_run:
            print(f"  (dry-run, not writing)")
            continue

        # Append / 重写
        if args.retranslate_all:
            # 重写整个文件 — 用 LLM 翻译全部
            strings_path.parent.mkdir(parents=True, exist_ok=True)
            with strings_path.open("w", encoding="utf-8") as f:
                f.write(f'/* Auto-translated by translate_exercise_names_llm.py — {lang} */\n\n')
                for n in all_names:
                    tr = all_new.get(n, n).replace('\\', '\\\\').replace('"', '\\"')
                    n_safe = n.replace('\\', '\\\\').replace('"', '\\"')
                    f.write(f'"{n_safe}" = "{tr}";\n')
            print(f"  ✓ wrote {strings_path}")
        else:
            # Append 缺的
            with strings_path.open("a", encoding="utf-8") as f:
                f.write(f"\n/* LLM-translated missing names (translate_exercise_names_llm.py) */\n")
                for n in missing:
                    if n in all_new:
                        tr = all_new[n].replace('\\', '\\\\').replace('"', '\\"')
                        n_safe = n.replace('\\', '\\\\').replace('"', '\\"')
                        f.write(f'"{n_safe}" = "{tr}";\n')
            print(f"  ✓ appended to {strings_path.name}")


if __name__ == "__main__":
    main()
