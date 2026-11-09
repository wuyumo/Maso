#!/usr/bin/env python3
"""Generate a self-contained local gallery for the App Store screenshots.

Reads slide copy from the approved Studio state so captions cannot drift from
the shipped posters, and points at the existing exported PNGs in place.
"""
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
BATCH = ROOT / "docs/store-all-refresh-2026-11-06"
STATE = BATCH / "approved-studio-state.json"
PROJECT = ROOT / "design/app-store-studio-2026-10-29/app-store-screenshots.json"

LOCALES = [
    ("en", "English"),
    ("zh", "简体中文"),
    ("zh-Hant", "繁體中文"),
    ("ja", "日本語"),
    ("ko", "한국어"),
    ("es", "Español"),
    ("fr", "Français"),
    ("de", "Deutsch"),
    ("it", "Italiano"),
    ("pt-BR", "Português"),
    ("ru", "Русский"),
    ("ar", "العربية"),
]

DEVICES = [
    {
        "id": "iphone",
        "name": "iPhone 6.9″",
        "spec": "1320 × 2868",
        "dir": "iphone/1320x2868",
        "width": 1320,
        "height": 2868,
        "count": 6,
        "note": "App Store 主截图",
    },
    {
        "id": "iphone-medium",
        "name": "iPhone 6.3″",
        "spec": "1206 × 2622",
        "dir": "iphone-medium/1206x2622",
        "width": 1206,
        "height": 2622,
        "count": 6,
        "note": "中等尺寸等比导出",
    },
    {
        "id": "ipad",
        "name": "iPad 13″",
        "spec": "2064 × 2752",
        "dir": "ipad/2064x2752",
        "width": 2064,
        "height": 2752,
        "count": 6,
        "note": "原生 iPad 截图",
    },
    {
        "id": "duo",
        "name": "Duo",
        "spec": "2007 × 2853",
        "dir": "duo/2007x2853",
        "width": 2007,
        "height": 2853,
        "count": 6,
        "note": "折叠屏内屏",
    },
    {
        "id": "watch",
        "name": "Watch 46mm",
        "spec": "416 × 496",
        "dir": "watch/416x496",
        "width": 416,
        "height": 496,
        "count": 2,
        "note": "原生表盘截图，无营销文案",
    },
]

SLIDE_FILES = [
    ("body", "01-two-devices.png", "two-devices"),
    ("photo", "02-two-devices.png", "two-devices"),
    ("training", "03-hero.png", "hero"),
    ("library", "04-two-devices.png", "two-devices"),
    ("diet", "05-two-devices.png", "two-devices"),
    ("watch", "06-two-devices.png", "two-devices"),
]

PLAN_A_SLIDE_FILES = [
    ("plan", "01-plan.png", "hero"),
    ("recovery", "02-recovery.png", "hero"),
    ("training", "03-training.png", "hero"),
    ("diet", "04-diet.png", "two-devices"),
    ("devices", "05-devices.png", "multi-device"),
]

WATCH_SLIDES = [
    {
        "id": "watch-set",
        "file": "01-hero.png",
        "headline": {
            "en": "Log your next set from your wrist",
            "zh": "抬腕，就能完成这一组",
            "zh-Hant": "抬腕，就能完成這一組",
            "ja": "手首から次のセットを記録",
            "ko": "손목에서 바로 세트를 완료하세요",
            "es": "Registra tu siguiente serie desde la muñeca",
            "fr": "Enregistrez votre série au poignet",
            "de": "Erfasse deinen nächsten Satz am Handgelenk",
            "it": "Registra la prossima serie dal polso",
            "pt-BR": "Registre a próxima série no pulso",
            "ru": "Запишите подход прямо с запястья",
            "ar": "سجّل مجموعتك التالية من معصمك",
        },
        "description": {
            "en": "Reps are already filled in — one tap closes the set.",
            "zh": "次数已预填，一按即完成。",
        },
    },
    {
        "id": "watch-rest",
        "file": "02-hero.png",
        "headline": {
            "en": "Rest that knows what comes next",
            "zh": "休息倒计时，下一组就在眼前",
            "zh-Hant": "休息倒數，下一組就在眼前",
            "ja": "休憩中でも次のセットが分かる",
            "ko": "휴식 중에도 다음 세트가 보입니다",
            "es": "El descanso sabe qué viene después",
            "fr": "La récupération sait ce qui suit",
            "de": "Die Pause kennt den nächsten Satz",
            "it": "Il riposo sa cosa arriva dopo",
            "pt-BR": "O descanso já mostra a próxima série",
            "ru": "Отдых знает следующий подход",
            "ar": "الراحة تعرف مجموعتك التالية",
        },
        "description": {
            "en": "Timer, next set and skip — all on one screen.",
            "zh": "倒计时、下一组与跳过休息，一屏完成。",
        },
    },
]


def build_slides(state_path, slide_files):
    state = json.loads(state_path.read_text())
    by_id = {s["id"]: s for s in state["slidesByDevice"]["iphone"]}
    slides = []
    for sid, filename, layout in slide_files:
        src = by_id[sid]
        desc = {}
        for element in src.get("textElements", []):
            if element.get("id") == "description":
                desc = element.get("text", {})
        slides.append(
            {
                "id": sid,
                "file": filename,
                "layout": layout,
                "label": src.get("label", {}),
                "headline": src.get("headline", {}),
                "description": desc,
            }
        )
    return slides


def attach_shas(batch):
    """Bind each poster to the bytes on disk. A new export gets a new SHA."""
    base = (pathlib.Path(__file__).parent / batch["dir"]).resolve()
    by_device = {device["id"]: device for device in DEVICES}
    per = batch.get("perDevice") or {}
    shas = {}
    for dev_id in batch["devices"]:
        dev = by_device[dev_id]
        slides = per.get(dev_id) or batch["slides"]
        for loc in batch["locales"]:
            for slide in slides:
                path = base / dev["dir"] / loc / slide["file"]
                key = f"{dev_id}/{loc}/{slide['file']}"
                shas[key] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    batch["shas"] = shas


