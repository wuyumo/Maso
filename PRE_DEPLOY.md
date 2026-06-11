# Masso 上线 Runbook (2026-06-11 刷新)

> 代码侧已全部就绪。本文按顺序走完即提审。
> 历史遗留的"deploy 前恢复项"全部已处理: paywall 上限 ✅ 已恢复 (实测会弹) ·
> AI key 后端代理 ✅ (Cloudflare Worker, key 不在客户端) ·
> Paywall "Cloud sync" 卖点 ✅ 已下架 (未实现不承诺, iCloud Drive 同步排 1.1)。

---

## ✅ 已完成 (代码 / 素材侧)

| 项 | 状态 |
|---|---|
| Release 配置编译 | ✅ BUILD SUCCEEDED (签名就绪即可 Archive) |
| 版本号 | ✅ 1.0 (1) — Maso / MasoWatch / MasoWidgets 三 target 对齐 |
| 权限文案 / 加密豁免 / iPhone-only | ✅ Info.plist 全部就位 |
| iPhone 截图 | ✅ `build/screenshots/{en-US,zh-Hans}/` 各 8 张 1320×2868 (6.9"), 当日 build 重拍 |
| Apple Watch 截图 | ✅ `build/screenshots/watch/` 3 张 416×496 (idle / live+心率 / rest) — **watch app 随包提交时 ASC 必传 ≥1 张** |
| IAP 审核参考截图 | ✅ `build/screenshots/iap-paywall-zh.png` (价格占位 "—", 可在 TestFlight 真价后重拍) |
| 文案 | ✅ `docs/app-store-metadata.md` (已加 Watch 卖点, 900+ 动作; **只填 en-US + zh-Hans 两个 locale**) |
| 隐私政策 / 条款 / 支持页 | ✅ 全部 200 在线 (见下方 URL) |
| Secrets.xcconfig | ✅ 本机在位 (proxy URL + client token), Archive 可直接打 |

---

## 🚦 你要做的 (按顺序)

### 0. Xcode 登录 Apple ID ⛔️ 一切的前置
Xcode → Settings → Apple Accounts → Add Apple Account → `wuyumoawuyumo@outlook.com` (密码+2FA)。
登录后选中你的 iPhone 点 ▶ Run 一次 → 自动生成 app + watch 的 profile (顺带真机装上最新版)。

### 1. App Store Connect 建 App 记录
appstoreconnect.apple.com → My Apps → ＋:
- Platform **iOS** (watch app 随包, 不用单独建) · Name **Masso** (被占就 Masso – Workout Tracker)
- Primary language **English (U.S.)** · Bundle ID 选 **com.yumowu.maso** · SKU `maso-ios-001`

### 2. 内购 (Features → In-App Purchases / Subscriptions)
先建订阅组 `Masso Pro`, 再建:
| Product ID | 类型 | 参考价 |
|---|---|---|
| `com.yumowu.maso.pro.monthly` | Auto-Renewable, 1 个月 | ¥18 / $2.99 |
| `com.yumowu.maso.pro.yearly` | Auto-Renewable, 1 年 (7 天试用) | ¥108 / $17.99 |
| `com.yumowu.maso.pro.lifetime` | Non-Consumable | ¥328 / $49.99 |
每个都要: 本地化显示名 (Masso Pro 月度/年度/终身) + 审核截图 (用上表 paywall 图)。
**三个 IAP 必须随 1.0 版本一起提交** (版本页底部 In-App Purchases 区勾上)。

### 3. App 隐私问卷 (App Privacy) — 照抄
- Do you collect data? → **Yes**
- 勾 **Fitness** (Health & Fitness → Fitness) → 用途 **App Functionality** → linked to identity? **No** → tracking? **No**
- 其余全不勾。结果标签 = "Data Not Linked to You: Fitness" ✓ (对应 AI 推荐把训练摘要发到代理→DeepSeek; 本地数据/HealthKit/心率不出设备, 不算收集)

### 4. 版本页素材
- iPhone 6.9" 截图: `build/screenshots/en-US/` 8 张按 01→08 拖入; zh-Hans locale 切换后传 `zh-Hans/`
- Apple Watch 截图: `build/screenshots/watch/` 3 张 (顺序 02-live → 03-rest → 01-idle, 把最有信息量的放第一张)
- 文案: 从 `docs/app-store-metadata.md` 复制 (Name/Subtitle/Promo/Description/Keywords/What's New; **只做 en-US + zh-Hans**)
- URLs: Support `https://wuyumo.github.io/Maso/` · Privacy `https://wuyumo.github.io/Maso/privacy-policy`
- 年龄分级问卷全选 None → **4+** · Copyright `© 2026 Yumo Wu`

### 5. Archive + 上传 (必须 Xcode GUI)
Xcode 顶部设备选 **Any iOS Device (arm64)** → Product → **Archive** → Organizer → **Distribute App** → App Store Connect → Upload (全默认)。
处理完成邮件后在 ASC 版本页选这个 build。

### 6. TestFlight 自测 (建议 1-2 天)
关键回归: 完整跑一次训练 (含 Live Activity) · 手表镜像 + ✓ 完成组 + 心率 · 分享 (routine 图卡扫码导入 / History 自定义分享) · 从照片导入 routine · 购买月度 (沙盒) → Pro 解锁 → 恢复购买 · HealthKit 写入圆环 · 中英切换。

### 7. 提审 — App Review 备注直接粘贴:
> Masso is a local-first workout tracker. No account or login is required — all features are immediately accessible.
> • HealthKit: we write finished workouts to Apple Health (Activity rings) and read basic workout history; on Apple Watch we run a workout session for live heart rate. Health data never leaves the device.
> • AI workout suggestions (Pro): when the user explicitly taps "Generate", the app sends training preferences and a 14-day training summary (no personal identifiers) to our server proxy, which forwards to DeepSeek's LLM API. This is the app's only network feature.
> • Apple Watch app mirrors the active workout (check off sets, rest timer, heart rate). To test: start any workout on iPhone.
> • In-app purchases unlock unlimited routines, full history, and AI suggestions. Free tier is fully functional for core logging.

---

## ⚠️ 已知非阻塞 (上线后处理)
- FormSubmit 反馈邮箱首封需点激活邮件 (wuyumoawuyumo@gmail.com 收)
- 27 个主库动作无动图 (Pexels 静图备选, key 在 Vercel env, 1.0.x 跟进)
- iCloud Drive 多设备同步 → 1.1 (届时恢复 paywall "Cloud sync" 行)
- IAP 审核截图可换成 TestFlight 真价版
