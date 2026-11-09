#!/usr/bin/env python3
"""Rebuild the iPhone App Store deck as the Plan A six-slide story.

plan -> recovery -> training -> heart -> diet(+sleep) -> watch

One screen per page except diet/sleep. New headline + description copy is
written for zh / zh-Hant / en / ja only; the other eight locales keep the
closest previous slide's copy as a placeholder until the four-language
preview is approved.
"""
import copy
import json
import shutil

P = "design/app-store-studio-2026-10-29/app-store-screenshots.json"
shutil.copy(P, P + ".before-plan-a-20261108")

with open(P) as f:
    doc = json.load(f)

slides = doc["slidesByDevice"]["iphone"]
old = {s["id"]: s for s in slides}
LOCALES = doc["locales"]


def desc_element(slide):
    for te in slide.get("textElements", []):
        if te["id"] == "description":
            return te
    return None


SINGLE = {"x": 120, "y": 900, "width": 1080, "height": 2208.0, "rotation": 0, "zIndex": 3}
WATCH_SINGLE = {"x": 160, "y": 980, "width": 1000, "height": 1571.43, "rotation": -6, "zIndex": 3}

NEW = [
    {
        "id": "plan",
        "layout": "hero",
        "label": {"zh": "01 / 今日训练", "en": "01 / TODAY'S TRAINING"},
        "fallback": "photo",
        "screenshot": "/screenshots/localized/iphone/{locale}/plans.png",
        "secondary": None,
        "transforms": {
            "caption": {"x": 112, "y": 225, "width": 1096, "height": 545, "zIndex": 4},
            "device": SINGLE,
        },
        "headline": {
            "zh": "今天练什么，早就排好了",
            "zh-Hant": "今天練什麼，早就排好了",
            "en": "Know what to train today",
            "ja": "今日のメニューは決まってる",
        },
        "description": {
            "zh": "AI 教练读懂你的身体和目标，把这一周排好了。",
            "zh-Hant": "AI 教練讀懂你的身體和目標，把這一週排好了。",
            "en": "Your AI coach reads your body and goals, then plans the week.",
            "ja": "AIコーチが体と目標を読み取り、1週間のメニューを組みます。",
        },
    },
    {
        "id": "recovery",
        "layout": "hero",
        "label": {"zh": "02 / 肌肉恢复", "en": "02 / RECOVERY"},
        "fallback": "body",
        "screenshot": "/screenshots/localized/iphone/{locale}/muscle-selected.png",
        "secondary": None,
        "transforms": {
            "caption": {"x": 112, "y": 225, "width": 1096, "height": 545, "zIndex": 4},
            "device": SINGLE,
        },
        "headline": {
            "zh": "肌肉恢复，一眼看清",
            "zh-Hant": "肌肉恢復，一眼看清",
            "en": "See what has recovered",
            "ja": "筋肉の回復がひと目でわかる",
        },
        "description": {
            "zh": "3D 肌肉图显示每个部位的恢复状态，该练哪里一目了然。",
            "zh-Hant": "3D 肌肉圖顯示每個部位的恢復狀態，該練哪裡一目了然。",
            "en": "A live 3D muscle map shows what has recovered and what to train next.",
            "ja": "3Dの筋肉図で、回復した部位と次に鍛える部位がわかります。",
        },
    },
    {
        "id": "training",
        "layout": "hero",
        "label": {"zh": "03 / 专注训练", "en": "03 / TRAINING"},
        "fallback": "training",
        "screenshot": "/screenshots/localized/iphone/{locale}/training.png",
        "secondary": None,
        "transforms": {
            "caption": {"x": 112, "y": 225, "width": 1096, "height": 545, "zIndex": 4},
            "device": SINGLE,
        },
        "headline": {
            "zh": "每一组重量，都替你记下",
            "zh-Hant": "每一組重量，都替你記下",
            "en": "Every set and weight, logged",
            "ja": "セットと重量を自動で記録",
        },
        "description": {
            "zh": "组数、次数、重量自动累计，休息倒计时就在训练界面上。",
            "zh-Hant": "組數、次數、重量自動累計，休息倒數就在訓練介面上。",
            "en": "Sets, reps and weight add up as you go. Rest timer built in.",
            "ja": "セット・回数・重量を自動で記録。休憩タイマーも同じ画面に。",
        },
    },
    {
        "id": "heart",
        "layout": "hero",
        "label": {"zh": "04 / 心率提醒", "en": "04 / HEART RATE"},
        "fallback": "training",
        "screenshot": "/screenshots/localized/iphone/{locale}/workout-heart.png",
        "secondary": None,
        "transforms": {
            "caption": {"x": 112, "y": 225, "width": 1096, "height": 545, "zIndex": 4},
            "device": SINGLE,
        },
        "headline": {
            "zh": "心率过高，会提醒你缓一缓",
            "zh-Hant": "心率過高，會提醒你緩一緩",
            "en": "It tells you when to slow down",
            "ja": "心拍数が高すぎたら知らせます",
        },
        "description": {
            "zh": "训练时读取 Apple Watch 心率，持续超过你设定的上限就提醒。",
            "zh-Hant": "訓練時讀取 Apple Watch 心率，持續超過你設定的上限就提醒。",
            "en": "Live heart rate from Apple Watch. A nudge when it stays above your limit.",
            "ja": "Apple Watch の心拍数を表示。上限を超え続けると知らせます。",
        },
    },
    {
        "id": "diet",
        "layout": "two-devices",
        "label": {"zh": "05 / 饮食与睡眠", "en": "05 / NUTRITION & SLEEP"},
        "fallback": "diet",
        "screenshot": "/screenshots/localized/iphone/{locale}/diet.png",
        "secondary": "/screenshots/localized/iphone/{locale}/sleep.png",
        "transforms": copy.deepcopy(old["diet"]["transforms"]),
        "headline": {},
        "description": {},
    },
    {
        "id": "watch",
        "layout": "hero",
        "label": {"zh": "06 / 手表", "en": "06 / APPLE WATCH"},
        "fallback": "watch",
        "screenshot": "/screenshots/apple/iphone/watch-exercise-heart.png",
        "secondary": None,
        "transforms": {
            "caption": {"x": 112, "y": 225, "width": 1096, "height": 430, "zIndex": 4},
            "device": WATCH_SINGLE,
        },
        "headline": {},
        "description": {},
    },
]

