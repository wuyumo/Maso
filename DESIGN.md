# Maso — Design System & Specifications

跨平台统一的设计规范。Web app(`Maso - iOS & Watch OS/`)和 iOS app(`Maso-iOS/`)都按这份文档来。

文档原则:**做减法,才是设计**。每个决策都要回答一个问题 —
> 它能让"在健身房记下这一组"变得更快,还是更慢?

慢的,砍掉。

---

## 一、底层理念(十条不可妥协的原则)

| # | 原则 | 落地表现 |
|---|---|---|
| 1 | **训练时优先** | 80% UX 价值在那 30 秒。大字号、单手可达、高对比 |
| 2 | **历史即计划** | 进入动作页, 上次重量最显眼; 自动建议下一组 |
| 3 | **一屏一焦点** | 做组只显示当前组目标 + 大「完成」 |
| 4 | **沉默的进步反馈** | 不催回、无徽章、无连胜。PR 小高亮足够 |
| 5 | **离线优先** | 本地数据 100% 可用; 云同步是 nice-to-have |
| 6 | **数据归用户** | 无注册墙、一键导出 |
| 7 | **可组合,不强制** | 允许换动作、跳过、调顺序 |
| 8 | **统一训练抽象** | 力量/有氧/瑜伽共用 `SetRecord` |
| 9 | **进阶式默认值** | 无「新手/高级」切换器; 默认值随次数演化 |
| 10 | **平台原生** | 用系统手势 (sheet 滑下、左滑等); 不模拟 web router 在 iOS 上 |

---

## 二、视觉系统

### 2.1 配色

| Token | 值 | 用途 |
|---|---|---|
| `accent` | **#1ED760** (Spotify 绿) | 主 CTA、强调、训练进度、当前段提示 |
| `text` | #FFFFFF | 主文本 |
| `textDim` | #B3B3B3 | 次要文本 |
| `textFaint` | #AEAEAE | 极次要 |
| `textSoft` | #CBCBCB | 数字 / 列表辅助 |
| `background` | #121212 | 主背景 |
| `surface` | #191919 | 卡片背景 |
| `surfaceHi` | #262626 | 卡片内的二级控件 (stepper 等) |
| `borderSoft` | white@8% | 分隔线 |
| `negative` | #F3727F | "结束训练" 等危险操作 |

**强调色只用一种**。不要彩虹。

### 2.2 字体 / 字号

| 用途 | 字号 | 字重 |
|---|---|---|
| 屏幕标题 ("今日训练" / "我的训练" / "训练状态") | 26 | bold |
| 动作名 (player 页) | 22 | bold |
| Section kicker ("今日推荐" / "STEP 1 / 3") | 10-12 | bold + 大字距 (tracking 2-3) + uppercase |
| 卡片标题 (plan name) | 16 | bold |
| 正文 | 14 | regular/bold |
| 数字 (组数 / 重量 / 倒计时) | monospaced digits, tabular-nums |
| 大倒计时 (休息屏) | 88 | bold |

### 2.3 圆角

- **极小 (chip / tag)**:8
- **卡片 / 弹层**:16
- **大卡片 / sheet**:24
- **药丸 / 圆按钮**:pill (= height/2)

### 2.4 间距 / 安全区(**强约束 — 不许 magic number**)

所有屏 / 组件必须从下面这套常量取值;不许在代码里散落字面量。

| Token | 值 | 用途 |
|---|---|---|
| `pagePaddingHorizontal` | **16** | 主屏左右安全距 (ScrollView 内容) |
| `pagePaddingTop` | **56** | 主屏顶部留白 (标题 / 状态栏分隔) |
| `pageBottomInset` | **80** | 主屏底部 Spacer (避开 78 高 TabBar) |
| `cardPadding` | **20** | 卡片 / 弹层内 padding |
| `rowPaddingH` | **12** | 列表行水平 padding |
| `rowPaddingV` | **8** | 列表行垂直 padding |
| `bottomNavHeight` | **78** | TabBar 高度 |
| `pillWidthActive` | **248** | 训练态中间 pill 宽度 |

iOS:`MasoMetrics.*` / Web:对应 Tailwind 工具类(`px-4 / pt-14 / pb-20 / p-5 / p-3`)。

**安全区**:iPhone 刘海 + Home Indicator 必须保留,用 `safeAreaInset` 或 `ignoresSafeArea(.container, edges: .bottom)` 控制底部 TabBar 贴底。

