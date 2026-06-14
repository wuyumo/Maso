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
**仍需在 ASC / 开发者后台手动做**(代码改不了的):
- [ ] App Store Connect 建新 App 记录 `com.yumowu.maso`(name "Masso")
- [ ] 开发者后台给 `com.yumowu.maso` + `.watchkitapp` 勾 HealthKit capability
- [ ] ASC 建内购: Subscription Group「Masso Pro」+ 2 订阅(monthly/yearly, 7天试用) + 1 lifetime 非消耗;各传审核截图,和首版一起提交
- [x] ASC 隐私问卷(2026-06-14 填毕, 草稿未发布): 数据类型 = 健身 + 客户支持, 两者均「App 功能 / 不关联身份 / 不追踪」; 追踪全选否; HealthKit 心率能量留设备不申报; 隐私政策 URL 已填 wuyumo.github.io/Maso/privacy-policy.html。⚠️「发布」按钮 Yumo 决定等最后提审时再点
- [ ] ASC App Review: HealthKit 用途说明(watch 读心率/能量, 写训练)
- [ ] ASC 元数据: 描述/关键词/支持URL/隐私政策URL/截图/年龄分级/Health&Fitness 类别
- [ ] Xcode GUI Archive → Validate → Upload(命令行会卡 No Accounts)
- [ ] (可选润色) 分享卡占位二维码换真 App Store 链接;补译界面残留英文(空状态/STEP)

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