def main():
    plan_a = build_slides(PROJECT, PLAN_A_SLIDE_FILES)
    # The Plan A deck has no iPad counterpart for 03 (it is a phone + watch page),
    # so the 13" iPad posters are the same slides minus that one.
    plan_a_ipad = [slide for slide in plan_a if slide["id"] != "training"]
    all_devices = [d["id"] for d in DEVICES]
    all_locales = [code for code, _ in LOCALES]
    batches = [
        {"id": "review", "label": "11-09 审阅稿（未上传）", "dir": "../store-review-2026-11-09/exported/ios/",
         "note": "12 语草稿，供审阅，不是上传批准。Duo 机身是本仓库 Night Sky 框的中性黑适配，不是单独的官方黑色色款文件。缺内屏的页在图内标 NO CAPTURE，画廊缺文件则显示「缺图」。旧 Plan A 的 04/05 仍在下一档，未被覆盖。",
         "slides": plan_a, "perDevice": {"ipad": plan_a_ipad}, "watchSlides": [],
         "devices": ["iphone", "ipad"],
         "locales": all_locales, "v": "20261109t161"},
        {"id": "plana", "label": "11-08 Plan A 预览", "dir": "../store-plan-a-2026-11-08/exported/ios/",
         "note": "改版前的 Plan A 导出。本快照只带了 en/zh 的 04 与 05，其余页在画廊里显示缺图，避免把审阅稿说成已覆盖旧批次。",
         "slides": plan_a, "perDevice": {"ipad": plan_a_ipad}, "watchSlides": [],
         "devices": ["iphone", "ipad"],
         "locales": ["zh", "zh-Hant", "en", "ja"], "v": "20261109c"},
    ]
    if STATE.exists():
        legacy = build_slides(STATE, SLIDE_FILES)
        batches.extend([
            {"id": "new", "label": "11-08 调整版", "dir": "../store-refresh-2026-11-08/exported/ios/",
             "note": "文案放大 + 演示机位下移，尚未上传 App Store Connect",
             "slides": legacy, "watchSlides": WATCH_SLIDES, "devices": all_devices, "locales": all_locales},
            {"id": "live", "label": "11-06 已上传", "dir": "../store-all-refresh-2026-11-06/exported/ios/",
             "note": "当前 App Store Connect 上的线上版本",
             "slides": legacy, "watchSlides": WATCH_SLIDES, "devices": all_devices, "locales": all_locales},
        ])
    for batch in batches:
        attach_shas(batch)
    data = {"locales": LOCALES, "devices": DEVICES, "batches": batches}
    payload = json.dumps(data, ensure_ascii=False, indent=1)

    html = TEMPLATE.replace("__DATA__", payload)
    out = pathlib.Path(__file__).with_name("index.html")
    out.write_text(html)
    print(f"wrote {out} ({out.stat().st_size/1024:.1f} KB)")