---

## 三、组件规范

### 3.1 BodyHint(双视图肌肉图)

**核心**:正面 + 背面**并排**显示,被命中的肌肉用 accent 高亮,其他用 #2A2A2A。

```
┌─────┐  ┌─────┐
│ 正面 │  │ 背面 │  ← gap 6px
└─────┘  └─────┘
```

- 用 SVG path (web) / Canvas 绘制 (iOS),不是位图
- 圆角:`CORNER_RADIUS = 1.4`(每个肌肉块的小圆角)
- 高亮色:**rgba(30, 215, 96, 0.85)** 在 player 页;**rgba(30, 215, 96, 0.78)** 在 Home 页
- 底色:**#2A2A2A**
- 描边:**#1F1F1F**, 0.25px

**region 自动裁剪**(根据传入的肌群自动判断):

| 区域 | viewBox y 范围 | 适用 |
|---|---|---|
| `upper` | 0..125 | 单纯上肢动作(胸/背/肩/臂/核心) |
| `lower` | 95..205 | 单纯下肢动作(腿/臀/小腿) |
| `full` | 0..200 | 复合动作(硬拉等) |

**Panel slot 模式**(`square` 参数):

| 场景 | square | 行为 |
|---|---|---|
| 列表行 (Plans / 训练计划) | **true** | 每个 panel 锁成 `height × height` 方块,所有行高度宽度都对齐;body 在 slot 内 aspect-fit 居中 |
| Player 动作信息行 | **true** | 切动作时 layout 不抖,name + chips 位置稳定 |
| Home 大卡 / History 整身 | **false** | 自然 aspect(默认),整身展示 |

> **核心规则**:**同一类区域,无论装哪个 region 的 body,显示尺寸必须一致**。否则列表里相邻行会忽宽忽窄,player 切动作时会左右抖。
>
> 解决:列表 / player 一律 `square: true`,首页大卡片 / History 一律 `square: false`(用自然 aspect 让整身看着舒服)。

**标准高度**(各场景对照表):

| 场景 | 高度 token | 值 |
|---|---|---|
| Home WorkoutCard | `bodyHintLarge` | **260** |
| History 7-day | `bodyHintHistory` | **240** |
| PlanPlayer 动作信息行 (square) | `bodyHintPlayer` | **72** |
| Plans 列表行 (square) | `bodyHintListRow` | **56** |

**胸只有三段**(`upperChest` / `midChest` / `lowerChest`),已彻底删除 `innerChest` / `outerChest` — 它们是空间维度标签, 跟解剖头维度冲突。

### 3.2 TimelineBar(顶部进度条)

播放器顶部一条横向条,每个 segment 一个小药丸。

**配色规则**:

| 段类型 | 过去 | 当前 | 未来 |
|---|---|---|---|
| **动作 (exercise)** | accent (绿) | text (白) | textFaint@40% (灰) |
| **休息 (rest)** | white@55% | white (100%) | white@15% |

**关键**:休息一律白色, 跟动作的绿色区分。

**宽度**:rest 段 `flex-grow: 0.28`,exercise 段 `flex-grow: 1`(休息条比动作条窄)。
**高度**:5px(细窄,不喧宾夺主)
**间距**:相邻段之间 3px gap

### 3.3 ExerciseImage(动作缩略图)

Spotify "album cover" 风格 — 两帧 cross-fade 动图(0.jpg + 1.jpg)。

- 默认圆角:4(列表)/ 16(player 大图)/ pill(MiniBar 缩略图)
- 失败回退:category 渐变色
- Category 配色:
  - `strength` → emerald 渐变
  - `cardio` → rose 渐变
  - `flexibility` → amber 渐变

### 3.4 WorkoutCard(今日卡片)

Home 页核心元素。

```
[今日推荐]          ← accent kicker, uppercase, tracking
推日 · 胸肩三头     ← 22px bold
                    ← 12px 描述

       [BodyHint]   ← height 260 (大), 居中
       [BodyHint]

[5 个动作]  [15 组]  ← chips, surfaceHi 背景

[ ▶ 开始这套训练 ]   ← accent CTA, pill, h-11
```

### 3.5 BottomNav

3-tab 固定底栏。双形态:

