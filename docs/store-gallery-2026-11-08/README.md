# App Store 截图浏览页

本地只读画廊，三批并列对比：**11-08 Plan A 预览**（新卖点重做）、**11-08 调整版**（文案放大 + 机位下移）、**11-06 已上传**（线上版本）。

| 批次 | 目录 | 覆盖 | 状态 |
| --- | --- | --- | --- |
| 11-08 Plan A 五页预览（默认） | `docs/store-plan-a-2026-11-08/exported/ios/` | iPhone × zh / zh-Hant / en / ja，20 张（5 页） | 卖点与文案待确认，**未导出 12 语言、未上传** |
| 11-08 调整版 | `docs/store-refresh-2026-11-08/exported/ios/` | 12 语言 × 5 设备，312 张 | 文案放大 + 演示机位下移，**尚未上传** |
| 11-06 已上传 | `docs/store-all-refresh-2026-11-06/exported/ios/` | 12 语言 × 5 设备，312 张 | 当前 App Store Connect 上的线上版本 |

不复制、不压缩、不改动任何图片：页面直接以相对路径读取 PNG 原件。

## 打开

```bash
# 任选其一
open docs/store-gallery-2026-11-08/index.html          # file:// 直接打开即可
cd docs && python3 -m http.server 8840 --bind 127.0.0.1   # 根目录必须是 docs/（图片在 ../store-*）
# → http://127.0.0.1:8840/store-gallery-2026-11-08/
```

## 功能

- **批次切换**：三批同设备同语言可直接对比；设备与语言控件跟随批次（Plan A 只有 iPhone 与 4 种语言）。
- **设备切换**：iPhone 6.9″（1320×2868）、iPhone 6.3″（1206×2622）、iPad 13″（2064×2752）、Duo（2007×2853）、Watch 46mm（416×496）。
- **12 语言切换**：en / 简中 / 繁中 / ja / ko / es / fr / de / it / pt-BR / ru / ar；阿拉伯语只翻转文案区，页面框架保持 LTR。
- **两种视图**：单语言横排（默认，按 App Store 顺序 01→06）；全部语言对照（每种语言一行，用于检查本地化是否漏译或换行溢出）。
- **大图查看**：点击任意海报打开原图，含该语言的实际标题与副文案、文件路径、像素尺寸；支持「复制文案」。
- **海报尺寸**：舒适 / 大（默认）/ 满屏。满屏约 1 张铺满窗口高度并自动滚到海报区，适合逐张看文案；选择会记在本机。也可用 `?size=full` 直接打开。
- **深链接**：`#批次/设备/语言/视图/页码`，例如 `#plana/iphone/zh/single/3`、`#new/ipad/fr/matrix`（旧的四段式 `#iphone/zh/single` 仍可用，落在默认批次）。
- **快捷键**：`← →` 切图、`[ ]` 切语言、`Esc` 关闭。

## 数据来源

每批次的标题与副文案直接读该批次自己的 Studio 状态：

- Plan A 预览 → `design/app-store-studio-2026-10-29/app-store-screenshots.json`
- 11-08 / 11-06 → `docs/store-all-refresh-2026-11-06/approved-studio-state.json`

因此画廊里的文案与海报逐字一致；主文案里的 `\n` 是刻意断行，页面按 `pre-line` 渲染。Watch 两张为原生表盘截图，无营销文案。

重新生成：

```bash
python3 docs/store-gallery-2026-11-08/build_gallery.py
```

## 自检

`selftest.html` 在 iframe 里驱动真实页面，检查渲染、灯箱、键盘、语言同步、批次切换、设备与语言控件随批次变化、对照视图与横向溢出。

```bash
# 需要本地服务（http://127.0.0.1:8840）
# 用无头 Chrome 打开 selftest.html，读取 <pre id="out"> 的结果
```

最近一次结果（2026-11-08，headless Chrome，1280 宽）：**ALL PASS (28 checks)**。

## 边界

- 仅覆盖仓库内的三批导出文件；不含 Apple 线上回读状态（见 `docs/store-all-refresh-2026-11-06/independent-final-verification.json`）。
- Plan A 预览只有 4 种语言的 iPhone 成品；对照视图只有 4 行是对的。
- 11-08 两批均尚未上传，画廊里的「调整版 / Plan A」不等于线上现状。
- 不含 Studio 工程本身（`design/app-store-studio-2026-10-29`，8802）的可编辑画布。
- 截图内容为授权营销演示数据，不代表真实 AI 精度或传感器验证。
