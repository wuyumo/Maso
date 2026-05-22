# Maso — Session Memory Dump (2026-05-22)

本文件是 Claude Code 跟用户长会话的全程"记忆"导出. 涵盖:
- 项目背景 + 用户偏好
- 这次会话做的事 (按时间顺序)
- 各模块当前状态
- Punch list 完成度
- 未解决的开放问题
- 给下次会话 / 接手者的提示

---

## 1. 项目背景

**Maso** — iOS 原生 SwiftUI 健身追踪 app, 单人项目.

**核心理念** (跟 user 反复迭代得来):
- 训练时优先, 营销第二 — 真在健身房用, 不是 vanity stats
- 离线优先 — WiFi 不可靠是硬约束
- 沉默的进步反馈 — 没有徽章 / 连胜 / 催回推送
- 全品类 — 力量 + 有氧 + 拉伸, 统一 `TrainingEntry` 抽象
- 进阶式默认值 — 不做"新手版/高级版"切换器, UI 自然演进

**Tech stack**:
- SwiftUI + Observation (iOS 18+ 最低)
- 全 in-memory mock → 持久化走 `PersistenceController` (Documents/maso-data.json)
- StoreKit 2 IAP (这次会话接入)
- HealthKit 双向同步
- AI workout suggestions via Cloudflare Worker proxy → DeepSeek API
- 12 语言 i18n (en, zh-Hans, zh-Hant, ja, ko, es, fr, de, it, pt-BR, ru, ar)

**Repo**: `github.com/wuyumo/Maso.git` (main branch)
**Bundle ID**: `com.maso.app`
**Developer Team**: `UR6F66266C` (US, Apple ID `wuyumoawuyumo@outlook.com`)
**App Status**: Pre-launch, 距 App Store 提交一步之遥

---

## 2. 用户偏好 / 重要 quirks

(对接其他会话或开发者非常关键)

### 工作流偏好
- **自动安装到 iPhone**: 每次代码改动后, 自动跑 `./scripts/install_iphone.sh`. 不用问.
- **Memory 文件**: `~/.claude/projects/-Users-yumowu-Projects/memory/feedback_auto_install_maso_iphone.md` 有这条规则.
- **Commit 节奏**: 不主动 commit, 等用户明确指令 ("帮我 commit" / "push 到 GitHub"). 但用户允许 batch commit 累积的工作.
- **沟通语言**: 中文主导 (用户母语), 代码注释 + commit message 也允许中文.
- **代码风格**: 注释偏长且包含决策过程 + "为什么这么写而不那样" 的对比.

### 视觉 / 交互偏好
- **Spotify 风格深色**: `#121212` 背景, `#1ED760` accent 绿
- **大字号 / 高对比 / 单手操作**
- **iOS 默认 > 自定义**: 自定义的 Tab bar / Swipe button 用户反复改回原生
- **拒绝 motion / 庆祝动效**: 完成训练只要 haptic + 一声 chime, 不要彩屏 / 礼花
- **拒绝徽章 / XP / 连胜**: 反复强调

### 拒绝过的方案
- ❌ 自制 TabBar (用了几次最终回归原生)
- ❌ 自制 SwipeAction 按钮 (跟原生 .swipeActions 不一致, 回退)
- ❌ Anatomy 图重画 (尝试 4 次都"完全不能用", 回退到 react-body-highlighter baseline)
- ❌ 社交 / 朋友圈 / 点赞功能 — 制造比较焦虑, 偏离训练
- ❌ AI 教练聊天框 — "做得好!" 的廉价反馈, 没价值
- ❌ 体脂 / 身材过度追踪 — 易诱发饮食失调

---

## 3. 这次会话做的事 (按时间顺序)

### 阶段 1: Pre-conversation 累积
(summary 里已经记的, 这里不展开)
- 社区训练计划 + 8 seed plans + maso:// deep link
- SwipeableRow 自定义 swipe wrapper
- iOS 默认 TabView 替换自制 tab bar
- UnifiedShareCard 整合 4 个 sections
- HistoryScreen 各种打磨

### 阶段 2: 拉伸用 checkmark 不用倒计时
- `Maso/Data/PlanSegments.swift:43-46` — `isCountdown` 从 `ex.category != .strength` 改成 `ex.category == .cardio`
- 只有 cardio 自动倒计时. flexibility (拉伸) 跟 strength 一样手动打勾
- `TrainingSession.swift:215` 同步把"完成组" haptic / chime 触发条件扩到 flexibility

