# Masso App Store Studio

Local portrait screenshot editor: nine selling points, Chinese/English marketing copy, original Masso demo screenshots, and unchanged official Apple device bezels.

## Run

```sh
npm install --legacy-peer-deps
npm run dev -- --hostname 127.0.0.1 --port 8802
```

Open http://127.0.0.1:8802/. Use 编辑这一页 to edit copy, replace screenshots, reorder pages and drag/resize elements. Changes persist in app-store-screenshots.json through the local API. The gallery language toggle changes marketing copy; native screenshots retain their captured language.

## Export

一键导出 downloads a ZIP with nine PNGs per selected size and locale, plus export-manifest.json. Supported iPhone portrait sizes: 1179×2556 and 1206×2622. The local Sharp endpoint flattens PNGs to RGB without alpha. No files are uploaded to an external service. Choose one or both sizes; bilingual export is available in the desktop toolbar. Exported screenshots include Apple Watch illustrations within iPhone App Store pages; this is not a standalone watchOS screenshot submission set.

Official specification: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/

## Sources

Typography/layout follows /Users/yumowu/Projects/yumo-site/styles/portfolio-theme.css and works/masso; accent is Masso green #1ED760. Exact input paths and SHA-256 hashes are recorded in asset-provenance.json. Official Apple iPhone 18 Pro and Watch Series 11 PNG resources remain unchanged; owner confirmed license acceptance on 2026-10-29. Use is subject to Apple's resource license.

Validation: production build passed; browser gallery/editor navigation and ZIP export exercised; all 18 Chinese PNGs checked for exact size and RGB mode. Real App screenshots use demonstration data. Review copy/screenshots before App Store submission.

Editor foundation: https://www.parthjadhav.com/products/app-store-screenshots (@parthjadhav8).

Owner size update (2026-10-29): screenshot portrait 1179×2556 / 1206×2622; landscape equivalents 2556×1179 / 2622×1206. App preview video sizes 886×1920 / 1920×886 are documented separately; this portrait screenshot editor does not export preview videos. The internal 1320×2868 design canvas is retained to preserve existing edits, then rasterized to the selected output dimensions. Previous ZIPs remain historical exports.

## Device categories (2026-10-29 owner revision)

The gallery's device selector exports one largest portrait resolution per category:

| Category | Output | Source / status |
| --- | --- | --- |
| iPhone | 1206×2622 | Nine existing marketing pages |
| iPhone Duo | 2007×2853 | Export intentionally blocked until a compatible runtime/device can produce and validate real captures |
| iPad 13″ | 2064×2752 | Eight pages built from actual universal-App captures on iPad Pro13 M5, iOS26.5 |
| Apple Watch | 416×496 | Two existing native watchOS screens, without a bezel or marketing surround |

Older two-size ZIP exports are historical. The current device selector supersedes their export defaults. Chinese/English changes marketing captions; captured native UI remains in its recorded language (currently English). Watch screenshots do not certify Series12 hardware testing. iPad's illustrated enclosure is a simple neutral device surround, not an official Apple bezel asset. Native capture SHA256s are in device-capture-provenance.json. The training illustration uses the captured Rest state after the initial media-loading screenshot was rejected.
