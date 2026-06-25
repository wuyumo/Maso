@/Users/yumowu/.claude/projects/-Users-yumowu-Projects/memory/MEMORY.md

# Maso — iOS 健身 App (SwiftUI)

## 项目
- SwiftUI, **iOS 18** target, 单仓 (`Maso` app target + `MasoWidgets` 小组件 target)
- GitHub: `github.com/wuyumo/Maso.git`

## 签名 / Bundle ID  ⚠️ 重要
- **Bundle ID**: `com.yumowu.maso` (app) / `com.yumowu.maso.widgets` (widget)
- **上架签名**: **Eric Ng 付费 Developer Program, Team ID `TW8ZVVX529`** (Apple ID **wuyumoawuyumo@outlook.com**) — `project.pbxproj` 的 `DEVELOPMENT_TEAM`
- **已弃用**: 旧 Bundle ID `com.maso.app` + 免费个人 team `UR6F66266C` (Yumo Wu / nomorefish@163.com) — 免费 team **只能装机、不能上架**,已迁走。

### 🚨 命令行签名装机会失败 → 真机安装走 Xcode GUI
- `xcodebuild -allowProvisioningUpdates`(`scripts/install_iphone.sh` 用的)即使 Xcode GUI 里已登录账号,仍会报 **`No Accounts: Add a new account`** —— 这是这台机器的已知问题 (CLI 的 account store 跟 GUI 不通)。
- **解决**: 真机安装至少**第一次必须用 Xcode GUI** —— 选好 iPhone 目标 → 点 ▶ Run (⌘R)。GUI 会自动在 `TW8ZVVX529` 下生成 `com.yumowu.maso` 描述文件、注册设备、装机。
- 描述文件落盘后(`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`),之后 `scripts/install_iphone.sh` 多半能直接用(无需再走 GUI)。
- Archive 上架同理:**必须 GUI**(GUI 自动用 distribution profile,命令行会卡 no-devices)。

## 构建 / 安装
- **模拟器** (不需签名,CLI 可直接构建验证):
  `xcodebuild -scheme Maso -configuration Debug -destination "platform=iOS Simulator,id=5617AC82-D030-4E55-8A5D-26A3067DF06E" -derivedDataPath build/DerivedData build`
  装模拟器: `xcrun simctl install <simid> build/DerivedData/Build/Products/Debug-iphonesimulator/Maso.app`
- **真机**: `./scripts/install_iphone.sh`(若报 No Accounts,见上面 → 用 Xcode GUI 跑一次)
- **每次改完代码自动装真机**(用户偏好):build 验证后自动跑 `install_iphone.sh`,不用等用户开口。

## Git push
- push 需要先 `gh auth switch -u wuyumo`(否则 403,默认账号无权限)。

## 上架前还没做的收尾 (换了 Bundle ID 后)
代码侧已就绪(2026-06-13 上线审计批量修复,见 commits bb7f95c 等):
- [x] product IDs 已是 `com.yumowu.maso.pro.{monthly,yearly,lifetime}`;Maso.storekit 对齐
- [x] URL scheme = `maso` / CFBundleURLName `com.yumowu.maso`(旧 com.maso.app 已清)
- [x] 语言收窄 en + zh-Hans(只剩两个 lproj);InfoPlist.strings 本地化
- [x] 隐私清单: iOS + **MasoWatch** 各一份;iOS 删掉未用的 Health-read 声明(watch 保留)
- [x] ITSAppUsesNonExemptEncryption=false(三 target);TARGETED_DEVICE_FAMILY=1(iPhone-only)
- [x] 付费墙合规: 试用按 isEligibleForIntroOffer 显示;disclaimer 明示 auto-renews;Restore 按钮在
- [x] 法务页在线: wuyumo.github.io/Maso/{terms,privacy-policy}.html 均 200
- [x] icon 无 alpha 1024(iOS+watch);version 1.0/build 1;launch screen 配好
## 🚀 上架进度 (2026-06-15 — 改走「免费版先上」)
**决策**: 账号注册名 "Eric Ng" + 美国地址,无法签 Paid Apps(要美国 W-9/SSN),故 **IAP 全部隐藏先上免费版**。
代码侧免费开关: `Maso/Models/Settings.swift` 文件作用域 `enum MasoFlags { static let iapEnabled = false }`;
`isPro = !MasoFlags.iapEnabled || proSubscription != nil`(关 IAP 时全解锁,proSubscription 仍为 nil);
SettingsScreen.proSection 在 iapEnabled=false 时返回 EmptyView。**以后开 IAP**: 翻回 true + 建 3 个内购 + 重走 Paid 协议/W-9/银行/把账号改成 吴俣墨。

