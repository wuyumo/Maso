# 训练中心率卡片波纹 — 写回说明

这是一份只改画法的增量补丁。云端仓库 `main` 是 `02106ee`，里面的 `PlanPlayerScreen.swift` 没有心率卡片。本机工作区 HEAD 是 `c3bba5dd`，播放器和 `RootView.swift` 还有未提交修改，UI 测试未跟踪。补丁的基线是附件快照，不是云端 `main`，也不是 `c3bba5dd` 的 git blob。

Linux 上不能跑 iOS 模拟器。这里没有编译、没有装机、没有录屏。不能把这份代码当成已经在手机上看过的完成结果。

## 不要覆盖

- 不要 `git checkout`、`git reset`、`git clean`、`git pull`，也不要把云端 `main` 或这份分支里的文件盖回 `/Users/yumowu/Projects/Maso-iOS`。
- 不要用整份 `PlanPlayerScreen.swift` 替换本机文件。本机文件比云端多出的未提交内容必须留在原地。
- 不要改 `RootView.swift` 和 `MasoUITests/ExerciseLibraryBrowserUITests.swift`。它们不在补丁里。
- 不要合并这个 PR 到 `02106ee`。合并只会把补丁文本带进旧历史，不会更新本机正在跑的 App，还可能把无关文件带进来。
- 不要上传 App Store，不要发版。

## 核实到的波纹来源

心率卡片上的波纹不是按压溅射，也不是主按钮完成组时的 `HaloRing`（那圈在约 2148 行，这次没动）。

真正的波纹在快照 `PlanPlayerScreen.swift` 的 `WorkoutHeartRateButton.heartControl`：卡片展开、场景 active、设置页没打开、没有 Reduce Motion、有新鲜 BPM、`WorkoutHeartLiquid.progress` 有值时，`TimelineView` 每 1/30 秒画一个圆。

```swift
let cycle = time * Double(bpm) / 60 - 0.25
let phase = cycle - floor(cycle)
let radius = extent * (0.25 + 0.75 * progress) * phase
Circle().stroke(color.opacity(0.55 * (1 - phase)), lineWidth: 2)
```

生硬来自这条画法，不是手势队列：

- 半径跟 `phase` 成正比，速度恒定，没有扩散时应有的减速。
- 透明度在 `phase = 0`（半径接近 0）时是 0.55，到 `phase → 1` 时落到 0，下一帧又跳回 0.55。每一拍都在心形中间硬闪一下，再被裁成细线冲到卡片边缘。
- 线宽恒为 2pt，边缘一直是硬矢量线。
- 时钟是纯函数，没有 `withAnimation` 完成回调，也没有每次点击再生成一圈。所以不会自己叠多圈；跳变是同一圈在 0/1 处断开。

手势只决定这层在不在：

- 点按打开设置页（`settingsPresented`），波纹视图被拿掉，不会留下残影。
- 长按切换卡片，仍走原来的 `Haptics.tap()`。
- 连点不会排队、不会多圈，因为没有动画状态可堆。
- 从设置页或后台回来时，视图重新创建。旧实现会在当前相位直接满强度出现。新实现只在出现的前 0.2 秒做一次淡入。

`HeartIconBoundsKey` 仍把圆心放在心形图标上。`HeartPressInteraction` 的点按 / 0.55 秒长按没改。

## 改了什么

只动 `Maso/Views/Screens/PlanPlayerScreen.swift` 里这一圈的采样。

- 节拍时钟不变：`time * bpm / 60 - 0.25`，仍和心形那一下对齐。
- 最大半径不变：`extent * (0.25 + 0.75 * progress)`。`Double` / `CGFloat` 的显式转换不改变这个数。
- 颜色不变：仍把 `progress` 交给 `WorkoutHeartLiquid.color(progress:)`。
- 出现条件不变：展开、前台、非设置页、非 Reduce Motion、新鲜 BPM、progress 有值。
- 仍是一圈。半径缓出（指数 1.6），透明度是两端为 0 的单峰，所以回绕时没有可看见的跳变。
- 线宽大约从 2.4pt 收到 1.5pt，模糊大约从 0.15pt 增到 1.05pt，边缘随扩散变软。
- 采样结果关掉继承来的隐式动画，避免下拉回弹时这一圈拖影，看起来像多圈。
- 平均不透明度大约 0.265，接近旧的 0.275。旧的 0.55 只出现在半径接近 0 的那一帧；现在最亮是 0.46，落在半径已经走出约三分之一的时候。告警仍靠原来的红向颜色和更大的半径，不靠多画一圈。

下面这些数是这一版的手感，不是验收指标，也不是用户指定的节拍：

| 选择 | 值 | 作用 |
| --- | --- | --- |
| 缓出指数 | 1.6 | 先离开图标，然后减速。再大就会在卡片边缘停住。 |
| 亮度峰值位置 | 心跳周期的 22% | 紧跟心形缩放，而不是在半径为 0 时最亮。 |
| 包络指数 | 1.35 | 两端斜率为 0，回绕不断开。 |
| 峰值不透明度 | 0.46 | 比旧的起点 0.55 柔，旅行中的一圈仍可读。 |
| 线宽 | 2.4 → 约 1.5pt | 最亮时接近原来的 2pt。 |
| 模糊 | 0.15 → 约 1.05pt | 只去掉剃刀边，不把玻璃卡片糊掉。 |
| 出现淡入 | 0.20 秒，仅层被创建时 | 盖住切页回来的第一帧。不改变心跳周期。 |