**无训练**:左 ← 中圆按钮 → 右
- 中间 64×64 圆按钮, `-translate-y-3.5`(上凸 14px,signature 视觉),accent 当选中,黑色其他状态
- 左右 SideTab `items-center`(图标在 cell 中心)

**训练中**:左 ← pill → 右
- 中间变成 **248px 宽** 横向 pill, 垂直居中(不再上凸)
- pill 内容:缩略图(36×36 圆形) + 名字 / meta + 主控按钮(36×36)
- 左右 SideTab `edge` 推到边(`pl-9` / `pr-9` = 36px 距离 cell 外边缘)
- **指示圆点必须跟图标竖向对齐**(嵌套 `flex-col items-center` 一组)
- 用 200ms transition 平滑过渡

**pill 主控按钮的图标 / 配色**:

| 段类型 | 图标 | 背景 |
|---|---|---|
| 力量动作 | ✓ checkmark | accent (绿) |
| 休息 | ▶| skip-forward | text (白) |
| 计时动作 (cardio/flex) | play/pause | text (白) |

### 3.6 ActiveTrainingPill 行为

- 主体 tap → 打开 PlanPlayer(返回训练播放器)
- action button tap → advance / togglePlay(用 stopPropagation 隔开,不打开 player)
- 跟悬浮 MiniBar 共享同一份 session 状态; 在 tab-bar 路由上吸收 MiniBar 的角色; 在深页(Settings / 计划详情)悬浮 MiniBar 继续显示

### 3.7 PlanPlayer

```
═══════════════════════════════════ ← drag handle (可下滑收起)
■■━━━━━━━■━━━■━━━━━━━━■━━━■■━━━ ← TimelineBar (顶部进度)
                                  [ ⋯ ] ← 右上角 "..." 菜单

       ╔═══════════╗
       ║  动作图   ║
       ╚═══════════╝
                                   ← gap
   [BodyHint]   动作名             ← 双视图 + 信息行
       (88h)    1/3 × 10  20kg

                                   ← spacer
       [ ◀ ]  [   ✓   ]  [ ☰ ]   ← Controls (back/main/playlist toggle)

═══════════════════════════════════ ← InlinePlaylist(可折叠)
训练计划  1 / 4
• 1/3 × 10 · 20kg · 杠铃卧推
  3 × 10 · 哑铃飞鸟
  ...
```

**主控按钮**:
- 76×76 大圆,accent 背景,黑色图标
- 力量段图标 = ✓
- 休息段图标 = ▶| skip
- 计时段图标 = ⏸ 暂停 / ▶ 继续

**Back 按钮(左侧)**:
- 直接跳到**上一个 exercise**,跳过中间的休息段
- 没有更早的动作时按钮 disabled (opacity 30%)

**Playlist toggle(右侧)**:
- 收折时高度 0,展开时滑出 50svh / 320pt
- 展开图标变成 accent(暗示激活)

**"..." 菜单**:
- 绝对定位右上角
- 点击弹出 sheet:"**结束训练**"(红色,destructive)
- 点击后 `window.confirm` 二次确认 → "确定结束本次训练吗? 已记录的组数会保留。"
- 用语统一为 **"结束"**, 不是 "取消" — 用户是主动停止, 不是丢弃训练

**完成屏**:
- 全屏接管 player(不是 modal)
- 中央大 ✓ 圆(96px,accent)
- "已完成" uppercase kicker + plan name + CTA「完成」按钮 → 清 session + 回首页

**反竞态保护**:
- 主动结束训练时, 先标记 `endedRef = true`, 再 `end()` + `navigate(-1)`
- player 的 auto-restart useEffect 检查 `endedRef` 跳过, 防止 React 18 批处理把 session 复活

**Format**:
- 组数显示 **`{当前}/{总} × {次}`**, 用 `/` 不用 `-`
- 重量:`{val} kg`,monospaced digits

### 3.8 InlinePlaylist(播放器底部播放列表)

iOS Mail 风格左滑揭示编辑按钮:

- 默认收折,点 toggle 后展开
- 当前 step 用 accent@15% 背景高亮
- 当前 step 行格式 `1/3 × 10` (current/total × reps)
- 其他 step 行格式 `3 × 10` (total × reps)
- 左滑(dx < 0)露出右侧编辑按钮(小笔图标,无主色 — 不抢戏)
- 阈值:超过 `ACTION_WIDTH / 2 = 32px` 视为目标状态
- 行背景必须不透明(`rgba(10, 10, 10, 1)`),不然编辑按钮会从下面透出来