**已完成 (free launch)**:
- [x] ASC App 记录 `com.yumowu.maso` (Apple ID 6776689750, name "Masso — AI Workout Planner", 类别 健康健美)
- [x] 开发者后台 HealthKit capability: `com.yumowu.maso` + `.watchkitapp` 均已勾 (其实早就勾好)
- [x] ASC 元数据 en + zh-Hans: 名称/副标题/推广文本/描述/关键词/支持URL/版权 全齐
- [x] ASC 截图: 8 张 (1320×2868 6.9", Apple 跨尺寸跨语言复用) — en 上传, zh 共用
- [x] ASC 年龄分级 4+ (173国 + 巴西/韩国区域例外);加密豁免 (Info.plist ITSAppUsesNonExemptEncryption=false)
- [x] ASC 内容版权声明「是」;App Review 信息: 联系人 Wu/Yumo/+86 18027438345/wuyumoawuyumo@gmail.com,**取消「需要登录」**(无账号系统),备注写了 HealthKit 用途说明
- [x] **build 1.0(3) 已 Archive + Upload** (Xcode GUI;CLI 会卡 No Accounts)。
      ⚠️ 上架踩坑: ① 6/11 旧 archive 1.0(1) 已传过 → build 号每次必须 bump (1→2→3);
      ② iOS `Maso/Info.plist` 缺 `NSHealthShareUsageDescription` 致 upload 校验失败 (code 90683) →
         已补「读」用途说明 + en/zh InfoPlist.strings (catchUpHealthKitSync 避免重复计入的诚实文案);
      ③ Distribute 报 "No Accounts" → Yumo 在 Xcode Settings>Accounts 登录 Eric Ng 后通过。

## 🚀 1.2(8) 合并重提 (2026-06-25)
1.1(7) 在审期间又攒了一批(引导重做/居中/滚轮+声音震动/按钮音效/AI 生成过渡/动作库肌肉分区+跳转条)。
本想合并成 1.1 新 build, 但 **Xcode 上传 1.1(8) 被 Apple 拒**: `CFBundleShortVersionString 必须高于已提交的 1.1` +
`Pre-Release Train '1.1' is closed for new build submissions`(版本号被占,不能复用)→ **改 1.2**。
三 Info.plist CFBundleShortVersionString → 1.2, build 8。Xcode GUI 重新 Archive 1.2(8) → Distribute → **已上传**。
**已提交审核 (2026-06-25)**: 进 ASC 发现 **1.1 已自动过审上架(可分发)**, 故不用撤回——直接新建 1.2 版本叠上去。
What's New en+zh 合并填(kg/lb + 引导重做 + 滚轮声音震动 + 按钮音效 + AI 过渡 + 动作库分区); 关键词/截图从 1.1
自动继承(沿用 ASO 优化版 en: fitness,gym,home,bodybuilding,...; zh: 健身,训练,力量,...); 挂 build 8; 自动发布。
**状态 = 「1.2 正在等待审核」** (≤48h, 邮件通知, 过审自动上架)。合规问答沿用历史答案未再弹。
⚠️ 下次发版要继续往上 (1.3 或 build 9+); 1.1/1.2 版本号都已用过。

## 🆕 Exercises 右侧索引: 单面板缩放肌肉图 + 滚动跟随高亮 (2026-06-25 二轮)
- 图标换成 `MuscleRegionIcon` (新 private struct): 单面板 (背部 POSTERIOR / 其余 ANTERIOR), Canvas 把该区肌群
  polygon 的包围盒 ×1.55 取正方形当 viewBox → 缩放到该区+周边的精细分块 (不再画前后两个小人). 参数化 focusColor/surroundColor.
- **配色 (accessibility, 三轮调)**: accent=#1ED760 亮绿, 白字在它上只 ~1.8:1 不达标 → 选中态用**深色** (focusColor=
  background #121212, surround=background.opacity(0.35)) 在亮绿 `Capsule().fill(accent)` 底上, 文字也 background 深色 → ~11:1 AAA.
  静止态: 无底、无名称、整体 opacity 0.7, 灰剪影 (focus text.opacity(0.42)/surround 0.1, 单色无色相→色盲友好). 图标 22pt, 标题 10pt.
  选中靠"绿底+文字现身+深色高对比图"三重线索, 不靠单一颜色.
- **滚动跟随高亮**: `SectionMinYKey` 改成上报 `[RowAnchor(section,minY)]` — **每个可见行**都报 (不能只报第一行:
  第一行滚出屏幕被 List 虚拟化就不再上报, 会误判 → 之前 bug). onPreferenceChange 取 minY<=70 里 minY 最大的行
  (= 顶部刚越过参考线那行) 的 section 高亮. 模拟器实测: 滚到 Back 区高亮切 Back.
- **修 scrubber 抖动 (二轮收尾)**: 拖拽时 scrubber 设区 + scrollTo, 滚动又触发跟随按顶部行算出相邻区 → 互斗来回跳.
  加 `isScrubbing` 门: 拖拽 onChanged 置 true 期间 onPreferenceChange 直接 return; scrollTo 去掉 withAnimation 改即时跟手;
  onEnded 延迟 0.35s 再置 false 让滚动 settle 防回弹. 实测按住移到 Legs 干净跳、松手不回弹.
- **改成通讯录式圆点 (四轮, 尺寸一致诉求)**: 之前每行直接画 MuscleRegionIcon, 各区 bbox 缩放不同 → 视觉大小不一.
  改为: **平时** 当前区 = 小号绿色肌肉图 (`MuscleRegionIcon` focus=accent/surround=accent.opacity(0.3), size 18 — 瞥见是哪个肌群),
  其余区 = 统一小灰点 (`Circle` textDim.opacity(0.35) 5pt); 无文案;
  **仅拖动**时 (`showScrubLabel`, onChanged 置 true / onEnded 立即置 false) 当前区弹出绿 capsule pill = [名称 + MuscleRegionIcon(深色)],
  仿 iPhone 通讯录右侧索引的 HUD. 行用 `.frame(width:30,height:32,alignment:.trailing).contentShape(Rectangle())` 给足拖拽热区. rowH 38→32.

## 🆕 Exercises 右侧索引重做成"肌肉图 scrubber" + 去 section 标题 (2026-06-25)
`ExerciseLibraryBrowser.jumpNav` 重做: 每区一个迷你 `BodyHint(muscles:[sec], color:)` 人体图 (该区肌肉高亮).
未选中 = dim (textDim, opacity 0.7) 只显示图; 选中/手指滑到 = accent 高亮 + 左侧浮出文字 + "图+文字"chip 底 (Capsule .ultraThinMaterial); **整条无卡底**. 交互 = `DragGesture(minimumDistance:0)` scrubber: 固定行高 38, `value.location.y / rowH` → 行 → 高亮 + `proxy.scrollTo(该区第一行 group.id)`. VStack(alignment:.trailing) 右对齐, overlay(.trailing) 浮右缘垂直居中.
**列表 section 标题全去掉** (`sectionHeader` func + `Section{}header:` + `.id(sec)` 删除; 吸顶时底色对不齐导航栏, 索性不要) — 仍按肌肉分组保顺序, 只是无标题. `SectionMinYKey` preference + coordinateSpace + onPreferenceChange 一并删 (高亮改由 scrubber 驱动, 不再跟随滚动). `composites[.chest/.arms/.legs...]` 能把区→子肌群展开给 BodyHint 点亮整片.

## 🆕 1.2 提交后的一批 UI 调整 (2026-06-25, 在 main, 未进 build)
- **Exercises tab**: ① 分区跳转条从底部横条改成**右侧竖排索引** (`jumpNav` overlay(alignment:.trailing), pill `.fixedSize()` 收窄, 别用 maxWidth:.infinity 否则撑满全宽盖列表); 点击滚到该区第一行 + 高亮跟随滚动 (PreferenceKey 保留). ② section 吸顶表头底色 `MasoColor.background` → `.bar` (跟导航栏同材质). ③ 去掉筛选/搜索的上划隐藏 — `headerVisible`/`jumpNavVisible`/showHeader/hideHeader/setJumpNav + onScrollGeometryChange/onScrollPhaseChange 全删, safeAreaBar(.top) 恒显 searchFilterBar.
- **Routines tab**: ① 把 AI / Classics 从 "+" 菜单**放出来**, 作为入口卡 (`entryCard`) 排在 My routines 列表下面 (TodayScreen .myPlans 末尾, 新增 `onBrowseClassics` 闭包; PlansScreen savedPage 传 `{ addRoute = .classics }`); "+" 菜单只剩 Create my own + Import. ② "Create from scratch" → **"Create my own"** (en/zh Localizable 已加).
- **Player 休息**: 倒计时圆环 trim + REST kicker `MasoColor.accent` → 白 (`MasoColor.text`); 播放列表 active rest 行文字 + 高亮底也改半透明白 (`MasoColor.text` / `.opacity(0.14)`).
- **Player 回退键**: 恒用三角 `backward.end.fill` (去掉 isUndo 切撤销图标那套); `handleBack()` 恒 `store.skipBackToPrevExercise()` (跳过休息回到上一训练组播放态, 不再撤销组). `Controls.isUndo` 属性删除. 模拟器实测: 休息中点回退直接回到上一组 set 1/3 播放态.

## 🆕 Exercises Tab 肌肉分区 + Section Navigation (2026-06-24)
`ExerciseLibraryBrowser`: 动作列表按肌肉大区 (`MuscleGroup.section`, 6 区: 胸/背/肩/臂/核心/腿) 拆成
**竖向 List Section**, 每区一个吸顶表头 (`sectionedGroups` 按 muscleSections 顺序分桶; `sectionOf` 取 canonical
首个 primaryMuscle 的 .section — 注意 `.section` 是 Optional 要解包). 区内顺序沿用 filteredGroups (置顶+名字序).
底部 (TabBar 上方) 加**肌肉分区跳转条** (`jumpNav`): 横向 pill, 上滑进列表浮出 (`jumpNavVisible`, iOS26 onScrollGeometryChange
newValue>60 触发), 点 pill → `proxy.scrollTo(该区第一条 row 的 group.id, anchor:.top)`. 放在 iOS26 `.safeAreaBar(edge:.bottom)`
里 (ScrollViewReader 提到 body 外层包住 Group). 高亮当前 = 点击驱动 (默认第一个区).
⚠️ **未完全验证**: 模拟器自动化点击底部 bar 区域不触发 (computer-use 在 safe-area 底条的已知限制?), tap-to-jump 待真机确认.
  曾试过 PreferenceKey 跟随滚动高亮 (List 里 GeometryReader preference 不可靠, 已移除) + safeAreaInset/overlay 放置 (同样点不到).

## ❌→🔁 1.0(3) 被拒 → 修复重传 1.0(5) (2026-06-17)
**拒因 (Guideline 4 - Design)**: Apple Watch app icon 背景是黑色 → 在手表上(圆形遮罩+黑底)看不出圆形轮廓。
**修复**: watch app icon 换成**品牌绿 #1ED760 满底 + 深色 #121212 M 标**(`MasoWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png`,
用 rsvg-convert 从 SVG 合成 + Pillow 扁平化去 alpha;生成脚本思路见本条)。iOS icon 不受影响(只改 watch)。
build 号 → **5**(1/2/3 我用过、4 Yumo 传过)。1.0(5) 这版顺带带上了 6/16-17 的改进:
纯平 logo(去 3D 内阴影)、watch 待机屏改品牌 M 标(`MasoWatch/WatchBrandMark.swift`)、分享 customize 卡满宽、
完成屏底色统一 #121212、训练音效改成 watch 风格单 click(`SoundPlayer` 合成)。
**已重新提交审核 (2026-06-17 ~17:45)**: build 1.0(5) Archive+Upload(账号已登录, 无 No Accounts)→
处理完 → ASC 版本页移除旧 build 3、选中 1.0(5)、保存 → 「更新审核」→「重新提交至 App 审核」。
当前 ASC「iOS 提交」状态 = **等待审核**(1.0(5))。等 Apple 结果(≤48h, 邮件通知)。

