# Coach Tab — Routines + Exercises 合并为 AI 对话 tab (交互框架, 2026-07-09)

> 方法: 地基勘察(代码事实) → 三方案并行(A 纯聊天 / B 工作台混合 / C 画布) → 三评审(苛刻健身用户 / 仓库工程师 / IA·设计系统)。
> 评审排序: 健身用户 C>B>A, 工程 B>A>C, IA B>C>A → **B 骨架 + A/C 关键零件**。
> 完整方案与评语存档: 见本次 workflow 产物 (design.json)。

## 0. 全局 IA 变化

- Tab bar: **Today / Coach / Progress** (4→3)。Today=今天练什么+开练, Coach=对话式生成与管理 routines, Progress=数据。
- Exercises 不再是 tab → Coach 导航栏 dumbbell 一步拉起 `ExerciseLibraryBrowser(asTab:false)` (组件本就支持 sheet 形态, 零改动)。
- Plans tab (PlansScreen 正文) 整体退役, 能力全部迁入 Coach; 复用件清单见 §6。

## 1. Coach tab 三段式布局 (方案 B 骨架)

```
┌ NavBar: "Coach"        [dumbbell] [gearshape] ┐
│ SAVED 货架 (常驻, 不随滚动消失)                  │  ← owner "很显眼" 硬要求:
│  [卡][卡][卡][全部→]      🔖 bookmark 计数       │    结构兑现, 不靠动效
├───────────────────────────────────────────────┤
│ 对话流 (滚动)                                    │
│   AI 问候 / 主动建议气泡 (优化卡化身)              │
│   [Context 偏好卡: kicker+prefSummary+铅笔✎]     │
│   用户气泡 (accent 12% 底, 非实心绿)              │
│   AI 回复: 教练短评 + DAY 1..N routine 卡         │
│     每卡: ✨AI badge · 🔖 Save/Saved · ▶ · tap详情 │
│   [suggestion chips: 换器械/短一点/少练腿…]       │
├───────────────────────────────────────────────┤
│ Composer: [+] [输入框…………] [↑发送]               │  ← 训练中(MiniBar 在场)整体收起
└───────────────────────────────────────────────┘
```

### SAVED 货架 (顶部常驻)
- 横滑紧凑卡 (名称+meta+▶), `safeAreaInset` 钉住; 空态显示引导句。
- "全部" → sheet 承载完整管理 = 现 TodayScreen(mode:.myPlans) 整块 (删/编辑/照片导入/优化卡), 一件不丢。
- 保存动作的反馈 = 货架计数 +1 弹跳 (飞入动效留 V2 糖, 工程评审判定 toolbar matchedGeometry 不可行)。

### 对话流
- 一次生成 = 一条 AI 消息: 一句教练短评 + **DAY 1..N 卡组** (C 的"周方案"框定, 消解多候选 vs 单焦点矛盾; N=weeklyTrainingDays 夹 2...4)。
- 修订轮: 新消息追加 (不原地 morph, 老版本留在流里可捞), 变更的动作 pill 加 accent 描边 = 客户端 diff (C 的 reconciliation, 渲染前抹平 LLM 抖动)。
- 深链消息 (Progress AI 小结 Apply / 优化建议): 渲染成带来源 kicker 的用户气泡 ("FROM WEEKLY SUMMARY" 10pt uppercase + arrow.turn.down.right) 并**到达即发送** (A 的最佳零件)。
- 空态三层: AI 问候 → Context 偏好卡 (kicker + prefSummary 一行灰字 + **铅笔尾 icon** → TrainingPreferencesSheet; 落实 owner 的"编辑 icon"要求) → suggestion chips。
- **长按结果卡里的动作行 → 引用式定向反馈** ("换掉 {动作}, 肩不舒服") — 健身用户评审钦点必须 V1: 用户对计划的意见 90% 是针对单个动作。
- 等待态: 诚实渐进清单 (复用 AIGeneratingView 模式) + 预期时长; **绝不做假打字机** (无流式, 45-60s 上限, 三案共识)。
- 生成任务收归 **DataStore 层** (A 的零件): 切 tab/锁屏回来生成继续, 结果不再是 view @State 即丢。

