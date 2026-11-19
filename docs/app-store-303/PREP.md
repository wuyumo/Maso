# Masso 3.0.3 隔离准备 — 未打包、未上传、未提审

父交付核验用。本文只描述这个云端分支实际改了什么、跑了什么、以及仍不能声称的事。正式提审前必须由父交付核验后再确认。没有 App Store Connect 写入、上传、提审、发布、部署、广告操作、购买或试用。

## 源与范围

- 基线：`a0b034245618a57cdfe911ccbb79b7d98cf7ee6d`（2026-11-15 10:53:32 +0800，`Update Masso app and supporting services`）。
- 本环境克隆里的 `origin/masso/pro-device-48` 尖端就是这个 SHA。它不是归档当时的 HEAD 证明。baseline intake 已说明该提交晚于 3.0.2(54) 提审，只是 1,028 个可比对、非敏感的受审文件 hash 与历史 manifest 一致。
- 未纳入、也未改写：Mac 工作区的 46 个已修改文件、2 个已删除文件、未跟踪文件，以及仅存在于那台 Mac、尚未推送的 4 个 backend 提交（`cc29d0bd`、`52eb3947`、`8cf7c807`、`30d9193b`）。
- 本分支相对基线的意图差异只有：三个手维护 Info.plist 的营销版本与 build 候选、`docs/app-store-303/` 的已批准 ASO 包和准备说明、`scripts/check_303_prep.py`、以及 `docs/app-store-metadata.md` 顶部的指向。`project.yml`、`project.pbxproj`、entitlements、bundle ID、Team、签名、地区和 App 显示名没有改。
- 这个提交里没有 `AGENTS.md`（`DESIGN.md` 仍引用它）。版本号继续按 `project.yml` 的既有约定只写在三个 Info.plist，不往 yml 加 `info:` 块，也没有运行 `xcodegen`。

## 版本候选

| Target | 营销版本 | Build | 显示名 |
| --- | --- | --- | --- |
| Maso | 3.0.3 | 55 | Masso |
| MasoWidgets | 3.0.3 | 55 | Masso Widgets |
| MasoWatch | 3.0.3 | 55 | Masso |

Build `55` 的状态是 `PENDING_LIVE_ASC_CONFIRMATION`。目前只知道历史回执里的最高已上传 build 是 3.0.2 的 54；本环境没有做实时 ASC 查询。若实时列表里已有大于或等于 55 的 build，归档前要把三个 plist 的 `CFBundleVersion` 一起提高，不能只改其中一个。

en-US 商店名候选是 `Masso — Workout Tracker`。zh-Hans 商店名保持 `Masso - AI健身计划`。这两个字符串没有写入 `CFBundleDisplayName`。主屏幕名称仍是 Masso。

## ASO

`docs/app-store-303/candidate/` 是已批准准备包的逐字节副本，状态仍是 `PREPARED_ONLY_NOT_APPLIED_TO_ASC`。

- en-US 名称 `Masso — Workout Tracker`，副标题 `AI Plans & 3D Muscle Recovery`，关键词为 97 个 ASCII 字符：`strength,training,gym,log,planner,weightlifting,sets,reps,routine,progress,dumbbell,barbell,watch`。
- zh-Hans 名称未改；副标题为 `力量训练记录与肌群恢复估算`。
- 描述只替换第一条功能 bullet 之前的介绍。权益、额度、7 天试用、自动续订、估算和非医疗说明、隐私与条款链接、导入限制都从捕获的 ASC 文本原样保留。英文保留段写的是自动续订和在 Apple 账户设置中管理，没有单独的 “Restore Purchases” 句；中文保留段写的是自动续费以及可在 Apple 账户设置中管理或取消。本轮没有补写新的恢复购买句。
- 其余 10 个 locale、类别、地区、价格和发布设置不在本包内，也不在本分支改动里。
- What's New 使用 `candidate/review-only/`，只说明商店信息更新，不宣称新功能或修复：
  - en-US: `Updated App Store information to clarify workout logging, AI plans and muscle recovery estimates.`
  - zh-Hans: `更新 App Store 信息，更清楚地介绍训练记录、AI 计划与肌群恢复估算。`
  若后续原生分支加入产品修复，提交前必须重写这两句。当前源码差异没有产品行为修复。

应用前仍要重新读取 ASC，并与 `candidate/before/` 比较。before 已变就停止覆盖。

## 依赖、签名与复现缺口

这些缺口按 intake 保留，没有用静态检查把它们补上：