### 阶段 3: TrainingMiniBar iOS Now-Playing 风格重做
- `Maso/Views/Tabs/TrainingMiniBar.swift` — 从纯黑实色 `Color.black` 改成 `.ultraThinMaterial` 半透明
- 缩略图 44 → 36pt, 主控按钮 40 → 32pt
- `Maso/Views/RootView.swift` — `.safeAreaInset(edge: .bottom)` 从 TabView 整体挪到每个 tab 的 content
- 之前 MiniBar 跟 TabBar 视觉粘连; 现在两者独立分层

### 阶段 4: SessionCard 照片 + BodyHint 并排居中
- `HistoryScreen.swift` SessionCard 底部布局
- 删掉了挂在 title 左侧的 48×48 缩略图
- 改成 `[Spacer] [Photo 80×80] [BodyHint 80pt] [Spacer]` 一起居中, replay 按钮 ZStack overlay 浮右下角

### 阶段 5: App Store 上架 audit
跑 general-purpose agent 全盘扫描, 输出 punch list:
- 🔴 paywall 注释拆 + mock Pro 删 + ITSAppUsesNonExemptEncryption + StoreKit 接 + Terms/Privacy 按钮
- 🟡 iCloud sync / 翻译 lint / debug print() / Settings legal / 健身免责
- 🟢 截图本地化 / Keychain / App Group

### 阶段 6: 3 个 quick fix
- `RootView.handleNewPlan` 把 paywall 检查从注释拆出来
- `DataStore.makeMock()` 删 `testProSub`, 改 `proSubscription: nil`
- `project.yml` 加 `ITSAppUsesNonExemptEncryption: false` → 重新 xcodegen 生成 Info.plist

### 阶段 7: StoreKit 2 完整集成
- 创建 `Maso.storekit` config (3 product: monthly $4.99 / yearly $29.99 / lifetime $79.99, monthly+yearly 同一 subscription group)
- 新建 `Maso/Data/SubscriptionManager.swift` — `@Observable @MainActor` class, 250 行
  - `loadProducts()` / `purchase()` / `restore()` / `refreshEntitlements()`
  - 后台 `Task.detached` 监听 `Transaction.updates`
  - `nonisolated(unsafe)` 处理 deinit MainActor 隔离问题
- `MasoApp.swift` 注入 SubscriptionManager via `.environment`, 在 `.task` 里 configure callback 同步 entitlement → `dataStore.settings.proSubscription`
- `Models/Settings.swift` ProSubscription 加 Equatable
- `PaywallScreen.swift` 完全重写: `product.displayPrice` locale-aware, 真 purchase / restore, Terms+Privacy 改成 Link
- `project.yml` 加 schemes 配置: `storeKitConfiguration: Maso.storekit`

### 阶段 8: Debug print() 包 #if DEBUG
- `SpeechManager.swift:51`
- `LiveActivityManager.swift:37, 52, 55`

### 阶段 9: i18n lint 清零
- en.lproj 加了 16 个新 key (10 个 StoreKit/History + 6 个 Settings)
- delegate agent 翻译到 11 个语言, lint "All good ✓"

### 阶段 10: Settings 加 Health & Safety + About
- `SettingsScreen.swift` — 在 Data section 之后加两个 section:
  - Health & Safety: 完整免责文案 (consult physician / 紧急停止)
  - About: Privacy Policy / Terms of Service / Version
- `appVersionLabel` 从 `Bundle.main.infoDictionary` 读 "1.0 (1)" 格式

### 阶段 11: GitHub Pages 部署
- `docs/terms.md` 新建 (中英双语, 12 个 section, 涵盖订阅 / 免责 / 退款 / IP)
- `docs/index.md` 加 Terms 链接
- `docs/_config.yml` exclude 内部 dev docs (`app-store-connect-walkthrough.md` 等)
- `PaywallScreen.swift` URL 从 placeholder 改成真 GitHub Pages URL
- 三个 URL 全 200 OK:
  - `https://wuyumo.github.io/Maso/`
  - `https://wuyumo.github.io/Maso/privacy-policy.html`
  - `https://wuyumo.github.io/Maso/terms.html`

### 阶段 12: Cloud sync 行从 paywall 删除
- iCloud Drive ubiquity 没实现, 留着是空头承诺 — Apple 审核 2.3.1 reject 风险
- 实现后 (`docs/cloudkit-todo.md`) 再恢复