没改：BPM 文本、新鲜度、提醒阈值、颜色映射、告警升级底、紧凑态红描边、长按触感、卡片尺寸、无障碍标识、设置页、录制和自动记组。心形图标 `pow(..., 8)` 的缩放也没动。若回看时仍觉得“跳”，剩下的硬边是这下缩放，不是这一圈。

## SHA

| 文件 | 状态 | SHA-256 |
| --- | --- | --- |
| `Maso/Views/Screens/PlanPlayerScreen.swift` | 快照（补丁前） | `9d869071a4177ef26a250adccb84ca6b6b3d8baa8b2c3349c7ea218d1605dd86` |
| `Maso/Views/Screens/PlanPlayerScreen.swift` | 补丁后 | `ac99fdfe7aaeaef28c5d90b3c227403a529e12dfdd0cfc76441b5fcaed3f85f0` |
| `Maso/Views/RootView.swift` | 不写 | `f633da0eefe20e87a47f524fa2bce7972813e09745ca4558824edc7146719d41` |
| `MasoUITests/ExerciseLibraryBrowserUITests.swift` | 不写 | `5bab8c0d5ab8f684c381a725fd11af401e8a97e045c2210bcf5eca93ea1de471` |

云端 `main` `02106ee605ccb90db4b152252c04c27c96c1c196` 上的同名文件不是这个快照。不要拿它做三方对比后覆盖本机。

## 写回

在本机仓库根目录执行。脚本先核对 SHA，干跑，再写入；结果不符会从临时备份还原这一个文件。

```bash
cd /Users/yumowu/Projects/Maso-iOS
/path/to/patches/heart-ripple-motion/apply-heart-ripple.sh --check /Users/yumowu/Projects/Maso-iOS
/path/to/patches/heart-ripple-motion/apply-heart-ripple.sh /Users/yumowu/Projects/Maso-iOS
shasum -a 256 Maso/Views/Screens/PlanPlayerScreen.swift
# 必须是 ac99fdfe7aaeaef28c5d90b3c227403a529e12dfdd0cfc76441b5fcaed3f85f0
```

如果 `--check` 说 SHA 不是快照，说明快照之后又改过这个文件。停下来，只把 `heart-ripple-motion.patch` 里的两段手动合进去。不要整文件替换。

若编译器不接受 `Double(progress)` 或 `HeartRippleRing<Ink: ShapeStyle>`，不要改颜色函数的签名。最大半径那一行可以改回原来的 `extent * (0.25 + 0.75 * progress)`，只要乘上的是 `motion.spread` 而不是旧的线性 `phase`。

## 相对附件的 diff

可读 diff 就是同目录的 `heart-ripple-motion.patch`（约 100 行，两个 hunk）。`motion-check.txt` 是同一公式的数值表，用来说明旧曲线在 0 处从 0.55 跳变、新曲线两端为 0。它不是模拟器证据。

## 测试边界

做过：

- 快照 SHA 与附件 `SOURCE-SHA256SUMS` 一致。
- 补丁能原样打回快照，结果 SHA 为 `ac99fdfe…`。
- 再次执行脚本会发现已经打过，不再写入。
- SHA 不符时脚本退出且不改文件。
- 公式表：半径单调、透明度单峰、`t = 0` 与 `t = 0.999` 的透明度都接近 0。

没做过，也不能在这台 Linux 上做：

- 没有 Xcode / iOS 模拟器，没有编译。`WorkoutHeartLiquid` 不在附件里，不能宣称工程能编过。
- 没有正常心率、告警、按下松开、快速连点、切页回来、Reduce Motion 的真机或模拟器观察。
- 没有录屏，也没有用网页或合成画面冒充。

本机最小后续（沿用仓库里的 `scripts/low_memory_build.py`，不要直接 `xcodebuild`，不要关掉其它模拟器）：

```bash
python3 scripts/low_memory_build.py ui-test --simulator <UDID> --scheme Maso \
  --only-testing <UITestTarget>/WorkoutSignalsUITests/testHeartCardLongPressAndWarningCompactState
```

云端这份 `project.yml` 没有 UI test target，本机目标名以 Mac 工程为准。上面这条只回归长按和告警卡片是否还在，不能判断波纹好不好看。

手机上要看的是模拟器短录屏。把带新鲜心率的训练页装进已经开着的模拟器后：

```bash
xcrun simctl io booted recordVideo --codec h264 --force ~/Desktop/maso-heart-ripple.mp4
```

展开心率卡片看几拍；有告警态再看几拍；点按打开设置再关掉；长按展开/收起；快速连点；切到后台再回来。Ctrl-C 结束，把这个 mp4 传到手机看。附件里的 UI 测试会设 `MASO_WORKOUT_HEART_FIXTURE=1`，但读取这个变量的代码不在快照里，这里不能保证手动 `simctl launch` 会注入心率。注不进去就用一次真实训练的读数，不要拿私人健康日志当样例。

Reduce Motion 打开时这一圈应消失，BPM 文字还在。这是原条件，补丁没放宽它。