## ❌→🔁 1.0(5) 又被拒 → 修复重传 1.0(6) (2026-06-21)
**拒因 (Guideline 2.5.1 - Performance - Software Requirements)**: app 用了 HealthKit, 但**界面里没有可见地标识 HealthKit 功能** → Apple 要求用 HealthKit 必须在 UI 里明确告知用户(透明)。
**根因**: 代码里早有 `Settings.healthKitSyncEnabled` + `HealthKitService`(write-only)+ `RootView.catchUpHealthKitSync`, 但 **SettingsScreen 里从来没加这个开关的 UI** → flag 永远 false, HealthKit 在界面上完全不可见。
**修复**: SettingsScreen 在 Units 之后加「**Apple Health**」section + `ToggleRow`「Save workouts to Apple Health」+ 说明文字(写训练 + 手表读心率/能量);开关打开 → `HealthKitService.requestAuthorization()` 弹系统授权对话框。已在 sim 验证: 设置里可见 + 点开正常弹「Masso would like to access and update your Health data」(Active Energy / Workouts 写入)。en+zh Localizable.strings 各补 3 键。
build 号 → **6**(1/2/3/5 我用过、4 Yumo 传过)。
**已完成重传 (2026-06-21)**: Archive+Upload(Xcode GUI, 自动签名通过)→ ASC 版本页移除 build 5、挂 1.0(6)、保存(状态→准备提交→可供审核)→ App Review 备注**顶部**插入精确指引「Re: Guideline 2.5.1 … open the app, go to Settings, scroll to the 'Apple Health' section … 'Save workouts to Apple Health' toggle … turning it on presents the standard HealthKit permission sheet」(原 HealthKit 用途说明保留在下方)→ 提交详情页「重新提交至 App 审核」。
当前 ASC「iOS 提交」状态 = **等待审核**(1.0(6))。等 Apple 结果(≤48h, 邮件通知)。
⚠️ 发布设置 = **自动发布**(过审即自动上架);若想手动控时间, 过审前去版本页「App Store 版本发布」改成手动。

