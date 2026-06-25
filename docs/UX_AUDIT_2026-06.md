# Maso 新用户 UX/QA 深度走查 (2026-06-23)

来源: 9-agent 工作流 (8 个面并行审计 + 完整性 critic), 以"全新用户"视角找困惑/死路/摩擦。
共 ~45 条。下面按主题 + 严重度归类 (🔴 高/阻断 · 🟠 中 · 🟡 低), 每条带"问题(新用户视角) → 建议"。
⚠️ 标 [本轮新增] 的是这个 session 我刚做的改动引出的问题 —— 优先级最高 (新引入的)。

---

## A. [本轮新增] 我刚做的改动引出的回归/风险 — 先修

1. 🔴 **Onboarding 性别门更隐蔽了** (我把默认选中改成 nil) — `OnboardingScreen.swift:44-58`
   只有点性别 pill 才推进, 但它不像"必选", 又没有 Next 按钮; 现在连"已选中"的视觉线索都没了。新用户填完年龄体重可能卡死在 step1 没有前进入口。
   → 给性别行加"选一个继续"提示/微动效, 或加一个常驻的 disabled「继续」按钮 (选了性别才亮)。

2. 🔴 **回退键静默删掉一组记录, 图标不变** (R2) — `PlanPlayerScreen.swift:213-223` / `TrainingSession.undoLastCompletedSet`
   播放头在已完成动作上时 ◀ 从"上一动作"变成"删掉最近一组 + 删历史记录", 图标和 a11y 标签都没变, 无确认无 toast。新用户想看上一个动作却把记录删了。
   → 该态下图标换成 `arrow.uturn.backward`、a11y 改"撤销上一组"、删后给 haptic + "已撤销一组" toast。

3. 🔴 **全局同步静默改写所有 routine, 且编辑弹窗文案是反的** (R3) — `PlanPlayerScreen.swift:315-319,1197-1201` + 文案 `:2759-2762`
   同步默认开, 训练中改重量会立刻写进所有含该动作的 routine; 但编辑表底部文案仍写"仅本次训练生效, 永久保存请去计划编辑" —— 与实际行为矛盾。
   → 同步开时文案改成"会更新所有用到该动作的计划"; 或训练中不实时传播, 改到结束保存时再传。

4. 🟠 **Exercises 滚动收起搜索条无兜底入口** (滚动收起) — `ExerciseLibraryBrowser.swift:263-286`
   向下滚时搜索/筛选条整条消失, 没有常驻的搜索入口; 新用户长列表里滚下去后不知道还能搜。iOS18-25 是钉住的, 行为分裂。
   → 导航栏留一个常驻搜索 glyph (点了滚到顶/唤出条), 或只收起筛选 chip、搜索框保持可见。

5. 🔴 **"Exercise data"同步开关中文里漏译, 夹英文 routine/params** (我刚加的) — `zh-Hans...:967,976`
   标题"跨 routine 同步参数"、说明"…任意 routine…各 routine…"中文句子里夹三次英文 routine。
   → 统一译成"计划": 标题"跨计划同步动作参数", 说明里 routine→计划。

6. 🟠 **AI 生成过渡 over-promise** (我刚做的) — 见 §I「AI 承诺」, 跟全局 AI 关闭是同一个根问题。

---

## B. Onboarding / 首次启动

- 🟠 **中途退出全丢** — 所有输入是 view @State, 只在 confirm() 落盘; 后台被杀回来从 step1 重来 + 再放一遍 2.84s splash。→ 部分答案存 UserDefaults 可恢复; splash 首启后缩短/可跳过。 (`OnboardingScreen.swift:11-22`)
- 🟠 **术语跳变** routine→plan→workout — 同一条首启动线里三个名词。→ 统一成 routine。
- 🟡 **step3 可零选肌群确认** — 取消默认后空 wantStrengthen 静默生效。→ 要求≥1 或加"可不选=均衡"微文案。
- 🟡 **splash 每次冷启全程重放** — 无跳过。→ 首启后缩短/点击跳过。
- 🟡 **性别第一步必填却几乎没用上也没解释** — 本地模板根本不按性别分支。→ 可选/加一句用途/或挪出必经路径。

## C. 本地化漏洞 (中文模式露英文) — 这类一次性扫干净

