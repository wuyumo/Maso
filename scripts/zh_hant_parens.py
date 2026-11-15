#!/usr/bin/env python3
"""Normalise half-width parentheses around Chinese text in the zh-Hant resources.

Taiwan typography inside a Chinese sentence uses full-width （）. A group is
converted when either

  * the text inside the pair contains a Han character
    (「羅馬尼亞式(屈髖直膝)」 -> 「羅馬尼亞式（屈髖直膝）」), or
  * the character right before "(" is Han and the pair only holds format
    specifiers (「每週累計舉起重量(%@)」 -> 「…（%@）」).

Groups that sit next to Latin text only — 「重量 (kg)」, 「Last: %@ kg × %d (%@)」
— are left alone: the space is the separator and both halves are Latin.

Usage:
  python3 scripts/zh_hant_parens.py            # rewrite the four zh-Hant files
  python3 scripts/zh_hant_parens.py --check    # report only, non-zero if dirty
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

CJK_RE = re.compile(r"[\u3400-\u9fff]")
SPACE_BEFORE_WIDE = re.compile(r"(?<=\S) +(?=（)")
SPACE_AFTER_WIDE = re.compile(r"(?<=）) +(?=[\u3400-\u9fff—，。、！？：；])")


def tidy(text: str) -> str:
    """Drop the stray space a full-width group does not need around it."""
    return SPACE_AFTER_WIDE.sub("", SPACE_BEFORE_WIDE.sub("", text))


TARGETS = [
    "Maso/Resources/zh-Hant.lproj/Localizable.strings",
    "Maso/Resources/zh-Hant.lproj/InfoPlist.strings",
    "MasoWidgets/zh-Hant.lproj/Localizable.strings",
    "MasoWatch/zh-Hant.lproj/Localizable.strings",
]


OPENERS = {"(": ")", "（": "）"}
CLOSERS = {")", "）"}


def balance(text: str) -> str:
    """Make every pair match its opener (「（…）」 stays, 「（…)」 becomes 「（…）」)."""
    out = list(text)
    stack: list[str] = []
    for index, char in enumerate(text):
        if char in OPENERS:
            stack.append(char)
        elif char in CLOSERS and stack:
            opener = stack.pop()
            out[index] = OPENERS[opener]
    return "".join(out)


def convert(text: str) -> str:
    out = list(text)
    stack: list[int] = []
    for index, char in enumerate(text):
        if char == "(":
            stack.append(index)
        elif char == ")" and stack:
            start = stack.pop()
            inside = text[start + 1:index]
            before = text[start - 1] if start else ""
            specifiers_only = not re.sub(r"%[@dfsu]|[\s\d.]", "", inside)
            if CJK_RE.search(inside) or (CJK_RE.search(before or " ") and specifiers_only):
                out[start] = "（"
                out[index] = "）"
    return "".join(out)


def main() -> int:
    check = "--check" in sys.argv[1:]
    root = Path(__file__).resolve().parents[1]
    dirty = 0
    for rel in TARGETS:
        path = root / rel
        if not path.exists():
            print("missing", rel)
            continue
        before = path.read_text()
        after = tidy(convert(balance(before)))
        if before == after:
            print("ok   ", rel)
            continue
        dirty += 1
        if check:
            print("dirty", rel)
        else:
            path.write_text(after)
            print("fixed", rel)
    if check and dirty:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