- 历史 `Package.resolved` SHA256：`da7cc237d2f4afcbd74ecdb944b6f35681dfb2c8f51f39305f85f5ea61142e72`。文件被 `.gitignore` 忽略，基线 Git 与本检出都不存在，本分支没有制造或提交它。
- 声明仍然是 MuscleMap `from: "1.6.4"` / `upToNextMajorVersion`。这与基线工程一致，但不是 revision 锁。
- 2026-11-19 对公开 GitHub 标签的只读查询：`1.6.4` 当前指向 `7dc03071e03052e8bd4f6351e9176994cd28aa7d`。同时存在更新的 `1.7.0`、`1.7.1`、`1.8.0`、`1.9.0`。没有这份历史 lock 就执行 resolve，会升到当前 1.x 最新版。本轮没有 resolve，也没有升级。标签以后仍可能移动，所以这次查询不能代替 lock 文件。
- `Maso/Secrets.xcconfig` 与 `Maso/Secrets.xcconfig.example` 都在 intake 的 hash 比较之外。example 仍在 Git 中且本轮未改；真实 Secrets 未读、未复制。example 第 17 行主 URL 仍写成 `https://...`，xcconfig 会把 `//` 当注释截断。第 20 行注释要求备用 URL 使用 `https:/$()/`。不能用 example 直接复制出归档配置，也不能据此推断那份未读 Secrets 的内容。
- 历史 IPA SHA256 `8ce7b27ce2b56b334e06adaee02df90203dc937027780fb8b9461817694a4711` 只来自 intake 中的旧回执。本检出没有 `build/export54/Maso.ipa`，没有 xcarchive，不能重算。
- 历史 manifest 里不在 Git 的 4 个路径（3 个 `.DS_Store` 与 `Package.resolved`）没有补进仓库。

## 本环境实际跑过的检查

Linux 云端，没有 Swift 工具链，没有 `xcodebuild`，没有模拟器。私有 Mac worker 本轮不使用。下面的通过不能代替原生编译、签名或测试。

| 命令 | 退出码 | 结果 |
| --- | --- | --- |
| `python3 scripts/check_303_prep.py` | 0 | PASS。三个版本一致，身份文件 hash 未变，lock 状态 `absent`，ASO 包 PASS。 |
| `python3 scripts/check_303_prep.py --self-test` | 0 | PASS，9 项：基线加上 8 个内存反例。 |
| `python3 docs/app-store-303/candidate/validate.py` | 0 | PASS。描述尾部与捕获文本字节相同；无网络、无写入。 |
| `python3 docs/app-store-303/candidate/validate.py --self-test` | 0 | PASS，7 项。 |
| `python3 scripts/lint_translations.py --check` | 1 | 既有失败，不是本分支引入。 |

完整静态输出在 `cloud-static-results.json`。

翻译 lint 的既有结果：19 个 Swift 字面量没有进 `en.lproj`。其中与本轮焦点有关、且会到达用户的是设置里的 `Manage Subscription`，以及恢复进行中的 VoiceOver 标签 `Restoring`。`Finish restore` 只存在于 DEBUG 且 `MASO_RESTORE_HOLD=1` 的测试钩子。zh-Hans 不在“缺 key”列表里；另外 10 个 locale 各缺 `Include photo`。zh-Hans 与英文完全相同的 16 个 key 是单位、品牌和一处署名，不包括恢复购买、分享或训练报告标题。本轮没有改这些字符串。

静态合同核对通过：`PaywallUITests` 里 12 种语言的 “Restore Purchase” 标签与对应 `Localizable.strings` 一致；en / zh-Hans 的空恢复结果、Share、Workout report 都在。

## 原生门禁

这些测试在本环境不能编译，也不能运行。清单来自源码阅读，不是执行结果。

恢复购买：

- `MasoUITests/PaywallUITests.swift` 的 `PaywallUITests` 与 `ProBannerUITests` 都在 `setUp` 调用 `SKTestSession(contentsOf:)`，各一处。会话创建失败时，整类测试在断言前失败，包括只检查按钮文案的用例。
- `MasoTests/SubscriptionTests.swift` 另有 4 处 `SKTestSession(contentsOf:)`，其中 `testRestoreWithoutSubscriptionReportsTheExistingFailure` 断言 `lastError == "No active subscription found"`。
- `MasoExerciseUI` scheme 的 Test action 没有挂 StoreKit 配置文件；UI 测试从测试包里的 `Maso.storekit` 自己建会话。`Maso` scheme 的 Run action 才引用 `Maso.storekit`。
- 实现是 `SubscriptionManager.restore()`：`AppStore.sync()` 后刷新 entitlement；没有当前订阅时把 `lastError` 设为本地化的 `No active subscription found`。付费墙恢复按钮标识是 `paywall.restore`。