- 🔴 **Today 主卡标题是英文** — 种子 routine 名 "Full Body A · Push / Quads / Pull" 等无本地化, 中文首页最显眼那行是英文。→ 给推荐计划名做 key/用已本地化的部位词拼。
- 🔴 **Community 筛选 chip** Level / Days/week / All levels / Any frequency 全英文 (en 源也缺)。→ 补 en+zh。
- 🔴 **自由训练主按钮** "Continue (N)" / "Start (N)" 中文里露英文 (选够了就从中文翻成英文)。→ 补 `"Continue (%lld)"` / `"Start (%lld)"`。
- 🔴 **历史明细重量永远标 "kg"**, 忽略 lb 设置 — `HistoryScreen.swift:1288`。→ 按 `settings.weightUnit` 显示+换算。
- 🟠 自创动作"网图搜索"子表 7 个键全英文 (`AddExerciseSheets.swift`)。
- 🟠 **"Workout"/"Playlist" 都误译成"训练计划"** (`zh:31,69`) — 播放器抽屉叫"训练计划"撞了 Plan 概念。→ Workout→训练, Playlist→动作列表。
- 🟠 Settings "Exercise photos" 行、Language 选择页 "Follow iPhone language (…)" 露英文。
- 🟡 多处 a11y 标签英文 (Playlist 拖柄/Collapse calendar/占位 "exercise-set")。

## D. 空状态 / 首日体验 (新用户第一眼)