### Composer
- `[+]` 菜单只放**工具** (IA 评审裁定, 一行一语义): Training Preferences / Browse Classics / 照片导入 / 新对话。
- chips 行只放"点了即发"的 suggestion (换器械 / 时间减半 / 加练背…)。
- 训练中 (TrainingMiniBar 在场) composer 整体收成一颗球, 避免 TabBar+MiniBar+Composer+键盘四层叠 (RootView:162 有历史翻车判例, 此叠层组合必须进 verify-app 断言)。

## 2. Save 交互 (owner 上一条意图并入)

- 卡片按钮: **bookmark (未存) ↔ bookmark.fill (已存)**, Save↔Saved 开关式可反复切换 → `AddToPlansButton` 改造 + DataStore 加 `unsavePlan`。
- 一致性升级 (工程评审): 保存时记录 **planId 映射** 取代纯签名反查, 修掉签名漂移边界 (Classics 改名后识别不了已存)。
- PlanDetailSheet browse CTA 同步换 bookmark 语言。

## 3. LLM 侧 (分期)

- **V1 不做真多轮**: 沿用 one-shot `generateAIRoutines(focusNote:surface:)`, 每轮 prompt 追加「上一轮结构摘要 (assistant 压缩) + 用户新 feedback」+ 定向 token (`ONLY MODIFY Day 2` / `ONLY MODIFY {exercise}`); **修订轮永远保留负重进阶硬约束块** (不许拿它腾 token)。
- 本地**版本栈**: 每轮 plans 快照数组 (签名+timestamp), "捞回旧版"零 LLM 成本 (C 的零件)。
- V2 真多轮 messages (Worker 透传, 不用改) + `what_changed` 字段驱动 diff + "记住这条" → appendCoachNote (记忆管道现成)。
- 拆掉 onAppear 自动生成 (附带修 P2 "每次进 tab 烧一次 LLM")。

## 4. 周边回路

- AppRouter.pendingSummaryFocus 深链改指 Coach tab; tab_switch 埋点加 coach 映射; 生成/保存沿用 ai_routine_generate_* / routine_save (+新增 routine_unsave); 聊天文本不进 analytics (PII)。
- 免费/Pro: 保存上限 gate 原样保留 (iapEnabled=false 时不生效); 生成次数 gate 留位不实现。
- Today tab / 中央键 / 播放器 / Watch 全部不动。

## 5. 分期

**V1 (最小可发)**: 三段式 CoachScreen + one-shot 修订环 + 版本栈 + bookmark 开关 + SAVED 货架/全部 sheet + dumbbell 库入口 + [+] 工具菜单 + chips + 深链改道 + 长按动作行定向反馈 + 拆 Exercises/Plans tab。
**V2**: 真多轮 + diff 高亮 + 记住这条→coachNotes + 飞入动效 + AI 主动递 Classics 卡。

## 6. 复用件 (地基勘察)

WorkoutCard(compactLayout+addAction) / AddToPlansButton / savePlan·isPlanSaved / TrainingPreferencesSheet / TrainingSettingsSection.coachMemorySection / ExerciseLibraryBrowser(asTab:false) / ClassicsSheet / TodayScreen(.myPlans) / PlanDetailSheet / aiGenerating 状态机 / FlowLayout chips / AppRouter 深链 / RoutineOptimizeCard→AI 主动气泡。
拆迁: PlansScreen 正文、Exercises tab 挂载、TrainPage/handleCenterPrimary 等遗留死代码一并清。

## 7. 已识别风险

1. 60s 无流式等待 × 聊天心智 = "已读不回"体感 → 诚实渐进清单 + 明示时长 + 生成收归 DataStore (可切走再回来)。
2. 修订轮 JSON 漂移 (LLM 重写未被要求改的天) → 客户端 reconciliation: 未提及的 Day 用上一版原数据回填。
3. 底部四层叠 (TabBar/MiniBar/Composer/键盘) → verify-app 加全态断言 + 真机过。