WorkBuddy 所说的 PaywallUITests StoreKitTest Code 3、以及 iPhone 17 Pro / OS 26.5 失败，仍是未验证假设。本环境没有 Apple SDK，不能把 Code 3 对应到某个枚举，也没有 `.xcresult`。它和恢复文案不一致不是一回事：文案静态核对是齐的。会话没建起来时，不能把整类失败解释成恢复购买逻辑坏了。

训练开始、结束、报告、历史和分享：

- `SessionReportUITests` 没有 `SKTestSession`。StoreKitTest 失败不能解释这组测试。
- 需要原生跑的用例至少包括 `testHomeStartButtonOpensThePlayer`、`testFinishedReportExitsThroughProductionRootAndCanStartAgain`、`testFinishExitLeavesTheReportAndHistoryUsesBack`、`testAggregateRowsAndNativeSharePreviewAcrossLanguages`。后一个覆盖 en、zh-Hans、ar 的汇总行和系统分享预览。
- `testAggregateRowsAndNativeSharePreviewAcrossLanguages` 在最多 5 次上滑后要求 sparkline 为 80×20，并给分享预览 8 秒。`testRecordFiveExercisePreview` 与预览录制用例使用 `Thread.sleep`。这些结构可以造成不稳定，但本环境没有运行，不能把 WorkBuddy 的 flaky 说成已复现，也不能说与现有测试无关。
- 分享预览由 `workout.sessionReport.share` 打开，确认按钮是 `workout.sessionReport.previewShare`。历史入口用例期待标题 “Workout Summary” / 返回 `workout.sessionReport.historyBack`。

AI 计划与额度：

- 单元门禁是 `DeviceAIQuotaTests`、`ProAccessPolicyTests`、`AIRoutineSelectionTests`。它们不使用 `SKTestSession`，但仍要 iOS XCTest，本环境没有跑。
- UI 侧额度与付费墙场景在 `PaywallUITests`（`device-quota`、`device-notice`）以及 `ExerciseLibraryBrowserUITests.testAcceptedWeeklyFrequencyProducesThreeActualAIRoutines`。后者会走真实 AI 路径，原生复跑前要单独确认网络和 Secrets，不能当成离线合同。

中英：上述 UI 用例里的 en 与 zh-Hans 分支都要在原生结果里单独保留，不能只看英文截图。

## 已看到、本轮不修的风险

- 没有历史 lock 时，MuscleMap 会从 1.6.4 解析到当前 1.9.0。3D 肌群图可能因此和 3.0.2(54) 不同。归档必须使用 hash 匹配的那份 `Package.resolved`，并禁止 package update。
- `Manage Subscription` 与恢复中的 VoiceOver 标签 `Restoring` 没有翻译条目，中文界面会显示英文。这是既有缺口，不是本分支造成的。
- 3.0.2(54) 的 IPA 与 xcarchive 不在可检查路径上，二进制和签名没有复核。
- `a0b0342` 与三个 plist 的版本改动都不是归档时的脏工作区快照。

## 下一原生步骤

在干净检出本 PR 的机器上做，不要在脏的 `masso/pro-device-48` 工作区里归档，也不要把它的未推送提交推上来。

1. 实时读取 ASC。确认没有大于或等于 55 的 build，且 3.0.3 版本槽没有别人的草稿。把 `candidate/before/` 与当前 ASC 逐字段比较，不一致就停止。
2. 只把本机已有的 `Maso/Secrets.xcconfig` 放到检出里，不提交。不要按 example 现抄。
3. 只把本机已有的 `Package.resolved` 放到 gitignore 的原路径。SHA256 必须等于上面的历史值，且其中 MuscleMap 为 1.6.4、revision `7dc03071e03052e8bd4f6351e9176994cd28aa7d`。缺失或 hash 不同就停止，不要 resolve。
4. 用本机签名账户做 Release archive。核对 app、widget、watch 都是 3.0.3 与确认后的 build。记录 entitlements、隐私清单和签名，不改 bundle ID 或 Team `TW8ZVVX529`。
5. 跑上一节的单元和 UI 门禁，保留 `.xcresult`。StoreKit 使用测试会话，不做真实购买或试用。
6. 导出 IPA 并记录 SHA256。到这一步仍不上传。
7. 父确认源 SHA、干净差异、原生结果和 ASO 字段后，才创建 3.0.3、粘贴 `after/` 与 review-only What's New、挂 build。其余 10 个 locale、类别、地区和发布设置不动。
