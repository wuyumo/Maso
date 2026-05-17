#!/usr/bin/env python3
"""用 Anthropic Claude API 把 873 个动作的 verbose instructions 提炼成 2-3 个简短要点.

输入: Maso/Resources/exercises.json 的 instructions (原 yuhonas 数据, 每条 80-250 字符英文)
输出: Maso/Resources/{lang}.lproj/ExerciseInstructions.strings — 跟 ExerciseNames 同模式
      key = exercise.name (英文 raw, 跟 ExerciseNames 用同一个 key)
      value = "Step 1\nStep 2\nStep 3"  (\n 分隔的 2-3 个精简步骤)

工作方式:
1. 读 exercises.json 拿 873 unique entries (name + instructions)
2. 读现有 {lang}.lproj/ExerciseInstructions.strings 拿已生成的 key (skip)
3. 把 missing 的批量喂给 Claude — 一次 batch 处理多条, 输出 JSON
4. Append 到 strings 文件

成本: Sonnet 4.5 — 873 × ~200 tokens input + ~50 tokens output ≈ $0.50 / 语言

用法:
    export ANTHROPIC_API_KEY=sk-ant-xxx
    pip install anthropic

    # 先生成英文 master (用 LLM 浓缩英文 verbose instructions)
    python3 scripts/simplify_instructions_llm.py --lang en

    # 再翻译到其他语言 (跟 translate_exercise_names_llm.py 同 pattern)
    python3 scripts/simplify_instructions_llm.py --lang zh-Hans
    python3 scripts/simplify_instructions_llm.py --all-langs

    # 干跑
    python3 scripts/simplify_instructions_llm.py --lang zh-Hans --dry-run
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
    "en": "English (concise, beginner-friendly)",
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
    # 多行 value 用 \n 转义, 这里按行匹配
    pattern = re.compile(r'"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"', re.MULTILINE)
    return dict(pattern.findall(txt))


def simplify_batch(items: list[dict], lang: str, lang_name: str) -> dict[str, str]:
    """一批 exercises (name + instructions) → 简化版 i18n strings.

    输出 dict: { exercise.name: "Step1\\nStep2\\nStep3" }
    """
    from anthropic import Anthropic
    client = Anthropic()

    # 给 LLM 看的输入: name + raw instructions
    payload = {
        item["name"]: item["instructions"][:5]  # 最多 5 条原文, 防 token 爆炸
        for item in items
    }

    prompt = f"""You're rewriting fitness exercise instructions to be concise and beginner-friendly in {lang_name}.

For each exercise, output 2-3 short steps capturing only the ESSENTIAL motion. Each step must:
- Be ≤ 60 characters (target language)
- Use imperative voice ("Lie on bench", not "You should lie on the bench")
- Skip generic advice (breathing, "go slow", "control the movement", warmup hints)
- Keep equipment / body part names that matter for the motion

Output ONLY a JSON object: {{"<english name>": "<step1>\\n<step2>\\n<step3>"}}.
No prose, no fences. Use literal \\n between steps.

Example:
Input:
  "Bench Press": [
    "Lie back on a flat bench. Using a medium width grip (a grip that creates a 90-degree angle in the middle of the movement between the forearms and the upper arms), lift the bar from the rack and hold it straight over you with your arms locked.",
    "From the starting position, breathe in and begin coming down slowly until the bar touches your middle chest.",
    "After a brief pause, push the bar back to the starting position as you breathe out and push through your feet for greater leverage."
  ]
Output (English):
  {{"Bench Press": "Lie on bench, grip bar shoulder-width.\\nLower bar to mid-chest.\\nPush back up to lockout."}}

Translate these {len(items)} exercises:
{json.dumps(payload, ensure_ascii=False, indent=2)}

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
                        help="只生成指定语言. 可多次. 默认 en (master).")
    parser.add_argument("--all-langs", action="store_true",
                        help="覆盖 --lang, 生成全部 12 个语言")
    parser.add_argument("--batch-size", type=int, default=20,
                        help="每批 API call 的 exercises 数量 (instructions 比 names 长, 默认 20)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=None,
                        help="只处理前 N 个 (dev 测试用)")
    args = parser.parse_args()

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ERROR: export ANTHROPIC_API_KEY first")
        sys.exit(1)

    if args.all_langs:
        target_langs = list(LANG_NAMES.keys())
    elif args.lang:
        target_langs = args.lang
    else:
        target_langs = ["en"]
    print(f"Target languages: {', '.join(target_langs)}")

    # 读 873 exercises (含 instructions)
    with open(JSON_PATH) as f:
        exercises = json.load(f)
    # dedupe 按 name
    seen_names = set()
    unique_exercises = []
    for ex in exercises:
        if ex["name"] not in seen_names:
            seen_names.add(ex["name"])
            unique_exercises.append(ex)
    if args.limit:
        unique_exercises = unique_exercises[:args.limit]
    print(f"Total unique exercises with instructions: {len(unique_exercises)}")

    for lang in target_langs:
        lang_name = LANG_NAMES.get(lang, lang)
        strings_path = ROOT / f"Maso/Resources/{lang}.lproj/ExerciseInstructions.strings"
        existing = parse_strings(strings_path)

        missing = [ex for ex in unique_exercises if ex["name"] not in existing]
        print(f"\n[{lang}] {len(existing)} already generated, {len(missing)} missing")
        if not missing:
            print(f"  ✓ nothing to do")
            continue

        all_new: dict[str, str] = {}
        n_batches = (len(missing) + args.batch_size - 1) // args.batch_size
        for i in range(0, len(missing), args.batch_size):
            batch = missing[i:i + args.batch_size]
            print(f"  [{lang}] batch {i // args.batch_size + 1}/{n_batches}"
                  f" ({len(batch)} exercises)…", flush=True)
            result = simplify_batch(batch, lang, lang_name)
            for ex in batch:
                if ex["name"] in result and result[ex["name"]].strip():
                    all_new[ex["name"]] = result[ex["name"]].strip()
            # 显示 sample
            for ex in batch[:1]:
                tr = result.get(ex["name"], "?")
                preview = tr.replace("\n", " | ") if isinstance(tr, str) else "?"
                print(f"      {ex['name']!r} → {preview[:100]}{'…' if len(preview) > 100 else ''}")

        print(f"  → got {len(all_new)} new entries (out of {len(missing)} missing)")

        if args.dry_run:
            print(f"  (dry-run, not writing)")
            continue

        # Append
        strings_path.parent.mkdir(parents=True, exist_ok=True)
        mode = "a" if strings_path.exists() else "w"
        with strings_path.open(mode, encoding="utf-8") as f:
            if mode == "w":
                f.write(f'/* Simplified instructions, LLM-generated by simplify_instructions_llm.py — {lang} */\n\n')
            else:
                f.write(f"\n/* LLM-generated batch (simplify_instructions_llm.py) */\n")
            for ex in missing:
                if ex["name"] in all_new:
                    # 转义 quotes / backslashes; 保留 \n (literal escape in .strings file)
                    val = all_new[ex["name"]]
                    val_safe = val.replace('\\', '\\\\').replace('"', '\\"')
                    # \\n 已经在上一步被双重转义成 \\\\n, 需要复原成 .strings 的 \n
                    val_safe = val_safe.replace('\\\\n', '\\n')
                    n_safe = ex["name"].replace('\\', '\\\\').replace('"', '\\"')
                    f.write(f'"{n_safe}" = "{val_safe}";\n')
        print(f"  ✓ wrote/appended to {strings_path}")


if __name__ == "__main__":
    main()
