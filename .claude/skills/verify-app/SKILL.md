---
name: verify-app
description: 端到端验证 Maso iOS app——驱动模拟器、用内置 showcase 种子路由逐屏启动+截图,断言编译通过、exercises.json 数据完整、各关键页(today/动作列表/计划详情/训练中)真渲染且互不相同。改完 Swift 代码、动了 exercises.json、或重构了 ExerciseLibraryBrowser/ExercisePickerSheet/播放器后,装真机前先跑它当烟测。
---

# verify-app — Maso iOS 验证(Simulator)

iOS 没法用 headless 浏览器,所以用**模拟器**驱动。Maso 几乎没有 accessibilityIdentifier,
硬点按钮很脆,所以改用 app 自带的**确定性 showcase 路由**(`SIMCTL_CHILD_MASO_SHOWCASE_SEED=1` +
`SIMCTL_CHILD_MASO_SHOWCASE=<route>`,跟 `scripts/shoot_screenshots_auto.sh` 同一机制)直接跳到每个
关键页 + 种子数据,截图后断言它真的渲染出来了。

## 怎么跑

```bash
bash .claude/skills/verify-app/driver.sh
# 或指定模拟器: bash .claude/skills/verify-app/driver.sh "iPhone 17 Pro"
```

自动:挑一台已启动的模拟器(没有就按名字启)→ xcodegen generate → 数据体检 → 编译 → 逐路由跑。
截图落在 `build/verify-screens/`。模拟器构建**不需签名**,CLI 直接能跑。

## 断言了什么(硬断言,失败即 exit 1)

| 步 | 断言 |
|----|------|
| generate | `xcodegen generate` 成功(工程与 project.yml 同步) |
| 数据 | `Maso/Resources/exercises.json`(**运行时真正加载的那个**)能解析且条目 ≥ 500 |
| 编译 | Debug 模拟器构建成功(真正的门槛) |
| 每条路由 | today / 动作列表 / 计划详情 / 训练中:启动拿到 pid + 截图非空(真像素,不是黑屏/失败帧) |
| 全局 | 各路由截图**互不相同**(证明真渲染了不同页,而非崩到桌面 / 卡在启动屏)。状态栏钉 9:41 防时钟造成假"不同" |

## 实现要点 / 坑

- **不靠 accessibilityIdentifier。** 用 showcase 路由 + 截图差异来证明导航成功,不点按钮。
  路由集合见 `shoot_screenshots_auto.sh`("" today / routines / exercises / plan_detail / player / rest / history / free_workout)。
- **bundle id = `com.yumowu.maso`。** 注意 `scripts/screenshot_simulator.sh` 里写的旧 `com.maso.app` 是过期的,别照抄。
- **UDID 检测用 node 解析 `simctl -j`**,不要用正则(模拟器中途关机时正则容易取空 → destination 报错)。
- **数据体检很关键。** memory 记着 app 加载 `exercises.json` 而非 `exercises-new.json`;只改源文件没同步到
  bundle 的那个,这一步会抓到(条目数不对)。

## 想加断言?

- 改 showcase 路由集合 → 编辑 driver.sh 的 `ROUTES`。
- 想更强的"内容"断言(目前只到"非空+互不相同"):可在某路由截图后接 OCR 或 pixel 区域比对;
  但别依赖硬点按钮——Maso 没有稳定 identifier。