### 3.9 Settings 组件

iOS 风格列表项:

```
SECTION TITLE                       ← 12px bold uppercase tracking
┌───────────────────────────────┐
│  Label              [chips]   │  ← Row, h-14
├───────────────────────────────┤
│  Title                  [⚫━━] │  ← ToggleRow, 双行 (title + desc)
│  desc text 11px               │
└───────────────────────────────┘
```

- `Section` 标题在卡片外, surface 背景在内
- `Row` 高度 56,左右 padding 20
- `ToggleRow` 必须整行可点,switch 跟 title 同一行,desc 在下方
- `Choice` 是 segmented pill(选中 accent 黑字,未选中 textDim)

---

## 四、屏幕规范

### 4.1 Onboarding(首次启动)

**单页渐进展开**式 — 不是多步路由,而是一页内 step 1 → 2 → 3 逐渐露出。

```
STEP 1 / 3 (accent kicker)
先聊聊你的训练偏好
三个小问题, 选完直接确认...

╭─ Step 1 ─╮
你的基础信息
[男] [女] [其他]
年龄: ‒ 25 +
体重: ‒ 70kg +

╭─ Step 2 (做完 1 自动展开) ─╮
一周通常训练几次?
[1][2][3][4][5][6]

╭─ Step 3 ─╮
想加强哪些肌群? (多选)
[胸] [背] [肩] [二头] ...
[确认, 生成计划]
```

完成后,自动:
- 标记 `onboardingCompleted = true`
- 根据 wantStrengthen + weeklyTrainingDays 生成推荐计划(`recommendedPlanIds`)
- 跳到 Today

### 4.2 Today

```
[早上好]  ← greeting kicker (time-based)
今日训练   ← 26px

[WorkoutCard with BodyHint]

(没推荐时:)
[今天需要加强]
[一组帮你补齐的训练]
[BodyHint of recommendation muscles]
[chest, lats, ...]
[开始这套训练]
```

时段问候:
- 0-5 凌晨好 / 5-12 早上好 / 12-18 下午好 / 18-24 晚上好

### 4.3 Plans

```
[标题: 我的训练]    ← pt-14 顶部留白

[Card] 推日                    [▶]
       [BodyHint 64h]
       5 个动作 · 15 组

[Card] 拉日                    [▶]
       ...
```

### 4.4 History("训练状态" — 不叫"最近")

```
[标题: 训练状态]

╔═══════════════╗
║  整身 BodyHint ║  ← 7 天激活肌群, opacity 按距今远近递减
║  height 240   ║
╚═══════════════╝
近 7 天激活的肌群

[最近 set 列表]
动作名                          重量 × 次
日期 时间
```

### 4.5 Settings

不强加 native iOS 样式,用我们自己的 Section/Row/ToggleRow。

包含的 toggle / 控件:
- 重量单位 (kg/lb) — Choice
- 距离单位 (km/mi) — Choice
- 默认组间休息 — Stepper
- **中间按钮快捷启动** — ToggleRow,title + desc
- 训练偏好(weekly days + want strengthen 肌群多选)
- 数据(导出 / 导入)

---

## 五、行为规范

### 5.1 TrainingSession 全局状态

- session 在 App 根部 (Web: Provider; iOS: `@Environment(TrainingSessionStore.self)`)
- 跨路由保留 — 用户可以下收播放器去看历史 / 计划,训练状态不丢
- 1Hz timer 驱动 endsAt → 自动 advance
- 力量段:没有 endsAt(等用户手动 ✓)
- 休息段 / 计时段:有 endsAt → 时间到自动 advance
- 暂停时把剩余秒数存到 `pausedRemaining`,恢复时算回 endsAt

### 5.2 中间 Tab 双形态切换

```
isTodayActive=false → 点击 → navigate('/')
isTodayActive=true  → 点击 → quickStartOnActiveTab?
                              true:  startTodaysWorkout()
                              false: 无操作 (留在 Today, 不跳自由训练)
```

- 关键:**没有推荐计划时,点击也不应该跳到 /quick/muscle**;应该现合成一个 plan(用 wantStrengthen + analyzeRecentTraining 生成)然后启动
- 集中在 `useStartTodaysWorkout` 一个 hook 里,Home 页按钮和 BottomNav center tap 共用

