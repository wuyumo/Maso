#!/usr/bin/env python3
"""Rewrite the iPhone Plan A deck from six pages to five.

plan → recovery → training(+Apple Watch) → progress → diet(+sleep)

The heart-rate page is merged into the training page (player screenshot with a live
bpm card) and the Apple Watch moves next to the phone on that same page, so the
separate heart and watch pages are removed. Only zh / zh-Hant / en / ja carry
approved copy; the other eight locales keep English placeholders and stay in
pendingLocales so they cannot be exported.

HISTORICAL MIGRATION — already applied on 2026-11-08. The deck has since moved on
(03 卖点改成「心率过高，立刻提醒」+ 185 bpm 告警态素材、01 去掉 CTA 改成横向计划卡、
05 改成扑克牌扇形)，re-running this file would clobber those revisions with the older
copy and the retired 160 bpm assets. It therefore refuses to write unless
PLAN_A_MIGRATE=1 is set explicitly.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DECK = ROOT / "design/app-store-studio-2026-10-29/app-store-screenshots.json"

import os
import sys

if os.environ.get("PLAN_A_MIGRATE") != "1":
    sys.exit(
        "plan_a_merge_heart.py is a historical migration; the deck now carries later "
        "revisions (reminder headline, 185 bpm assets, chat carousel, device fan). "
        "Re-run with PLAN_A_MIGRATE=1 only if you really mean to overwrite them."
    )

APPROVED = ["zh", "zh-Hant", "en", "ja"]
ALL = ["zh", "zh-Hant", "en", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "ar"]

CAPTION = {"x": 112, "y": 225, "width": 1096, "height": 545, "zIndex": 4}
DESC_BOX = {"x": 96, "y": 595, "width": 1128, "height": 140, "zIndex": 5}

TRAINING_HEADLINE = {
    "zh": "每一组重量，\n都替你记下",
    "zh-Hant": "每一組重量，\n都替你記下",
    "en": "Every set and rep,\nlogged",
    "ja": "セットと重量を\n自動で記録",
}
TRAINING_DESCRIPTION = {
    "zh": "组数、次数、重量自动累计，心率从 Apple Watch 实时同步。",
    "zh-Hant": "組數、次數、重量自動累計，心率從 Apple Watch 即時同步。",
    "en": "Sets, reps and weight add up as you go, with live heart rate from Apple Watch.",
    "ja": "セット・回数・重量を自動で記録。心拍数は Apple Watch からリアルタイムに。",
}

PROGRESS_HEADLINE = {
    "zh": "进步，\n是看得见的",
    "zh-Hant": "進步，\n是看得見的",
    "en": "Your lift history,\ntrending up",
    "ja": "種目ごとの伸びが、\n数字でわかる",
}
PROGRESS_DESCRIPTION = {
    "zh": "每个动作的重量和次数都留了记录，几周下来涨了多少一目了然。",
    "zh-Hant": "每個動作的重量和次數都留了記錄，幾週下來漲了多少一目了然。",
    "en": "Every lift keeps its history, so weeks of work show up as real numbers.",
    "ja": "種目ごとの重量と回数を記録。数週間の伸びが数字でわかります。",
}


def fill(text_by_locale):
    return {loc: text_by_locale.get(loc, text_by_locale["en"]) for loc in ALL}


def main():
    deck = json.loads(DECK.read_text())
    slides = deck["slidesByDevice"]["iphone"]
    by_id = {s["id"]: s for s in slides}

    plan, recovery, diet = by_id["plan"], by_id["recovery"], by_id["diet"]

    training = by_id["training"]
    training["label"] = {"zh": "03 / 训练与心率", "en": "03 / TRAINING & HEART RATE"}
    training["headline"] = fill(TRAINING_HEADLINE)
    training["screenshot"] = "/screenshots/localized/iphone/{locale}/player-heart-warning.png"
    training["screenshotSecondary"] = "/screenshots/localized/watch/{locale}/exercise-185.png"
    training["layout"] = "hero"
    training["transforms"] = {
        "caption": dict(CAPTION),
        # Phone on the left, Apple Watch beside it without covering the heart card.
        "device": {"x": 64, "y": 950, "width": 824, "height": 1684.8, "rotation": 0, "zIndex": 3},
        "deviceSecondary": {"x": 876, "y": 1456, "width": 436, "height": 685.14, "rotation": 0, "zIndex": 4},
    }
    training["textElements"] = [
        {
            "id": "description",
            "text": fill(TRAINING_DESCRIPTION),
            "transform": dict(DESC_BOX),
            "fontSize": 41,
            "fontWeight": 400,
            "color": "#B2B2B2",
            "align": "left",
        }
    ]

    progress = json.loads(json.dumps(by_id["heart"]))  # same page skeleton
    progress["id"] = "progress"
    progress["label"] = {"zh": "04 / 进步", "en": "04 / PROGRESS"}
    progress["headline"] = fill(PROGRESS_HEADLINE)
    progress["screenshot"] = "/screenshots/localized/iphone/{locale}/insights.png"
    progress.pop("screenshotSecondary", None)
    progress["layout"] = "hero"
    progress["transforms"] = {
        "caption": dict(CAPTION),
        "device": {"x": 120, "y": 900, "width": 1080, "height": 2208, "rotation": 0, "zIndex": 3},
    }
    progress["textElements"] = [
        {
            "id": "description",
            "text": fill(PROGRESS_DESCRIPTION),
            "transform": dict(DESC_BOX),
            "fontSize": 41,
            "fontWeight": 400,
            "color": "#60625C",
            "align": "left",
        }
    ]

    diet["label"] = {"zh": "05 / 饮食与睡眠", "en": "05 / NUTRITION & SLEEP"}

    deck["slidesByDevice"]["iphone"] = [plan, recovery, training, progress, diet]
    deck["approvedLocales"] = list(APPROVED)
    deck["pendingLocales"] = [loc for loc in ALL if loc not in APPROVED]
    DECK.write_text(json.dumps(deck, ensure_ascii=False, indent=1) + "\n")
    print("slides:", [s["id"] for s in deck["slidesByDevice"]["iphone"]])
    print("approved:", deck["approvedLocales"], "pending:", deck["pendingLocales"])


if __name__ == "__main__":
    main()