- 🔴 **Today 肌肉状态卡首日空白且误导** — 零历史→灰人 + 图例对不上, 还显示绿勾"All caught up"(其实从没练过)。→ 零历史专属文案"练一次看恢复状态"。
- 🔴 **"Train the gaps" 首日生成 12 动作马拉松** — 所有肌群都算 gap → 一键塞 12 个动作、重量 0。→ <1 次训练前不显示该 CTA, 或封顶 4-5 个。
- 🔴 **Exercises 主列表零结果空白死路** — 搜不到=全空白屏 (而 picker/niche 都有空状态)。→ 复用 picker 的空状态 + "把'xxx'加为自创"。
- 🟠 **History 空态全 0 stats + 空日历** — 像坏掉。→ 空态加一句说明 + 去 Today 的入口。
- 🟠 三个绿色"开始训练"CTA 抢焦 (Today's Workout / Train the gaps / Free workout), 新用户不知先点哪。→ 只留一个主 CTA 实心, 其余降级。

## E. 隐藏手势 / 可发现性 (新用户根本找不到)

- 🟠 **Routine 卡删除/改名只有长按** (Today + Routines 列表), 无任何提示。→ 加"⋯"或换 List 用 swipe。
- 🟠 **PlanDetail 里替换/编辑/删除(swipe)+ 拖排序(长按)全隐藏** — 替换动作几乎没人能发现。→ 加每行"⋯"菜单或 Edit 模式显拖柄。
- 🟠 **Exercises 行 swipe (置顶/删/移回冷门)** 无入口提示, 删自创/移回只有 swipe 一条路。→ 详情页加删除入口或长按菜单。
- 🟠 **History 删除会话** 只长按; 明细删动作 list 是 swipe、grid 是长按, 不一致。→ 统一 + 加可见入口。
- 🟡 播放器播放列表 reorder/swipe 提示 9pt 太淡且只提 reorder。

## F. 一致性 (术语 / 图标 / 品牌)

- 🟠 **plan / routine / workout 三词混用** — Tab 叫 Routines 但弹窗"Delete plan?"、Settings"Plans…"、两个"+"菜单项目和措辞都不同 (New workout vs Create from scratch)。→ 每语言定一个词全局扫 (en=Routine, zh=训练计划)。
- 🟠 **品牌名 Maso vs Masso 混用** — Apple Health 说明里"Masso saves…", 别处硬编码 Text("Maso Pro")。→ 统一 Masso。
- 🟡 AI vs Classics 不解释 (Classics 是啥没说); Community/Classics 内部命名也乱。→ Classics 页加一句说明 + 统一词。
- 🟡 完成休息态 "Switching"+"Next Exercise" 两个词同屏表达同一刻。

## G. 分享 / 导入 / Apple Watch

- 🔴 **朋友的 maso:// 邀请链接在 onboarding 期间被丢弃** — `.onOpenURL` 只挂在已完成分支; 新用户从邀请链接进来→引导页, 链接静默吞掉。病毒拉新路径断。→ `.onOpenURL` 提到 RootView 顶层, 未完成引导就暂存、引导完再弹。
- 🔴 **Watch 按钮在 iPhone 不可达时静默失效, 但还是震了** — `WatchBridge.send` 直接 return; ✓ 照样给 haptic 但没记录、UI 不前进。新用户以为表卡了。→ 发送成功才震 + 显示"在 iPhone 打开 Masso"/排队重发。
- 🔴 **Watch app 在 iPhone 端完全不可发现** — 全 app 没一处提到有手表伴侣。→ 播放器或设置里一句话提示 (检测 isWatchAppInstalled)。
- 🟠 **分享卡占位 QR → 404** (上架前) — 见 §J 待办, 上架后换真链接。
- 🟠 **History 分享卡没有 QR** (其它卡有) — `UnifiedShareCard` 传 nil。→ 统一传 appStore 链接。
- 🟠 **导入只支持相册选图, 没有实时扫码** — 卡上画了 QR 邀人"扫", 但 app 内没相机扫码入口; 收图者得先存图再去+菜单导入。→ 加相机扫码, 或把卡上 QR 明确成"下载 App"而非"扫码导入"。
- 🟠 导入入口埋在"+"菜单第 5 项; 空态也不提导入。→ 空态加"从截图导入"。
- 🟡 选图失败/OCR 失败静默或死路 alert; 未匹配的 OCR 行只能替换不能加。

## H. 无障碍 / 权限

- 🟠 **全 app 无 Dynamic Type** — ~480 处硬编码字号, 完全无视系统字号/大字号设置 (健身用户偏年长 + App Store 无障碍预期)。→ 主阅读文本用 `relativeTo:`/`ScaledMetric`, AX1-3 测。
- 🟠 **Apple Health 开关无结果反馈, 拒绝后死路** — 点 Don't Allow 开关仍显示开、永远不写、无法再次弹窗。→ 反映真实 authStatus + 深链 iOS 设置。
- 🟠 **首次训练第一组休息时弹通知权限** — 高专注时刻冷弹, 易被拒。→ 加 app 内前置说明或挪到完成页再请求。
- 🟡 Apple Health 文案对没手表的人承诺读心率 (多数人用不上)。

## I. 产品决策: "AI"承诺 vs 现实 (重要, 需你拍板)

- 🔴 **app 全程打"AI"旗号, 但 AI 实际关闭且无处开启** — splash 写 "My Personal AI Trainer"、onboarding 我刚加的"Creating your AI plan", 但 `aiWorkoutEnabled` 默认 false 且**设置里没有开关**, `AIWorkoutService` 也未配置 → 模型从不被调用; 用户拿到的是本地模板 + 启发式。
  这同时影响: App Store 名 "Masso — AI Workout Planner" + 我刚做的 AI 生成过渡 = 都在承诺一个当前交付不了的能力。
  **三选一 (你定)**:
  - (a) 真接上 AI: 设置加开关 + 配 `AIWorkoutService` 代理/token (服务端, 工作量大)。
  - (b) 诚实化文案: splash/onboarding 改成"为你挑选起始计划"之类, 不提 AI compute。
  - (c) 折中: 保留 AI 品牌叙事, 但过渡文案 + 生成内容对齐"基于你的偏好" (不暗示实时大模型)。
- 🟠 AI 今日计划失败完全静默 (只有 Free workout 的 Smart pick 会提示) — 若启用 AI, 失败应一致提示。

## J. 上个版本过审后的待办项 (一并处理)

- [ ] **发布**: 1.0(6) 已过审; ASC 设的是"自动发布"→ 过审即自动上架。想手动控时间则过审前改手动。(你说"准备分发了" = 应已在分发)
- [ ] **分享卡真 QR**: 上架后把占位 `MasoLinks.appStore` 确认指向 `https://apps.apple.com/app/id6776689750` 并验证返回 200; 顺带让 History/per-session 卡 (`UnifiedShareCard`) 也带上同一 QR (现在没有)。
- [ ] **补译残留英文**: 见 §C 一次性清 (Today 卡名 / 筛选 chip / 自由训练按钮 / kg-lb / 各零散键)。
- [ ] (以后) IAP: 翻 `iapEnabled=true` 时重跑 save-cap/paywall 全流程 (现在是 dead code 没被真实用户走过) + 恢复 Restore 按钮。

## K. 建议的下个版本批次 (待你点头)

- **P0 (新用户阻断/我引入的回归/中文露英文)**: §A 全部 + §C 全部 + §D 三条 🔴 + §G maso链接丢弃 + §I 选一个方向。
- **P1 (空态/可发现性/一致性)**: §D 剩余 + §E 全部 + §F 术语&品牌统一 + §G watch 反馈&发现 + §H health 反馈/通知时机。
- **P2 (打磨/以后)**: Dynamic Type、splash 跳过、onboarding 断点续填、dead code 清理、真接 AI、live 扫码。

> 等指令后开始改。改完跑 verify-app + 装机, 再走下个版本上架 (bump build)。
