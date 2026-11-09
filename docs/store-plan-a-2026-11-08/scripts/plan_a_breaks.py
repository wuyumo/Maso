#!/usr/bin/env python3
"""Bake deliberate CJK line breaks into the Plan A headlines.

CJK has no word boundaries, so `text-wrap: balance` alone can split a word in
half (「掌／握」). Every zh / zh-Hant / ja headline therefore carries an explicit
newline at the intended clause break; the accent phrase never spans it.
"""
import json

P = "design/app-store-studio-2026-10-29/app-store-screenshots.json"

FIXES = {
    "plan": {
        "zh": "今天练什么，\n早就排好了",
        "zh-Hant": "今天練什麼，\n早就排好了",
        "ja": "今日のメニューは\n決まってる",
    },
    "recovery": {
        "zh": "肌肉恢复，\n一眼看清",
        "zh-Hant": "肌肉恢復，\n一眼看清",
        "ja": "筋肉の回復が\nひと目でわかる",
    },
    "training": {
        "zh": "每一组重量，\n都替你记下",
        "zh-Hant": "每一組重量，\n都替你記下",
        "ja": "セットと重量を\n自動で記録",
    },
    "heart": {
        "zh": "心率过高，\n会提醒你缓一缓",
        "zh-Hant": "心率過高，\n會提醒你緩一緩",
        "ja": "心拍数が高すぎたら\n知らせます",
    },
    "diet": {
        "ja": "食事と睡眠を\nまとめて管理",
    },
    "watch": {
        "zh": "抬腕，\n就能完成这一组",
        "zh-Hant": "抬腕，\n就能完成這一組",
        "ja": "手首から\n次のセットを記録",
    },
}

with open(P) as f:
    doc = json.load(f)

for slide in doc["slidesByDevice"]["iphone"]:
    for loc, value in FIXES.get(slide["id"], {}).items():
        assert "\n" in value, (slide["id"], loc)
        slide["headline"][loc] = value
        print(f'{slide["id"]:9s} {loc:8s} {value!r}')

with open(P, "w") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("done")