TEMPLATE = r"""<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Masso · App Store 截图</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='8' fill='%230e1512'/%3E%3Cpath d='M7 22.5V13l4.4 5.4L15.8 13v9.5M19.5 22.5l3-9.5 3 9.5' fill='none' stroke='%231ed760' stroke-width='2.3' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E">
<style>
  :root{
    --bg:#09090a;
    --panel:#101012;
    --line:rgba(255,255,255,.08);
    --line-strong:rgba(255,255,255,.16);
    --fg:#f2f3f2;
    --muted:rgba(242,243,242,.52);
    --faint:rgba(242,243,242,.32);
    --accent:#1ed760;
    --mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,monospace;
    --radius:14px;
  }
  *{box-sizing:border-box}
  html,body{margin:0;height:100%}
  body{
    overflow-x:clip;
    background:var(--bg);
    color:var(--fg);
    font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue","PingFang SC","Hiragino Sans",sans-serif;
    -webkit-font-smoothing:antialiased;
    text-rendering:optimizeLegibility;
  }
  body::before{
    content:"";
    position:fixed; inset:0 0 auto 0; height:420px; pointer-events:none;
    background:radial-gradient(900px 340px at 24% -12%, rgba(30,215,96,.16), transparent 72%);
    z-index:0;
  }
  button{font:inherit;color:inherit;background:none;border:0;cursor:pointer}
  ::selection{background:rgba(30,215,96,.28)}

  /* ---------- header ---------- */
  header{
    position:sticky; top:0; z-index:40;
    padding:20px 32px 0;
    background:linear-gradient(180deg, rgba(9,9,10,.94) 0%, rgba(9,9,10,.86) 62%, rgba(9,9,10,0) 100%);
    backdrop-filter:blur(18px) saturate(140%);
    -webkit-backdrop-filter:blur(18px) saturate(140%);
  }
  .masthead{display:flex;align-items:flex-end;justify-content:space-between;gap:28px;flex-wrap:wrap}
  .brand{display:flex;align-items:center;gap:12px}
  .mark{width:26px;height:26px;flex:0 0 auto}
  .brand-name{font-size:15px;letter-spacing:.26em;font-weight:600;text-transform:uppercase}
  .brand-sep{width:1px;height:20px;background:var(--line-strong)}
  .doc-title{font-size:15px;color:var(--muted);letter-spacing:.01em}
  h1{
    margin:14px 0 0; font-size:clamp(23px,2.7vw,33px); line-height:1.12;
    letter-spacing:-.028em; font-weight:600; max-width:30ch;
  }
  h1 em{font-style:normal;color:var(--accent)}
  .lede{margin:8px 0 0;font-size:13px;line-height:1.55;color:var(--muted);max-width:78ch}
  .stats{display:flex;gap:22px;margin:12px 0 0;font-size:12px}
  .stat b{display:block;font-family:var(--mono);font-size:15px;font-weight:500;letter-spacing:-.01em;color:var(--fg)}
  .stat span{display:block;margin-top:3px;color:var(--faint);letter-spacing:.06em;text-transform:uppercase;font-size:10px}

  .controls{display:flex;flex-direction:column;gap:8px;margin-top:14px;padding-bottom:10px}
  .control-row{display:flex;align-items:center;gap:12px;flex-wrap:wrap}
  .control-label{font-size:10px;letter-spacing:.14em;text-transform:uppercase;color:var(--faint);width:52px;flex:0 0 auto}
  .seg{display:flex;gap:2px;padding:3px;background:rgba(255,255,255,.045);border:1px solid var(--line);border-radius:11px;flex-wrap:wrap}
  .seg button{
    padding:6px 12px;border-radius:8px;font-size:12.5px;color:var(--muted);
    transition:background .16s ease,color .16s ease;
  }
  .seg button:hover{color:var(--fg);background:rgba(255,255,255,.05)}
  .seg button[aria-pressed="true"]{background:rgba(255,255,255,.1);color:var(--fg);box-shadow:0 1px 0 rgba(255,255,255,.08) inset}
  .seg button .spec{font-family:var(--mono);font-size:10px;color:var(--faint);margin-left:6px}
  .seg button[aria-pressed="true"] .spec{color:rgba(30,215,96,.85)}

  .pills{display:flex;gap:6px;flex-wrap:wrap}
  .pills button{
    padding:5px 10px;border-radius:999px;font-size:12px;color:var(--muted);
    border:1px solid transparent;transition:.16s ease;
  }
  .pills button:hover{color:var(--fg);background:rgba(255,255,255,.05)}
  .pills button[aria-pressed="true"]{color:var(--accent);border-color:rgba(30,215,96,.38);background:rgba(30,215,96,.08)}

  /* ---------- main ---------- */
  main{position:relative;z-index:1;padding:8px 0 120px}
  .device-meta{display:flex;align-items:baseline;gap:12px;padding:6px 32px 12px;flex-wrap:wrap}
  .device-meta h2{margin:0;font-size:14px;font-weight:550;letter-spacing:-.01em}
  .chip{
    font-family:var(--mono);font-size:10.5px;letter-spacing:.04em;color:var(--muted);
    border:1px solid var(--line);border-radius:6px;padding:3px 7px;
  }
  .device-meta .note{font-size:12px;color:var(--faint)}

  .strip-wrap{position:relative;min-width:0}
  .strip{
    display:flex;gap:26px;align-items:flex-start;
    padding:6px 32px 30px;overflow-x:auto;overflow-y:hidden;
    scroll-snap-type:x proximity;scroll-padding-left:32px;
    scrollbar-width:thin;scrollbar-color:rgba(255,255,255,.14) transparent;
  }
  .strip::-webkit-scrollbar{height:8px}
  .strip::-webkit-scrollbar-thumb{background:rgba(255,255,255,.12);border-radius:8px}
  .poster{
    position:relative;flex:0 0 auto;scroll-snap-align:start;
    border-radius:var(--radius);overflow:hidden;border:1px solid var(--line);
    background:var(--panel);
    box-shadow:0 30px 70px -40px rgba(0,0,0,.95);
    transition:transform .25s cubic-bezier(.22,1,.36,1), border-color .2s ease, box-shadow .25s ease;
  }
  .poster img{display:block;height:clamp(300px,calc(100vh - 455px),740px);width:auto}
  .missing-shot{display:flex;align-items:center;justify-content:center;min-height:240px;width:min(42vw,280px);padding:16px;text-align:center;color:#ebecec;background:#171717;border:1px dashed #1ed760;font-size:13px}
  body[data-size="large"] .poster img{height:clamp(420px,calc(100vh - 330px),980px)}
  body[data-size="full"] .poster img{height:calc(100vh - 130px)}
  body[data-size="full"] header{position:static;backdrop-filter:none;-webkit-backdrop-filter:none;background:none}
  body[data-size="full"] h1,body[data-size="full"] .lede,body[data-size="full"] .stats{display:none}
  body[data-size="full"] .masthead{min-height:0}
  body[data-size="full"] .strip{padding-bottom:16px}
  .strip[data-device="watch"] .poster img{height:clamp(220px,calc(100vh - 520px),500px)}
  body[data-size="large"] .strip[data-device="watch"] .poster img{height:clamp(320px,calc(100vh - 380px),780px)}
  body[data-size="full"] .strip[data-device="watch"] .poster img{height:calc(100vh - 260px)}
  .poster:hover{transform:translateY(-4px);border-color:var(--line-strong);box-shadow:0 40px 80px -40px rgba(0,0,0,1)}
  .poster:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
  .poster .idx{
    position:absolute;left:10px;top:10px;padding:3px 7px;border-radius:7px;
    font-family:var(--mono);font-size:10.5px;letter-spacing:.06em;
    background:rgba(0,0,0,.55);backdrop-filter:blur(10px);color:rgba(255,255,255,.82);
    border:1px solid rgba(255,255,255,.14);
  }
  .poster .cap{
    position:absolute;inset:auto 0 0 0;padding:34px 14px 12px;
    font-size:12px;line-height:1.45;color:rgba(255,255,255,.9);
    background:linear-gradient(180deg,transparent,rgba(0,0,0,.78));
    opacity:0;transform:translateY(6px);transition:.22s ease;white-space:pre-line;
  }
  .poster:hover .cap,.poster:focus-visible .cap{opacity:1;transform:none}
  .hint-nav{display:flex;gap:6px;margin-inline-start:auto}
  .hint-nav button{
    width:30px;height:30px;border-radius:999px;display:grid;place-items:center;
    border:1px solid var(--line-strong);background:rgba(255,255,255,.04);color:var(--fg);
    transition:background .16s ease,opacity .16s ease;
  }
  .hint-nav button:hover{background:rgba(255,255,255,.12)}
  .hint-nav button[disabled]{opacity:.25;cursor:default}
  .hint-nav svg{width:14px;height:14px}

  /* all-locales matrix */
  .matrix{padding:4px 32px 0;display:flex;flex-direction:column;gap:2px}
  .mrow{
    display:grid;grid-template-columns:104px minmax(0,1fr);gap:18px;align-items:center;min-width:0;
    padding:16px 0;border-top:1px solid var(--line);
  }
  .mrow:first-child{border-top:0}
  .mrow .who{display:flex;flex-direction:column;gap:3px}
  .mrow .who b{font-size:12.5px;font-weight:550;letter-spacing:.01em}
  .mrow .who span{font-family:var(--mono);font-size:10px;color:var(--faint);letter-spacing:.04em}
  .mrow .thumbs{display:flex;gap:12px;overflow-x:auto;padding-bottom:4px;scrollbar-width:thin;min-width:0}
  .mrow .thumbs img{
    height:clamp(150px,18vh,250px);width:auto;border-radius:9px;border:1px solid var(--line);
    background:var(--panel);transition:transform .2s ease,border-color .2s ease;cursor:zoom-in;display:block;
  }
  .mrow .thumbs img:hover{transform:translateY(-3px);border-color:var(--line-strong)}

  /* ---------- lightbox ---------- */
  .lb{position:fixed;inset:0;z-index:100;display:none;background:rgba(4,4,5,.9);backdrop-filter:blur(26px);-webkit-backdrop-filter:blur(26px)}
  .lb[open]{display:grid}
  .lb{grid-template-rows:minmax(0,1fr)}
  .lb-shell{display:grid;grid-template-columns:minmax(0,1fr) 340px;height:100%;min-height:0;overflow:hidden}
  .lb-stage{position:relative;display:flex;align-items:center;justify-content:center;padding:52px 38px;min-width:0;min-height:0;overflow:hidden}
  .lb-stage img{
    display:block;max-width:100%;max-height:100%;width:auto;height:auto;
    border-radius:12px;border:1px solid var(--line);box-shadow:0 50px 100px -40px #000;
  }
  .lb-side{border-left:1px solid var(--line);padding:64px 28px 28px;display:flex;flex-direction:column;gap:20px;overflow-y:auto}
  .lb-eyebrow{font-family:var(--mono);font-size:11px;letter-spacing:.16em;color:var(--accent)}
  .lb-side h3{margin:0;font-size:19px;line-height:1.3;letter-spacing:-.01em;font-weight:600;white-space:pre-line}
  .lb-side p{margin:0;font-size:13px;line-height:1.65;color:var(--muted)}
  .kv{display:grid;grid-template-columns:auto 1fr;gap:6px 14px;font-size:11.5px;margin:0}
  .kv dt{color:var(--faint);letter-spacing:.04em}
  .kv dd{margin:0;font-family:var(--mono);font-size:11px;color:var(--muted);word-break:break-all}
  .review{display:flex;flex-direction:column;gap:8px}
  .review-kicker{font-size:12px;font-weight:650;color:var(--fg)}
  .review-sha{font-family:var(--mono);font-size:10px;line-height:1.45;color:var(--faint);word-break:break-all}
  .review-status{display:flex;gap:6px;flex-wrap:wrap}
  .review-status button{padding:6px 10px;border-radius:999px;border:1px solid var(--line-strong);background:transparent;color:var(--muted);font-size:12px}
  .review-status button[aria-pressed="true"]{color:#08110c;background:var(--accent);border-color:var(--accent)}
  .review-status button:disabled{opacity:.35}
  #reviewNote{width:100%;resize:vertical;min-height:72px;border-radius:10px;border:1px solid var(--line-strong);background:#070708;color:var(--fg);padding:8px 10px;font:13px/1.45 inherit}
  .review-old{font-size:11px;line-height:1.45;color:var(--faint)}
  .review-mark{position:absolute;left:8px;top:8px;z-index:2;padding:2px 7px;border-radius:999px;background:#08110c;color:var(--accent);font-size:10px;letter-spacing:.04em}
  .lb-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:auto;padding-top:8px}
  .btn{
    padding:8px 13px;border-radius:9px;border:1px solid var(--line-strong);
    background:rgba(255,255,255,.05);font-size:12px;color:var(--fg);
    transition:.16s ease;white-space:nowrap;
  }
  .btn:hover{background:rgba(255,255,255,.1)}
  .btn.ghost{background:none}
  .lb-close{position:absolute;right:16px;top:16px;width:34px;height:34px;border-radius:999px;display:grid;place-items:center;background:rgba(255,255,255,.06);border:1px solid var(--line-strong);z-index:3}
  .lb-close:hover{background:rgba(255,255,255,.13)}
  .lb-arrow{position:absolute;top:50%;transform:translateY(-50%);width:42px;height:42px;border-radius:999px;display:grid;place-items:center;background:rgba(20,20,22,.9);border:1px solid var(--line-strong);z-index:3}
  .lb-arrow:hover{background:rgba(40,40,44,.95)}
  .lb-arrow.prev{left:14px}
  .lb-arrow.next{right:14px}
  .lb-arrow[disabled]{opacity:.25;cursor:default}
  .lb-arrow svg,.lb-close svg{width:17px;height:17px}

  .hint{
    display:flex;gap:18px;flex-wrap:wrap;align-items:center;padding:0 32px 32px;
    font-size:11px;color:var(--faint);letter-spacing:.02em;
  }
  .hint-copy{display:flex;gap:18px;flex-wrap:wrap;align-items:center}
  kbd{
    font-family:var(--mono);font-size:10px;padding:2px 5px;border-radius:4px;
    border:1px solid var(--line-strong);background:rgba(255,255,255,.05);color:var(--muted);
  }
  [hidden]{display:none !important}

  @media (max-width:900px){
    header{padding:16px 18px 0}
    h1{margin-top:14px}
    .strip{padding:6px 18px 24px;gap:16px}
    .poster img{height:min(58vh,560px)}
    .matrix{padding:0 18px}
    .mrow{grid-template-columns:minmax(0,1fr);gap:10px}
    .mrow .thumbs img{height:140px}
    .lb-shell{grid-template-columns:1fr;grid-template-rows:minmax(0,1fr) auto}
    .lb-stage{padding:52px 14px 10px}
    .lb-side{border-left:0;border-top:1px solid var(--line);padding:18px 18px 24px}
    .device-meta{padding:10px 18px 14px}
    .hint{padding:0 18px 32px}
  }
  @media (prefers-reduced-motion:reduce){
    *{transition:none !important;animation:none !important}
  }
</style>
</head>
<body>

<header>
  <div class="masthead">
    <div>
      <div class="brand">
        <svg class="mark" viewBox="0 0 32 32" aria-hidden="true">
          <rect width="32" height="32" rx="8" fill="rgba(30,215,96,.14)"/>
          <path d="M7 22.5V13l4.4 5.4L15.8 13v9.5" fill="none" stroke="#1ed760" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>
          <path d="M19.5 22.5l3-9.5 3 9.5" fill="none" stroke="#1ed760" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        <span class="brand-name">Masso</span>
        <span class="brand-sep"></span>
        <span class="doc-title">App Store 截图</span>
      </div>
      <h1>把肌肉恢复、训练与 <em>AI 教练</em> 装进一套海报</h1>
      <p class="lede">当前要看的是 <b>11-09 审阅稿</b>：12 种语言，iPhone 5 页、iPad 4 页，尚未上传。下一档保留 11-08 Plan A 里已经导出的页，缺文件显示「缺图」，不拿英文内屏冒充。大图旁的意见按批次、设备、语言、文件和图片 SHA 记在这台浏览器里；图片一换，旧的「可以」不会沿用。这是审阅记录，不是上架批准。</p>
      <div class="stats">
        <div class="stat"><b>108</b><span>审阅稿 PNG</span></div>
        <div class="stat"><b>12</b><span>语言</span></div>
        <div class="stat"><b>2</b><span>审阅设备</span></div>
      </div>
    </div>
  </div>

  <div class="controls">
    <div class="control-row">
      <span class="control-label">批次</span>
      <div class="seg" id="batchSeg" role="group" aria-label="批次"></div>
    </div>
    <div class="control-row">
      <span class="control-label">设备</span>
      <div class="seg" id="deviceSeg" role="group" aria-label="设备"></div>
    </div>
    <div class="control-row">
      <span class="control-label">语言</span>
      <div class="pills" id="localePills" role="group" aria-label="语言"></div>
    </div>
    <div class="control-row">
      <span class="control-label">尺寸</span>
      <div class="seg" id="sizeSeg" role="group" aria-label="海报尺寸">
        <button data-size="comfort" aria-pressed="false">舒适</button>
        <button data-size="large" aria-pressed="true">大</button>
        <button data-size="full" aria-pressed="false">满屏</button>
      </div>
    </div>
    <div class="control-row">
      <span class="control-label">视图</span>
      <div class="seg" id="viewSeg" role="group" aria-label="视图">
        <button data-view="single" aria-pressed="true">单语言 · 横排</button>
        <button data-view="matrix" aria-pressed="false">全部语言 · 对照</button>
      </div>
    </div>
  </div>
</header>

<main>
  <div class="device-meta">
    <h2 id="deviceName">iPhone</h2>
    <span class="chip" id="deviceSpec">1320 × 2868</span>
    <span class="note" id="deviceNote"></span>
  </div>

  <section id="singleView">
    <div class="strip-wrap">
      <div class="strip" id="strip"></div>
    </div>
    <div class="hint">
      <div class="hint-copy">
        <span>点击海报查看大图</span>
        <span><kbd>←</kbd><kbd>→</kbd> 切图</span>
        <span><kbd>[</kbd><kbd>]</kbd> 切语言</span>
        <span><kbd>Esc</kbd> 关闭</span>
      </div>
      <div class="hint-nav">
        <button id="stripPrev" aria-label="向左滚动">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>
        </button>
        <button id="stripNext" aria-label="向右滚动">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg>
        </button>
      </div>
    </div>
  </section>

  <section id="matrixView" hidden>
    <div class="matrix" id="matrix"></div>
    <div class="hint"><span>每行一种语言，横向滚动查看该语言的完整 6 张（Watch 为 2 张）。点击可放大。</span></div>
  </section>
</main>

<div class="lb" id="lb" role="dialog" aria-modal="true" aria-label="截图大图">
  <div class="lb-shell">
    <div class="lb-stage">
      <button class="lb-close" id="lbClose" aria-label="关闭">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>
      </button>
      <button class="lb-arrow prev" id="lbPrev" aria-label="上一张">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>
      </button>
      <img id="lbImg" alt="">
      <button class="lb-arrow next" id="lbNext" aria-label="下一张">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg>
      </button>
    </div>
    <aside class="lb-side">
      <div>
        <div class="lb-eyebrow"><span id="lbEyebrow" dir="ltr">01 / 06</span></div>
        <h3 id="lbTitle" style="margin-top:10px"></h3>
        <p id="lbDesc" style="margin-top:10px"></p>
      </div>
      <dl class="kv">
        <dt>语言</dt><dd id="lbLocale"></dd>
        <dt>文件</dt><dd id="lbFile"></dd>
        <dt>尺寸</dt><dd id="lbSize"></dd>
      </dl>
      <div class="review" id="reviewBox">
        <p class="review-kicker">审阅记录 · 不是上架批准</p>
        <p class="review-sha" id="reviewSha"></p>
        <div class="review-status" id="reviewStatus">
          <button type="button" data-status="unread">未审</button>
          <button type="button" data-status="note">有意见</button>
          <button type="button" data-status="ok">这张可以</button>
        </div>
        <textarea id="reviewNote" rows="4" placeholder="只针对这一张图。换图后 SHA 变了，旧的「可以」不会带过来。"></textarea>
        <p class="review-old" id="reviewOld" hidden></p>
        <div class="lb-actions">
          <button class="btn" id="reviewExport" type="button">下载意见</button>
          <button class="btn ghost" id="reviewImport" type="button">导入意见</button>
          <input id="reviewFile" type="file" accept="application/json" hidden>
        </div>
      </div>
      <div class="lb-actions">
        <button class="btn" id="lbCopy">复制文案</button>
        <button class="btn ghost" id="lbNextLocale">切换语言 →</button>
      </div>
    </aside>
  </div>
</div>

<script id="gallery-data" type="application/json">__DATA__</script>
<script>
(() => {
  const DATA = JSON.parse(document.getElementById('gallery-data').textContent);
  const BATCHES = Object.fromEntries(DATA.batches.map(b => [b.id, b]));
  const byId = Object.fromEntries(DATA.devices.map(d => [d.id, d]));
  const localeLabel = Object.fromEntries(DATA.locales.map(([id, name]) => [id, name]));
  const isRTL = code => code === 'ar';

  const SIZE_KEY = 'masso-gallery-poster-size';
  const urlSize = new URLSearchParams(location.search).get('size');
  const savedSize = (() => { try { return localStorage.getItem(SIZE_KEY); } catch { return null; } })();
  const initialSize = ['comfort', 'large', 'full'].includes(urlSize)
    ? urlSize
    : (['comfort', 'large', 'full'].includes(savedSize) ? savedSize : 'large');
  const state = { batch: DATA.batches[0].id, device: 'iphone', locale: 'en', view: 'single', size: initialSize, index: -1, lightbox: false };

  /* ---------- model ---------- */
  const batchOf = () => BATCHES[state.batch];
  const batchDevices = () => batchOf().devices || DATA.devices.map(d => d.id);
  const batchLocales = () => (batchOf().locales || DATA.locales.map(([code]) => code)).map(code => [code, localeLabel[code]]);
  const slidesFor = device => {
    if (device === 'watch') {
      const list = batchOf().watchSlides || [];
      return list.map((s, i) => ({ ...s, num: i + 1, total: list.length }));
    }
    const perDevice = batchOf().perDevice || {};
    const list = perDevice[device] || batchOf().slides || [];
    return list.map((s, i) => ({ ...s, num: i + 1, total: list.length }));
  };
  const srcFor = (device, locale, slide) => batchOf().dir + byId[device].dir + '/' + locale + '/' + slide.file + (batchOf().v ? '?v=' + batchOf().v : '');
  function watchMissing(img) {
    img.addEventListener('error', () => {
      const note = document.createElement('div');
      note.className = 'missing-shot';
      note.textContent = '缺图 · 未导出';
      img.replaceWith(note);
    });
  }
  const copyFor = (slide, locale) => ({
    head: (slide.headline && (slide.headline[locale] || slide.headline.en)) || '',
    desc: (slide.description && (slide.description[locale] || slide.description.en)) || '',
  });

  /* ---------- controls ---------- */
  const batchSeg = document.getElementById('batchSeg');
  DATA.batches.forEach(b => {
    const el = document.createElement('button');
    el.dataset.batch = b.id;
    el.textContent = b.label;
    el.title = b.note;
    el.addEventListener('click', () => set({ batch: b.id }, true));
    batchSeg.appendChild(el);
  });

  const deviceSeg = document.getElementById('deviceSeg');
  const localePills = document.getElementById('localePills');

  // Device tabs and language pills follow the selected batch: the Plan A preview
  // only has iPhone captures in four locales so far.
  function buildDeviceSeg() {
    deviceSeg.innerHTML = '';
    batchDevices().forEach(id => {
      const d = byId[id];
      const b = document.createElement('button');
      b.dataset.device = d.id;
      b.innerHTML = `${d.name}<span class="spec">${slidesFor(d.id).length} 张</span>`;
      b.title = d.spec;
      b.addEventListener('click', () => set({ device: d.id }, true));
      deviceSeg.appendChild(b);
    });
  }

  function buildLocaleSeg() {
    localePills.innerHTML = '';
    batchLocales().forEach(([id, name]) => {
      const b = document.createElement('button');
      b.dataset.locale = id;
      b.textContent = name;
      b.lang = id;
      b.addEventListener('click', () => set({ locale: id }, true));
      localePills.appendChild(b);
    });
  }

  const sizeSeg = document.getElementById('sizeSeg');
  sizeSeg.querySelectorAll('button').forEach(b => {
    b.addEventListener('click', () => {
      set({ size: b.dataset.size }, true);
      try { localStorage.setItem(SIZE_KEY, b.dataset.size); } catch {}
      requestAnimationFrame(() => {
        updateStripNav();
        if (b.dataset.size === 'full') document.getElementById('singleView').scrollIntoView({ block: 'start', behavior: 'smooth' });
      });
    });
  });

  const viewSeg = document.getElementById('viewSeg');
  viewSeg.querySelectorAll('button').forEach(b => {
    b.addEventListener('click', () => set({ view: b.dataset.view }, true));
  });

  /* ---------- render ---------- */
  const strip = document.getElementById('strip');
  const matrix = document.getElementById('matrix');
  const singleView = document.getElementById('singleView');
  const matrixView = document.getElementById('matrixView');

  function syncControls() {
    batchSeg.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.batch === state.batch)));
    deviceSeg.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.device === state.device)));
    localePills.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.locale === state.locale)));
    viewSeg.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.view === state.view)));
    sizeSeg.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.size === state.size)));
    document.body.dataset.size = state.size;
  }

  function render() {
    const dev = byId[state.device];
    const slides = slidesFor(state.device);

    buildDeviceSeg();
    buildLocaleSeg();
    syncControls();
    document.getElementById('deviceName').textContent = dev.name;
    document.getElementById('deviceSpec').textContent = dev.spec;
    document.getElementById('deviceNote').textContent = dev.note + ' · ' + BATCHES[state.batch].note;

    singleView.hidden = state.view !== 'single';
    matrixView.hidden = state.view !== 'matrix';

    if (state.view === 'single') {
      strip.innerHTML = '';
      strip.dataset.device = state.device;
      slides.forEach((s, i) => {
        const card = document.createElement('button');
        card.className = 'poster';
        card.type = 'button';
        card.dataset.index = i;
        card.setAttribute('aria-label', `${copyFor(s, state.locale).head || s.file} — 打开大图`);
        const img = document.createElement('img');
        img.src = srcFor(state.device, state.locale, s);
        img.alt = copyFor(s, state.locale).head || '';
        img.decoding = 'async';
        watchMissing(img);
        const idx = document.createElement('span');
        idx.className = 'idx';
        idx.textContent = String(s.num).padStart(2, '0');
        const cap = document.createElement('span');
        cap.className = 'cap';
        cap.textContent = copyFor(s, state.locale).head;
        const mark = document.createElement('span');
        mark.className = 'review-mark';
        mark.hidden = true;
        card.append(img, idx, cap, mark);
        card.addEventListener('click', () => openLightbox(i));
        strip.appendChild(card);
      });
      requestAnimationFrame(() => { updateStripNav(); paintReviewMarks(); });
    } else {
      matrix.innerHTML = '';
      batchLocales().forEach(([code, name]) => {
        const row = document.createElement('div');
        row.className = 'mrow';
        const who = document.createElement('div');
        who.className = 'who';
        who.innerHTML = `<b>${name}</b><span>${code.toUpperCase()}</span>`;
        const thumbs = document.createElement('div');
        thumbs.className = 'thumbs';
        slides.forEach((s, i) => {
          const img = document.createElement('img');
          img.src = srcFor(state.device, code, s);
          img.alt = `${name} · ${copyFor(s, code).head}`;
          img.loading = 'lazy';
          img.decoding = 'async';
          watchMissing(img);
          img.title = copyFor(s, code).head;
          img.addEventListener('click', () => { state.locale = code; writeHash(); openLightbox(i); });
          thumbs.appendChild(img);
        });
        row.append(who, thumbs);
        matrix.appendChild(row);
      });
    }
    writeHash();
  }

  /* ---------- strip scroll ---------- */
  const updateStripNav = () => {
    const max = strip.scrollWidth - strip.clientWidth - 4;
    document.getElementById('stripPrev').disabled = strip.scrollLeft <= 4;
    document.getElementById('stripNext').disabled = strip.scrollLeft >= max;
  };
  strip.addEventListener('scroll', () => requestAnimationFrame(updateStripNav), { passive: true });
  window.addEventListener('resize', () => requestAnimationFrame(updateStripNav));
  const scrollByCard = dir => {
    const card = strip.querySelector('.poster');
    const step = card ? card.getBoundingClientRect().width + 26 : 400;
    strip.scrollBy({ left: dir * step * (state.locale === 'ar' ? -1 : 1), behavior: 'smooth' });
  };
  document.getElementById('stripPrev').addEventListener('click', () => scrollByCard(-1));
  document.getElementById('stripNext').addEventListener('click', () => scrollByCard(1));

  /* ---------- lightbox ---------- */
  const lb = document.getElementById('lb');
  const lbImg = document.getElementById('lbImg');

  function openLightbox(i) {
    state.index = i;
    state.lightbox = true;
    renderLightbox();
    lb.setAttribute('open', '');
    document.body.style.overflow = 'hidden';
    document.getElementById('lbClose').focus();
  }
  function closeLightbox() {
    state.lightbox = false;
    lb.removeAttribute('open');
    document.body.style.overflow = '';
  }
  function renderLightbox() {
    const slides = slidesFor(state.device);
    const s = slides[state.index];
    if (!s) return;
    const dev = byId[state.device];
    const { head, desc } = copyFor(s, state.locale);
    syncControls();
    const side = document.querySelector('.lb-side');
    side.dir = isRTL(state.locale) ? 'rtl' : 'ltr';
    lbImg.src = srcFor(state.device, state.locale, s);
    lbImg.alt = head;
    document.getElementById('lbEyebrow').textContent =
      String(s.num).padStart(2, '0') + ' / ' + String(s.total).padStart(2, '0');
    document.getElementById('lbTitle').textContent = head;
    const descEl = document.getElementById('lbDesc');
    descEl.textContent = desc;
    descEl.hidden = !desc;
    document.getElementById('lbLocale').textContent = localeLabel[state.locale] + ' (' + state.locale + ')';
    document.getElementById('lbFile').textContent = dev.dir + '/' + state.locale + '/' + s.file;
    document.getElementById('lbSize').textContent = dev.width + ' × ' + dev.height + ' · PNG';
    document.getElementById('lbPrev').disabled = state.index <= 0;
    document.getElementById('lbNext').disabled = state.index >= slides.length - 1;
    writeHash();
    paintReview();
  }
  const step = d => {
    const slides = slidesFor(state.device);
    const next = Math.min(Math.max(state.index + d, 0), slides.length - 1);
    if (next !== state.index) { state.index = next; renderLightbox(); }
  };
  document.getElementById('lbClose').addEventListener('click', closeLightbox);
  document.getElementById('lbPrev').addEventListener('click', () => step(-1));
  document.getElementById('lbNext').addEventListener('click', () => step(1));
  lb.addEventListener('click', e => { if (e.target === lb || e.target.classList.contains('lb-stage')) closeLightbox(); });
  document.getElementById('lbNextLocale').addEventListener('click', () => {
    const codes = batchLocales().map(([code]) => code);
    const idx = codes.indexOf(state.locale);
    const next = codes[(idx + 1) % codes.length];
    set({ locale: next });
    renderLightbox();
  });
  document.getElementById('lbCopy').addEventListener('click', async e => {
    const s = slidesFor(state.device)[state.index];
    const { head, desc } = copyFor(s, state.locale);
    const text = [head, desc].filter(Boolean).join('\n');
    try {
      await navigator.clipboard.writeText(text);
      e.target.textContent = '已复制';
    } catch {
      e.target.textContent = '复制失败';
    }
    setTimeout(() => (e.target.textContent = '复制文案'), 1400);
  });

  /* ---------- keyboard ---------- */
  document.addEventListener('keydown', e => {
    if (!state.lightbox) return;
    const tag = e.target && e.target.tagName;
    if (tag === 'TEXTAREA' || tag === 'INPUT') return;
    if (e.key === 'Escape') { closeLightbox(); return; }
    if (e.key === 'ArrowRight') step(1);
    if (e.key === 'ArrowLeft') step(-1);
    if (e.key === ']' || e.key === '[') document.getElementById('lbNextLocale').click();
  });

  /* ---------- hash routing ---------- */
  let writingHash = false;
  function writeHash() {
    const parts = ['#', state.batch, state.device, state.locale, state.view];
    if (state.lightbox) parts.push(String(state.index + 1));
    const h = parts.join('/').replace(/#\//, '#');
    writingHash = true;
    history.replaceState(null, '', h);
    writingHash = false;
  }
  function readHash(source) {
    const raw = (source !== undefined ? source : location.hash).replace(/^#\/?/, '');
    if (!raw) return;
    const parts = raw.split('/');
    const hasBatch = !!BATCHES[parts[0]];
    if (hasBatch) state.batch = parts.shift();
    if (!batchDevices().includes(state.device)) state.device = batchDevices()[0];
    if (!batchLocales().some(([code]) => code === state.locale)) state.locale = batchLocales()[0][0];
    const [device, locale, view, shot] = parts;
    if (byId[device] && batchDevices().includes(device)) state.device = device;
    if (localeLabel[locale] && batchLocales().some(([code]) => code === locale)) state.locale = locale;
    if (view === 'single' || view === 'matrix') state.view = view;
    if (shot) {
      state.index = Math.min(Math.max(parseInt(shot, 10) - 1, 0), slidesFor(state.device).length - 1);
      render(); openLightbox(state.index); return;
    }
    render();
  }

  function set(patch, rerender = false) {
    const deviceChanged = patch.device && patch.device !== state.device;
    Object.assign(state, patch);
    // Keep the selection inside what this batch actually exports.
    if (!batchDevices().includes(state.device)) state.device = batchDevices()[0];
    if (!batchLocales().some(([code]) => code === state.locale)) state.locale = batchLocales()[0][0];
    if (deviceChanged && state.index > slidesFor(state.device).length - 1) state.index = -1;
    if (rerender) render();
    if (deviceChanged && state.lightbox && state.index < 0) closeLightbox();
    if (state.lightbox) renderLightbox();
  }

  /* ---------- review notes, bound to image bytes ---------- */
  const REVIEW_STORE = 'masso-gallery-review-v1';
  const reviewStore = { version: 1, notes: {} };
  function loadReviewStore() {
    try {
      const raw = JSON.parse(localStorage.getItem(REVIEW_STORE) || '');
      if (raw && raw.notes && typeof raw.notes === 'object') reviewStore.notes = raw.notes;
    } catch {}
  }
  function persistReview() {
    try { localStorage.setItem(REVIEW_STORE, JSON.stringify(reviewStore)); } catch {}
  }
  function shaFor(device, locale, file) {
    const sha = (batchOf().shas || {})[device + '/' + locale + '/' + file];
    return sha || null;
  }
  function reviewKey(device, locale, file, sha) {
    return [state.batch, device, locale, file, sha].join('|');
  }
  function entryFor(device, locale, file, sha) {
    if (!sha) return null;
    return reviewStore.notes[reviewKey(device, locale, file, sha)] || null;
  }
  function writeEntry(device, locale, file, sha, status, text) {
    if (!sha) return;
    const key = reviewKey(device, locale, file, sha);
    const clean = (text || '').trim();
    if ((!status || status === 'unread') && !clean) delete reviewStore.notes[key];
    else reviewStore.notes[key] = { status: status || 'note', text: clean, updatedAt: new Date().toISOString() };
    persistReview();
  }
  function reviewMarkText(entry) {
    if (!entry) return '';
    if (entry.status === 'ok') return '可以';
    if (entry.status === 'note' || entry.text) return '有意见';
    return '';
  }
  function paintReviewMarks() {
    const slides = slidesFor(state.device);
    document.querySelectorAll('#strip .poster').forEach(card => {
      const slide = slides[Number(card.dataset.index)];
      const mark = card.querySelector('.review-mark');
      if (!slide || !mark) return;
      const text = reviewMarkText(entryFor(state.device, state.locale, slide.file, shaFor(state.device, state.locale, slide.file)));
      mark.hidden = !text;
      mark.textContent = text;
    });
  }
  function paintReview() {
    const slides = slidesFor(state.device);
    const s = slides[state.index];
    const shaEl = document.getElementById('reviewSha');
    const noteEl = document.getElementById('reviewNote');
    const oldEl = document.getElementById('reviewOld');
    if (!s || !shaEl || !noteEl) return;
    const sha = shaFor(state.device, state.locale, s.file);
    const entry = entryFor(state.device, state.locale, s.file, sha);
    const status = entry && entry.status ? entry.status : 'unread';
    shaEl.textContent = sha
      ? ('SHA-256 ' + sha)
      : '这张图还没有导出文件，不能标成可以。';
    document.querySelectorAll('#reviewStatus button').forEach(button => {
      button.disabled = !sha;
      button.setAttribute('aria-pressed', String(button.dataset.status === status));
    });
    if (document.activeElement !== noteEl) noteEl.value = entry && entry.text ? entry.text : '';
    noteEl.disabled = !sha;
    const prefix = [state.batch, state.device, state.locale, s.file, ''].join('|');
    const current = sha ? reviewKey(state.device, state.locale, s.file, sha) : '';
    const older = Object.entries(reviewStore.notes).filter(([key]) => key.startsWith(prefix) && key !== current);
    if (older.length) {
      oldEl.hidden = false;
      const bits = older.map(([, value]) => value.text || value.status).filter(Boolean);
      oldEl.textContent = '同路径有 ' + older.length + ' 条旧记录，SHA 已不同，旧的「可以」不会用在这张上。'
        + (bits.length ? ' 旧意见：' + bits.join(' / ') : '');
    } else {
      oldEl.hidden = true;
      oldEl.textContent = '';
    }
  }
  document.querySelectorAll('#reviewStatus button').forEach(button => {
    button.addEventListener('click', () => {
      const slides = slidesFor(state.device);
      const s = slides[state.index];
      if (!s) return;
      const sha = shaFor(state.device, state.locale, s.file);
      writeEntry(state.device, state.locale, s.file, sha, button.dataset.status, document.getElementById('reviewNote').value);
      paintReview();
      paintReviewMarks();
    });
  });
  document.getElementById('reviewNote').addEventListener('input', () => {
    const slides = slidesFor(state.device);
    const s = slides[state.index];
    if (!s) return;
    const sha = shaFor(state.device, state.locale, s.file);
    const current = entryFor(state.device, state.locale, s.file, sha);
    const text = document.getElementById('reviewNote').value;
    const status = current && current.status && current.status !== 'unread'
      ? current.status
      : (text.trim() ? 'note' : 'unread');
    writeEntry(state.device, state.locale, s.file, sha, status, text);
    paintReview();
    paintReviewMarks();
  });
  document.getElementById('reviewExport').addEventListener('click', () => {
    const blob = new Blob([JSON.stringify({ version: 1, notes: reviewStore.notes }, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'review-notes.json';
    link.click();
    URL.revokeObjectURL(link.href);
  });
  document.getElementById('reviewImport').addEventListener('click', () => document.getElementById('reviewFile').click());
  document.getElementById('reviewFile').addEventListener('change', async event => {
    const file = event.target.files && event.target.files[0];
    event.target.value = '';
    if (!file) return;
    const data = JSON.parse(await file.text());
    const notes = data && data.notes;
    if (!notes || typeof notes !== 'object') return;
    Object.entries(notes).forEach(([key, value]) => {
      if (value && typeof value === 'object') reviewStore.notes[key] = value;
    });
    persistReview();
    paintReview();
    paintReviewMarks();
  });

  loadReviewStore();
  readHash(location.hash);
  render();
  window.addEventListener('hashchange', () => { if (!writingHash) readHash(); });
  fetch('review-notes.json', { cache: 'no-store' }).then(response => response.ok ? response.json() : null).then(data => {
    if (!data || !data.notes || typeof data.notes !== 'object') return;
    let changed = false;
    Object.entries(data.notes).forEach(([key, value]) => {
      if (!reviewStore.notes[key] && value && typeof value === 'object') {
        reviewStore.notes[key] = value;
        changed = true;
      }
    });
    if (!changed) return;
    persistReview();
    render();
    if (state.lightbox) renderLightbox();
  }).catch(() => {});
})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
