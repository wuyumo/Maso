"""Rewrite slide 01 (AI Coach) to the approved "A 报告式" composition.

Two attached body photos -> one analysis reply -> three day rows -> the App's
"Save to My Routines" action. Content is the four approved locales; the other
eight keep English text via pickText fallback.

Run: python3 scripts/patch-plan-chat-a.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
FILE = ROOT / "app-store-screenshots.json"

LOCALES = ["zh", "zh-Hant", "en", "ja"]


def L(zh, zh_hant, en, ja):
    return dict(zip(LOCALES, [zh, zh_hant, en, ja]))


USER_TEXT = L(
    "帮我排个训练计划",
    "幫我排個訓練計畫",
    "Build me a training plan",
    "メニューを作って",
)
USER_META = L(
    "3 天 · 每次 45 分钟",
    "3 天 · 每次 45 分鐘",
    "3 days · 45 min each",
    "週3日 · 1回45分",
)
SAVE_CTA = L(
    "保存到我的训练计划",
    "儲存到我的訓練計畫",
    "Save to My Workout Plans",
    "マイプランに保存",
)

DAY3 = {
    "kicker": L("第 3 天", "第 3 天", "Day 3", "3日目"),
    "title": L("腿 + 核心", "腿 + 核心", "Legs + Core", "脚 + 体幹"),
    "meta": L("5 个动作 · 15 组", "5 個動作 · 15 組", "5 exercises · 15 sets", "5種目 · 15セット"),
    "muscles": ["legs", "core"],
    "pills": [
        {
            "part": L("腿", "腿", "Legs", "脚"),
            "name": L("杠铃深蹲", "槓鈴深蹲", "Back Squat", "バーベルスクワット"),
        },
        {
            "part": L("腿", "腿", "Legs", "脚"),
            "name": L("罗马尼亚硬拉", "羅馬尼亞硬舉", "Romanian Deadlift", "ルーマニアンデッドリフト"),
        },
        {
            "part": L("核心", "核心", "Core", "体幹"),
            "name": L("悬垂举腿", "懸垂舉腿", "Hanging Leg Raise", "レッグレイズ"),
        },
    ],
}


def main() -> None:
    data = json.loads(FILE.read_text(encoding="utf-8"))
    slide = data["slidesByDevice"]["iphone"][0]
    assert slide["id"] == "plan", slide["id"]
    chat = slide["chat"]
    user, coach = chat["bubbles"][0], chat["bubbles"][1]
    assert user["role"] == "user" and coach["role"] == "coach"

    # User turn: two attached photos, the short brief, the numbers underneath.
    user.pop("photo", None)
    user["photos"] = ["/chat/body-front.jpg", "/chat/body-back.jpg"]
    user["text"] = USER_TEXT
    user["subtext"] = USER_META

    # Coach turn: chips instead of the muscle diagram so the day rows fit.
    coach["report"]["compact"] = True
    coach["plans"] = coach["plans"][:2] + [DAY3]
    coach["rowCards"] = True
    coach["ctaAfterCards"] = True
    coach["cta"] = SAVE_CTA

    # The "ask me anything else" capsules belong to the old carousel layout; the
    # action pill now closes the thread.
    chat.pop("footnotes", None)

    FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("patched", FILE)


if __name__ == "__main__":
    main()