## 🧪 1.0(6) 之后的新功能 (2026-06-22, 已在 iPhone dev 包, 未进审核中的 build 6)
下次上架要 bump build (7+ 或 1.1) 才会带上这三项 (代码在 main 工作区, 模拟器实测 + 装机过):
- **R1 播放列表休息进度条去除**: `PlanPlayerScreen.restRow` 活动态删掉 3pt 进度条 (`GeometryReader`),
  只留 accent 高亮底 + 倒计时文字 (其余样式不变).
- **R2 已完成动作回退撤销**: 播放头在"有已完成组"的动作上时, 回退键 (`backBtn`) 改为"撤销最近一组"
  (`TrainingSessionStore.undoLastCompletedSet` 清 completedSet + `DataStore.removeLastSet` 删本场该动作最近一条
  SetRecord, 播放头落到该组重练); 组全撤完后回退键恢复"上一动作"导航. ⚠️ 把回退键在已完成动作上的语义由"导航"改成"撤销".
- **R3 全局动作参数同步** (`UserSettings.globalExerciseParamSyncEnabled`, 默认 ON, 设置页「Exercise data」开关):
  开 → 在任意 routine / 训练中改某动作参数 (组/次/重量/休息/逐组), 经 `DataStore.syncExerciseParams` 传播到所有含
  该动作的 plan (+ aiTodayPlan). 咽喉点 = `updatePlan` diff (覆盖 routine 编辑器实时 + 播放器结束保存) + 播放器
  `updateStep`/`updateCurrentStep` 后即时传播. 关 → 各 routine 独立, 新加动作 (`makeSeededStep`) 从 lastSet 回填.
  ⚠️ 同步只在"改参数那一刻"触发, 不回溯统一既有 routine; 重量也同步 (Yumo 拍板).