built = []
for spec in NEW:
    fb = old[spec["fallback"]]
    fb_desc = desc_element(fb)
    headline = {}
    description = {}
    for loc in LOCALES:
        headline[loc] = spec["headline"].get(loc, fb["headline"][loc])
        description[loc] = spec["description"].get(loc, fb_desc["text"][loc])

    desc_block = copy.deepcopy(fb_desc) if fb_desc is not None else {
        "id": "description",
        "transform": {"x": 96, "y": 595, "width": 1128, "height": 140, "zIndex": 5},
        "fontSize": 41,
        "fontWeight": 400,
        "color": "#60625C",
        "align": "left",
    }
    desc_block["id"] = "description"
    desc_block["text"] = description

    slide = {
        "id": spec["id"],
        "layout": spec["layout"],
        "label": spec["label"],
        "headline": headline,
        "screenshot": spec["screenshot"],
        "inverted": True,
        "transforms": spec["transforms"],
        "textElements": [desc_block],
    }
    if spec["secondary"]:
        slide["screenshotSecondary"] = spec["secondary"]
    built.append(slide)

doc["slidesByDevice"]["iphone"] = built
doc["approvedLocales"] = ["zh", "zh-Hant", "en", "ja"]
doc["pendingLocales"] = [l for l in LOCALES if l not in doc["approvedLocales"]]

with open(P, "w") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")

print("slides:", [s["id"] for s in built])
for s in built:
    print(s["id"], s["transforms"]["device"], "secondary" in s["transforms"])