### 5.3 替换正在进行的训练

- 用户开第二个训练时,如果当前已有 session 且 planId 不同且未 completed → 弹 confirm:
  > "当前正在进行另一个训练。开始这个会替换掉它, 确认吗?"
- 用户确认 → end() 当前 → navigate 到新 plan 的 player
- 用户取消 → 啥都不做

### 5.4 上一段跳过 Rest

播放器的 ← 按钮:
- 找最近的 `type === 'exercise'` 段索引,跳过中间的 rest
- 没有更早的动作 → 按钮 disabled

### 5.5 结束训练的反竞态

```
// 错误:
navigate(-1); end()   // React 批处理可能让 end() 先 flush,
                       // player 的 useEffect 检测到 session=null + planId
                       // → 自动 start(planId), 训练复活

// 正确:
endedRef.current = true
end()
navigate(-1)
// useEffect 检查 endedRef.current 直接 return, 不会复活
```

iOS 等效:`TrainingSessionStore.endedExplicitly` 标记。

### 5.6 解剖图肌群匹配

- 父级肌群(`chest`) → 展开为所有子级(`upperChest, midChest, lowerChest`)
- 子级(`upperChest`) → 也标记父级(`chest`)
- 这样无论动作标注的是父级还是子级,SVG 都能正确高亮

### 5.7 Quick Start 设置默认开

- `quickStartOnActiveTab = true` 是默认
- 用户可以在 Settings → 训练 里关掉
- 关掉后,点击高亮的中间 Tab = 留在 Today 不动

---

## 六、反模式(明确不做)

- **社交流**(朋友圈 / 点赞 / 评论)— 制造比较焦虑
- **游戏化**(XP / 徽章 / 连胜)— 把内在动机外化
- **AI 教练聊天框** — 多半只能出"做得好!"的廉价反馈
- **付费墙挡核心训练记录**
- **体脂 / 身材过度追踪** — 易诱发饮食失调倾向
- **通知催回** — 健身是用户的事
- **「新手版 / 高级版」模式切换器** — 反 simplicity (理念 9)
- **彩虹色 / 多强调色** — 一种 accent 足够
- **侵入式动画** — transition 不超过 300ms, 不抢戏

---

## 七、平台特例

### Web (PWA)
- iOS Safari 兼容是底线
- 「添加到主屏幕」必须是核心引导
- Service Worker 离线缓存
- IndexedDB (Dexie) 本地存储
- 推送通知:谨慎,iOS Safari 支持差

### iOS native
- SwiftUI + Observation (iOS 17+)
- SwiftData 持久化(MVP 可用 in-memory mock)
- PlanPlayer 用 `sheet(presentationDetents: .large)` 实现下收手势
- 触觉反馈 `UIImpactFeedbackGenerator`:组完成、PR 触发、休息结束
- 状态栏:`.preferredColorScheme(.dark)`
- 跟 web 不同的地方:**iOS 上 RootView 总是显示 TabBar**(没有深页/MiniBar 分离的概念),Player 用 sheet 弹出

---

## 八、Format 字典

- **组进度**:`{currentSet}/{totalSets} × {reps}` 例 `1/3 × 10` (slash, 不是 hyphen)
- **重量**:`{val} kg`(或 `lb`)
- **时长**:< 60s 直接秒数 `45`; ≥ 60s 用 `M:SS` 格式 `2:30`
- **日期**:`5/15` 或 `5/15 14:30`(简洁优先)
- **PR 标记**:动作行右侧出现小 ▲ accent

---

## 九、可测量的验收标准

- [ ] 录一组力量数据 ≤ 2 次点击
- [ ] 首屏 → 看到上次训练 ≤ 3 秒
- [ ] 主流程单手可完成(任意手)
- [ ] 完全离线可用 30 天
- [ ] 数据导出涵盖 100% 用户输入,无损失
- [ ] 同一个"录入"组件能处理力量、有氧、瑜伽(理念 8 落地)
- [ ] UI 中找不到任何「新手模式/高级模式」切换器(理念 9 落地)
- [ ] iOS 模拟器上「加到主屏幕」后体验 ≈ 原生(Web 版)
- [ ] 任何鼓励性 / 装饰性元素必须能给出存在理由 — 否则砍掉