## 🚀 1.1(7) 已提交审核 (2026-06-24)
1.0(6) 已过审上架后, 把这一版攒的改进打成 **1.1 (build 7)** 提交。Info.plist 三 target 升到 1.1 / build 7。
**这版含**: R1/R2/R3 (上条) + 播放器休息时不高亮下一动作行(只休息条高亮) + 第三 Tab 上滑收起 Muscle/Equipment/Search、下滑或暂停再现 + Onboarding 去掉默认选中 Male(gender 改 `nil` + 显式 Continue 按钮) + Onboarding "AI 正在生成计划"过渡页(`AIGeneratingView`) + 45 项 UX 走查的 P0/P1/P2 修复 + **kg↔lb 全 App 单位选择**(`WeightUnit` 扩展 + `WeightUnitProvider.current`,设置页切换) + set-complete 音效换成清单勾选感上行 chime(`SoundPlayer.generateComplete`) + 修 weightLabel 字面量 bug & 肌肉图溢出(perl `\(` 反斜杠被吞,见 commit) + Today 空状态/首日打磨。
**⚠️ 已知未修(留 1.2)**: 播放器"训练组"↔"休息中"三按钮位置跳动(HaloRing footprint > 42pt 致 Spacer 重排); 见 task #105 deferred P2 清单。
**ASC 元数据 (1.1, 版本锁定字段已改)**:
- What's New en+zh 已填(kg/lb 单位/引导更清晰/Today 打磨+完成音效/修重量显示&肌肉图/中文本地化修正)。
- **关键词做了 ASO 优化** (去掉跟名称"Masso — AI Workout Planner"+副标题"AI plans, guided lifting"/"AI 计划·跟练·记录"重复的词):
  - en (100字符): `fitness,gym,home,bodybuilding,strength,training,dumbbell,barbell,muscle,routine,trainer,exercise,log`
  - zh: `健身,训练,力量,增肌,减脂,塑形,肌肉,撸铁,举铁,哑铃,杠铃,私教,卧推,深蹲,俯卧撑,健身房,居家,打卡,核心,教练,减肥,健美,拉伸,燃脂`
  - 原理: 名称/副标题 Apple 已最高权重索引, 关键词重复=浪费; 用单词让 Apple 跨字段自由组合(home workout/strength training/力量训练/健身教练 等)。**品牌名 "masso" 不放关键词**(已索引, 搜不到只是新 app 索引滞后 24–72h)。