### 阶段 13: App Store Connect 操作手册
- `docs/app-store-connect-walkthrough.md` — 235 行, 6 step 详细 (从创建 app 到提交审核)

### 阶段 14: Commit + Push
3 个 commit 推 `wuyumo/Maso` main:
- `2ab273c` — Pre-deploy push (70 文件, +8498 / -1298)
- `1251f09` — Remove Cloud sync + add ASC walkthrough
- `ed97c79` — Hide internal dev docs from public Pages

---

## 4. Punch list 状态 (实时)

### ✅ 已完成
- [x] Paywall gate restored
- [x] Mock Pro removed (`makeMock` 默认 free tier)
- [x] `ITSAppUsesNonExemptEncryption=false` baked
- [x] StoreKit 2 full integration (SubscriptionManager + .storekit + reworked PaywallScreen)
- [x] Terms / Privacy URLs wired up + deployed
- [x] Debug print() → `#if DEBUG`
- [x] i18n translation lint clean (12 langs)
- [x] Fitness disclaimer in Settings → Health & Safety
- [x] About section (Privacy / Terms / Version)
- [x] Cloud sync removed from paywall (不再空头承诺)
- [x] Release archive 验证通过 (8.0 MB, icon 自动展开)
- [x] App Store Connect 操作手册

### 🔴 阻塞 — 只剩这一项, 但要去 web 操作
- [ ] **App Store Connect 流程** — 跟 `docs/app-store-connect-walkthrough.md` Step 1-6
  - 注册 3 个 IAP product ID + 价格档
  - 填 metadata (description / keywords / screenshots)
  - 上传 archive
  - TestFlight 内测
  - Submit for Review

### 🟡 可放后面 (TestFlight 阶段补)
- [ ] 截图本地化补 10 种语言 (现 en + zh-Hans 已够过审)
- [ ] iCloud sync 兑现 (从 paywall 删了, 不是 must-have)
- [ ] AI API key 上 Keychain (现在 Secrets.xcconfig 也够)
- [ ] App Preview 短视频 (15-30s, 上线后再补)

### 🟢 锦上添花
- [ ] App Group (将来加 home screen widget 才需要)
- [ ] Custom domain `maso.app` 替代 GitHub Pages

---

## 5. 重要技术细节 (容易忘的)

### StoreKit 2 — 怎么在本地测
- `Maso.storekit` config 只在 **Xcode Run + debugger attached** 时生效
- 走 `./scripts/install_iphone.sh` (devicectl install) 装的版本走真 App Store, 没在 ASC 注册前 product 会 load 不到
- 测 IAP flow 要 Xcode 打开项目 → Run with iPhone destination

### Anatomy 图
- 已经被反复改坏 4 次, 最终回到 react-body-highlighter baseline
- **不要再尝试重画** — 用户明确说"完全不能用"
- 位置: `Maso/Data/Anatomy.swift`

### TrainingMiniBar 定位
- 必须用 `.safeAreaInset(edge: .bottom)` per-tab, 不是整个 TabView
- 整体 TabView 加 safeAreaInset 会让 MiniBar 跟 TabBar 视觉粘连

### Pro 状态
- `DataStore.makeMock()` 现在默认 `proSubscription: nil`
- 开发期临时解锁 AI 等 Pro 功能, **临时**改成 1 年订阅, **上线前必须改回 nil**
- 注释里已经写了恢复模板

### URL Scheme
- `maso://` 已注册到 Info.plist CFBundleURLTypes
- `maso://import?plan=<base64>` — PlanShareCodec encode/decode
- `RootView.swift` `.onOpenURL` 拦截 → 弹 ImportedPlanSheet

### Cloudflare Worker AI Proxy
- 部署在 `https://maso-ai.wuyumo.workers.dev`
- 客户端 token 在 `Secrets.xcconfig` (不入 git)
- DeepSeek API key 在 worker server-side env var
- 客户端反编译 .ipa 拿不到真 key

---

## 6. 开放问题 / 未来 TODO

### 等用户决策
- **AI 是否 Pro-only?** 现在没真 gate, 任何人填 key 都能用. 上线后是否要 server-side 验 receipt? 见 `AIWorkoutService.swift:48` 注释
- **App Preview 视频** 上线后做不做? 影响 conversion 但不影响过审
- **Custom domain** `maso.app` 要不要从 GitHub Pages 切

