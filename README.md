# Maso — iOS native

Web App (`/Users/yumowu/Projects/Maso - iOS & Watch OS/`) 的 iOS 原生版,SwiftUI + Observation。

## 跑起来

需要:
- Xcode 26+ (Swift 6 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

```bash
cd Maso-iOS
xcodegen generate
open Maso.xcodeproj
# Cmd-R 跑模拟器即可 (iPhone 15 / 16 / 17 任意, iOS 17+)
```

命令行验证编译:
```bash
xcodebuild -project Maso.xcodeproj -scheme Maso -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

## 目录结构

```
Maso/
├── MasoApp.swift              App entry, 注入 DataStore + TrainingSessionStore
├── Info.plist
├── Assets.xcassets/           AppIcon + AccentColor + launchBackground
├── Theme/
│   └── Colors.swift           跟 web 端 CSS variables 1:1 (accent #1ED760 等)
├── Models/                    跟 web 端 src/lib/types.ts 1:1
│   ├── MuscleGroup.swift      所有肌群枚举 + displayName 本地化
│   ├── Exercise.swift
│   ├── Plan.swift             Plan / PlanStep / SetRecord
│   └── Settings.swift         UserSettings (含 quickStartOnActiveTab 等)
├── Data/
│   ├── Anatomy.swift          解剖 polygon 数据 (从 anatomy.ts 移植), BodyRegion 判断
│   ├── PlanSegments.swift     Plan → [Segment] 展开 (跟 web 端 planSegments.ts 同步)
│   └── DataStore.swift        Observable 仓库; 目前 in-memory mock, 后续可接 SwiftData
├── State/
│   └── TrainingSession.swift  全局训练会话状态 + 1Hz 自动倒计时 ticker
└── Views/
    ├── RootView.swift         顶级路由 (onboarding ? OnboardingScreen : Tab+sheets)
    ├── Tabs/
    │   ├── TabBarView.swift   3-tab 底栏, 中间 Tab 训练时变药丸
    │   └── ActiveTrainingPill.swift   训练中那个横向 pill
    ├── Components/
    │   ├── BodyHint.swift     双视图肌肉示意图 (region: full / upper / lower)
    │   ├── TimelineBar.swift  播放器顶部进度条 (rest=白, exercise=accent)
    │   ├── ExerciseImage.swift Spotify-style 占位渐变 + category 图标
    │   └── WorkoutCard.swift  Today 页的主卡片
    ├── Screens/
    │   ├── TodayScreen.swift
    │   ├── PlansScreen.swift
    │   ├── HistoryScreen.swift
    │   ├── SettingsScreen.swift   含 ToggleRow / Choice 等组件
    │   └── PlanPlayerScreen.swift PlanPlayer + Controls + InlinePlaylist + CompletedView
    └── Onboarding/
        └── OnboardingScreen.swift 单页渐进展开 (基础信息 → 频率 → 加强肌群)
```

## 跟 web 端的对应关系

| Web (React) | iOS (SwiftUI) |
|---|---|
| `App.tsx` | `MasoApp` + `RootView` |
| `BottomNav.tsx` | `TabBarView` + `ActiveTrainingPill` |
| `lib/trainingSession.tsx` Context | `TrainingSessionStore` (Observable) |
| `lib/db.ts` Dexie | `DataStore` (Observable, 目前 in-memory) |
| `lib/anatomy.ts` polygon | `Data/Anatomy.swift` |
| `lib/planSegments.ts` expandPlan | `Data/PlanSegments.swift` |
| `components/BodyHint.tsx` | `Views/Components/BodyHint.swift` (用 Canvas 绘制) |
| `screens/PlanPlayer.tsx` | `PlanPlayerScreen` + 内嵌的 ExerciseStage / RestStage / Controls / InlinePlaylist |
| `screens/Workout.tsx` (Today) | `TodayScreen` |
| `screens/Plans.tsx` | `PlansScreen` |
| `screens/History.tsx` | `HistoryScreen` |
| `screens/Settings.tsx` | `SettingsScreen` |
| `screens/Onboarding.tsx` | `OnboardingScreen` |
| `CSS variables` `--color-*` | `MasoColor.*` |

## 视觉语言对齐项

- ✅ 暗主题 + 强调色 #1ED760
- ✅ 双视图人体肌肉图 (anterior + posterior 并排, 区域裁剪 full/upper/lower)
- ✅ 顶部 TimelineBar (休息白, 动作绿)
- ✅ 底部 3-tab 栏 + 训练中变药丸
- ✅ PlanPlayer 的 sheet 形态 (presentationDetents .large)
- ✅ 取消改成 "结束训练" 措辞
- ✅ 大字号、圆角药丸、半透明 chip

## MVP 范围 + Tier 2 backlog

**已实现 (Tier 1)**:
- 基础数据流: DataStore + TrainingSessionStore
- 完整的肌群分类 + 解剖图渲染
- 4 个主屏 (Today/Plans/History/Settings) + Onboarding + PlanPlayer
- TabBar 训练态切换 + 快捷启动设置

**还没做 (Tier 2)**:
- **持久化** — 现在 DataStore 全在内存, 应该挪到 SwiftData。所有 model 已经是 `Codable`, 接 SwiftData 只需要换底层
- **真实图片** — `ExerciseImage` 现在用 category 渐变占位。要接 free-exercise-db 的话:
  - 把 0.jpg / 1.jpg 镜像到自家 CDN 或 R2
  - 用 `AsyncImage` 双帧切换 (Web 端是 CSS `keyframes` 切, iOS 用 `TimelineView` 切)
- **斜方三段细分 / 三头三段细分** — `Data/Anatomy.swift` 里这些目前合并成一个 polygon, 视觉够用但不如 web 细
- **左滑列表行编辑** — 比如训练计划列表那种 iOS Mail 风格的 swipe action, web 端在 InlinePlaylist 里实现了
- **AI 推荐 / 上次重量自动填充** — `useStartTodaysWorkout` 那套合成 plan 的逻辑
- **手势** — PlanPlayer 的下拉收起手势 (现在靠 sheet 的内建 dismiss)
- **触觉反馈** — `UIImpactFeedbackGenerator` 接到组完成、PR 触发等关键节点

## 设计原则 (来自 `~/.claude/plans/web-app-delightful-bumblebee.md`)

1. **训练时优先** — 80% UX 价值在那 30 秒,大字号、单手可达、高对比
2. **历史即计划** — 进入动作页, 上次 5×100kg 最显眼
3. **一屏一焦点** — 做组只显示当前组目标 + 大「完成」
4. **沉默的进步反馈** — 不催回、无徽章, PR 小高亮足够
5. **离线优先** — SwiftData 本地存全部, 云同步是 nice-to-have
6. **数据归用户** — 一键导出 JSON / Markdown
7. **可组合, 不强制** — 允许换动作、跳过、调顺序
8. **统一训练记录抽象** — 力量 / 有氧 / 灵活性共用一个 `SetRecord` (已对齐)
9. **进阶式默认值** — 没有「新手 / 高级」切换器, 默认值随次数演化
10. **iOS-native 硬约束** — 用系统手势 (sheet 滑下、左滑删除等), 不模拟 web router