- 发布方式 = **自动发布此版本**(过审即上架, 跟 1.0 一致)。
**状态: 「1.1 正在等待审核」** (2026-06-24 提交, ≤48h, 邮件通知)。合规问答沿用 1.0 答案未再弹。

## 🧪 1.1 提交后的新改动 (2026-06-24, 待下一版 bump 才进审核)
- **Onboarding 重做成"一问一屏向导"** (`OnboardingScreen.swift` 整体重写, 替代旧的单页渐进展开):
  5 步 = 性别 / 年龄 / 体重 / 每周次数 / 重点肌群。交互规则:
  · 选项型 (性别 / 次数) 单选 → 0.18s 后**自动跳**下一步, 无 Next 按钮;
  · 拨盘型 (年龄 / 体重) 用 `Picker(.wheel)`, 选体重时**默认落在该性别平均值** (`avgWeight`: 男75/女60/其他68 kg,
    `weightTouched` 标记用户拨过后不再被 re-seed) → 点"下一步"确定;
  · 多选型 (肌群) → "确认, 生成计划" 收尾 (触发原 `AIGeneratingView` 过渡);
  · **第 2 步起左下角恒有"返回"** (`goBack`), 即便是自动跳进来的步骤; 返回保留上一步已选态。
  · 切屏方向感: `goingForward` 控制 `.asymmetric` 滑动 (前进从右进/返回从左进); 顶部 5 段进度条 + "第 X 步 / 共 5 步"。
  · 模拟器 en+zh 全流程实测过 (gender 自动跳 / 体重默认 75→选 Female 返回重选后变 60 / 返回保留态 / 拨盘暗色渲染正常 / 确认→AI 过渡→Today)。
  · 删了旧的 `SectionLabel` (private 不再用); `FlowLayout`/`FlowAlignment` 仍定义在本文件 (全 app 复用, 勿移)。
  · 新增本地化键 (en+zh): "What's your gender?"/"How old are you?"/"What's your weight?" + 三句副标题 + "Next"(下一步) + "STEP %lld / 5"(第 X 步/共 5 步)。复用已有的 "Back"(返回)/"Confirm & build my plan"/性别标签/"How many days…"/"Which muscles…"。
- **Onboarding 二次调整 (同日, Yumo 反馈)**: ① 去掉所有预选默认 —— `daysPerWeek: Int? = nil` (天数不再默认 3)、`strengthen = []` (肌群不再默认 chest+back); 性别本就 nil。confirm 用 `daysPerWeek ?? 3` 兜底。② 问题区上移到"中间偏上" (上 1 : 下 2 的 Spacer 比例, 约 1/3 处)。③ 整体放大: 标题 24→30、副标题 13→16、性别行 font 16→21+padding 加大、天数圆 46→52/font 18→24、**拨盘 font 22→30 + 高 190→240**、返回/下一步按钮 font 15→17。en+zh 模拟器实测过。
- **Onboarding 三次调整 (同日, Yumo 反馈拨盘太挤 + 布局)**:
  · 拨盘换成**自定义 `WheelPicker`** (private struct in OnboardingScreen.swift): 原生 `.wheel` 行高固定, 字号一大数字重叠、选中框加不高。自做用 `ScrollView + .scrollTargetBehavior(.viewAligned) + .scrollPosition(id:anchor:.center) + .contentMargins`; 行高 64、居中数字 40pt 加粗/其余 30pt、tracking 3、选中框=行高。⚠️ `scrollPosition` 初值首次 layout 不生效, 用 onAppear 后置 + `ready` 门 (避免初始程序化定位误置 weightTouched)。
  · **布局重排**: 问题贴顶 + 居中 (`stepTitle` 用 `.multilineTextAlignment(.center)` + `frame(maxWidth:.infinity)`); 选项**沉到屏幕底部** + 居中 (拇指易触)。统一骨架 `stepBody(title,subtitle){ input }` = `VStack{ 16gap; title; Spacer; input }.frame(maxHeight:.infinity)`, 填满 header 与 bottomBar 之间。进度条 STEP 文案也居中。
  · 肌群 chip 居中: `MuscleSelector` 加 `chipAlignment: FlowAlignment = .leading` 参数 (Onboarding 传 `.center`, Settings 等默认不变)。
  · 性别行文字居中 + ✓ 用 `.overlay(alignment:.trailing)` 叠右侧 (不破坏居中)。en+zh + 全 5 步模拟器实测。