### 等代码实现
- iCloud Drive ubiquity (`docs/cloudkit-todo.md` 有方案)
- Keychain 升级 (AI key 现在 @AppStorage, 长期不安全)
- Home Screen Widget (现只有 Live Activity)
- Watch app companion (用户没提过, 但 fitness 类很常见)

### 等 Apple
- TestFlight build 处理 (上传后 10-30 分钟)
- App Review 等待 (1-3 天)
- 价格档对各地区的兑换 (Apple 自动算, 但 ¥35 / month 在国内可能偏高, 后期可调)

---

## 7. Files at a glance

### 重点新建 (这次会话)
```
Maso/Data/SubscriptionManager.swift          StoreKit 2 manager
Maso/Data/CommunityPlans.swift               8 seed community plans + materialize
Maso/Data/PlanShareCodec.swift               maso:// deep link encode/decode
Maso/Data/MuscleStatusComputed.swift         肌肉状态计算 (frequency / recency)
Maso/Views/Components/SwipeableRow.swift     自定义 swipe 容器
Maso/Views/Components/ProBanner.swift        Pro 横幅
Maso/Views/Components/LimitedFlowLayout.swift FlowLayout helper
Maso/Views/Components/TrainingSettingsSection.swift 共享的 Training 配置 section
Maso/Views/Components/Share/UnifiedShareCard.swift 整合的分享卡
Maso/Views/Screens/CommunityScreen.swift     社区训练计划
Maso/Views/Screens/ImportedPlanSheet.swift   maso:// import preview
Maso.storekit                                 StoreKit local config
docs/terms.md                                 Terms of Service (中英)
docs/app-store-connect-walkthrough.md         ASC 操作手册
docs/session-memory-2026-05-22.md             本文
```

### 重点修改 (这次会话)
```
Maso/MasoApp.swift                  + SubscriptionManager 注入
Maso/Views/RootView.swift           safeAreaInset per-tab; paywall 拆注释
Maso/Views/Tabs/TrainingMiniBar.swift iOS Now-Playing 风格重做
Maso/Views/Screens/PaywallScreen.swift StoreKit 真接 + URL + Cloud sync 删
Maso/Views/Screens/SettingsScreen.swift Health & Safety + About section
Maso/Views/Screens/HistoryScreen.swift 照片 + BodyHint 并排居中
Maso/Data/PlanSegments.swift        flexibility 不用 countdown
Maso/Data/DataStore.swift           makeMock 默认 free tier
Maso/State/TrainingSession.swift    完成组 haptic 扩到 flexibility
Maso/State/SpeechManager.swift      print → #if DEBUG
Maso/State/LiveActivityManager.swift print → #if DEBUG
Maso/Models/Settings.swift          ProSubscription: Equatable
project.yml                         schemes + ITSAppUsesNonExemptEncryption
docs/_config.yml                    exclude 内部 docs
docs/index.md                       link Privacy + Terms
Maso/Resources/*/Localizable.strings 16 个新 key × 12 lang
```

---

## 8. 给下次会话的提示

如果你 (Claude) 是下一次接手:

1. **先读 `PRE_DEPLOY.md`** — 现在大部分项已经完成, 但留作历史
2. **再读本文** — 知道这次都干了啥
3. **跑 `git status`** — 看有没有新累积的未提交工作
4. **看 ToS / Privacy URL 是否依然 reachable**:
   ```bash
   curl -I https://wuyumo.github.io/Maso/{privacy-policy,terms}.html
   ```
5. **App Store 状态查询**: 让用户登录 <https://appstoreconnect.apple.com> 看当前 build 状态
6. **不要**:
   - 主动重画 anatomy 图
   - 主动加社交 / 徽章 / XP 功能
   - 用 `Maso/Secrets.xcconfig` 里的真 key 跑测试 (用 placeholder)
   - 在 production 把 `proSubscription` 硬编码成非 nil

7. **要**:
   - 改完代码自动 `./scripts/install_iphone.sh`
   - i18n 改完跑 `python3 scripts/lint_translations.py`
   - 用户说 "Hi-Fi 设计稿" 时记住是 native Figma node 不是截图

---

**Last updated**: 2026-05-22 by Claude (session-id 787434f9)
**Repo HEAD**: `ed97c79` "Hide internal dev docs from public Pages site"