- **Onboarding 四次调整 (同日)**: 「每周训练几次」由 6 圆点选项型 → **WheelPicker (1...6, 默认 3)**, 改成拨盘型 = 转值后点「下一步」(不再点一下自动跳); `daysPerWeek` 回到非可选 `Int = 3`; 删 `selectDays`; primaryAction 给 `.days` 加 Next; 现在只剩"性别"是选项型自动跳。模拟器实测。
- **Onboarding 六次调整 (同日)**: ① **每步按钮音效**: `SoundPlayer.playTap()` (复用 clickBuffer, 公开) 接到 Next / Confirm / 性别选择; Back 用 `playTick()` (更轻, 区分方向)。② **AI 生成过渡重写** (`AIGeneratingView`): 改成**渐进式清单** —— 4 步逐条出现 (前 3 步 spinner→✓ 累积, 第 4 步成功态), 末尾中央大 ✓ 弹跳 + "All set!" + chime(`playSetComplete`)+ success 触觉; 每步带 tick。~4s 落地。文案 Uploading your data / Analyzing your stats / Building your plan / Your plan is ready (en+zh + "All set!" 已加 Localizable)。③ **🐞 关键 bug 修复**: 该过渡**之前从没真正显示过** —— `RootView` 用 `data.settings.onboardingCompleted` 做门控, 而 `confirm()` 当场就置 true → OnboardingScreen(连同挂在它上面的 `generating` overlay)被瞬间换走。改: `confirm()` 不再置 onboardingCompleted, 只点亮 `generating`; 由过渡结束的 `onDone`(RootView 里现在置 onboardingCompleted+flushSave)切到主界面。⚠️ 副作用: 过渡那 ~4s 内杀 app 会重看引导 (可接受)。
- **Onboarding 五次调整 (同日)**: ① 第 5 步 focus chip 放大 (`MuscleSelector` 加 `largeChips` 参数, font 20/pad 22×14, FlowLayout spacing 12; 默认 false 不影响 Settings) + 落到**屏幕中下段** (focusStep 用 上2:下1 Spacer + 底部 `Spacer(minLength:40)` 跟按钮留间隔)。② Confirm 按钮: 文案 `Confirm & build my plan` → **`Build My Routine`** (en+zh "生成我的计划" 已加 Localizable); `.lineLimit(1)` 不折行 + `.frame(maxWidth:.infinity)` 填满 Back 右侧 → 更宽 (bottomBar 去掉 Spacer, primary 改填充式)。③ **拨盘交互反馈**: `WheelPicker.onChange` 吸附换值时加 `Haptics.selection()` (常驻 `UISelectionFeedbackGenerator`) + `SoundPlayer.shared.playTick()` (新增更轻 tickBuffer = generateClick gain 0.11, 随静音静默); 自定义滚轮没有系统 Picker 的咔哒声/触觉, 手动补。`ready` 门保证初始定位不误触发。
- ⚠️ **on-device 看不到新引导**: onboarding 仅首次启动出现 (`settings.onboardingCompleted`), 覆盖安装保留标记 → 老用户直接进 Today。要预览须 clean reinstall (卸载+重装清本地数据) 或删 App 重开。

## 🤖 夜间自动流水线 + 发版工作流 (2026-06-24 起, Yumo 拍板「绿了通知我, 一键确认」)
**背景**: Yumo 不想再人为提交 App Store, 要自动化。但全自动上传+提审有硬约束 (审核 24-48h 且同时只能一个版本在审, 不适合每晚提交; 无人值守上传需 ASC API 密钥, 暂未配; 自动提审会误把半成品送审)。故定方案 = **夜间自动 验证+装机, 发版仍交互式一键确认**。
- **launchd**: `~/Library/LaunchAgents/com.yumowu.maso.nightly.plist` 每晚 **23:00** 跑 `scripts/nightly.sh` (Mac 须醒着; 睡了则下次唤醒补跑)。
  管理: `launchctl bootstrap/bootout gui/$(id -u) <plist>`; 立刻测跑 `launchctl kickstart -k gui/$(id -u)/com.yumowu.maso.nightly`。
- **`scripts/nightly.sh`** 做: boot 固定模拟器 → `verify-app/driver.sh` 烟测 → `install_iphone.sh` (best-effort) → 写 `build/nightly/latest.md` + 弹 macOS 通知 (✅/❌)。**故意不碰上传/提审**。
- **发版 (Yumo 说一句「提交」时, Claude 交互式做)**: bump build (Info.plist ×3) → Xcode GUI Archive+Distribute 上传 (CLI 会 No Accounts) → ASC 网页 (需 Yumo 已登录浏览器会话) 建版本/填 What's New+关键词/挂 build/设自动发布 → 给 Yumo 看终稿 → 点「添加以供审核」→ 最终面板 Yumo 一键确认「提交以供审核」。
- ⚠️ 真要全自动提审 = Yumo 在 ASC 建 App Store Connect API 密钥 (App Manager) 给我, 我写 fastlane 式纯脚本挂 launchd (archive→altool 上传→ASC API 建版本+提审)。当前没走这条 (Yumo 选了一键确认档)。

## ✅ 已提交审核 (2026-06-15 23:44, build 1.0(3) — 已被拒, 见上)
**状态: 「1.0 正在等待审核」** — Apple 审核 ≤48h, 完成邮件通知。提交时还现场补了几项 ASC 必填:
- [x] build 1.0(3) 处理完 → 已挂到版本 (注: TestFlight 里还有个 Yumo 重传的 1.0(4), 同代码冗余, 没用它)
- [x] 隐私问卷已「发布」(en + **zh 隐私政策URL 当时漏填, 已补** https://wuyumo.github.io/Maso/privacy-policy.html)
- [x] **价格 = 免费** (175 国全 $0.00) + 供应情况 = 所有国家/地区
- [x] **受监管医疗设备声明 = 否** (App 信息页, EU/UK/US 必答)
- [x] **Apple Watch 截图 3 张** (416×496 Series 11; build 含 watch app 故强制要):
      从模拟器镜像捕获 (待机屏/实时训练组/休息倒计时), 存 ~/Downloads/Maso App Store素材/screenshots/watch/, Yumo 拖传
- [x] App Review 备注写了 HealthKit 用途 + 无账号说明

**审核通过后要做**:
- [ ] 选发布 (当前设的「自动发布」: 过审即自动上架; 想手动控时间可改)
- [ ] 分享卡占位二维码换成真 App Store 链接 (见 [[project_maso_post_launch_qr]])
- [ ] (可选) 补译界面残留英文 (空状态/STEP)
- [ ] (以后做 IAP) MasoFlags.iapEnabled=true + 建 3 内购 + 改账号名 吴俣墨 + 走 Paid 协议/W-9/银行

## 工程管理 (xcodegen) — 2026-06-11 起
- **project.yml 是工程的 source of truth**, 已同步到真实配置 (bundle id / team / device family)。
- **加新 .swift 文件 / 新 target**: 直接建文件 + 改 project.yml → `xcodegen generate`。
  (旧约束"不要新建 swift 文件"作废 — 那是 yml 漂移期的权宜。)
- ⚠️ 三个 Info.plist (Maso / MasoWidgets / MasoWatch) **手维护**, yml 故意不写 info: 块;
  别把 info: 加回去, 会被 generate 重置。
- Maso.entitlements / MasoWatch.entitlements 由 yml 管理 (generate 会重写, 改 yml 不改文件)。

## Apple Watch (MasoWatch target)
- watchOS 11+, bundle `com.yumowu.maso.watchkitapp`, 嵌在 Maso.app/Watch/。
- 架构: 手机 TrainingSessionStore 是 source of truth, 每次 mutation 末尾 syncWatch()
  (Maso/Data/WatchSyncManager.swift) 推 WatchSyncState (MasoWatch/Shared/, 两 target 共编);
  手表 (MasoWatch/WatchBridge.swift) 渲染 + 回传 advance/togglePlay。
- 手表训练时跑 HKWorkoutSession (心率+卡路里+圆环), 保存由手表做;
  手机端 RootView.catchUpHealthKitSync 见 watchHealthSessionActive 标记就跳过当天写入 (防双计)。
- 模拟器联调: 用已配对的 pair (`simctl list pairs`), watch app 直接 install
  `build/.../Maso.app/Watch/MasoWatch.app`; 手机端 showcase player 模式开练即可看镜像。
