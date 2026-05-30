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
- [ ] App Store Connect 建**新 App 记录** `com.yumowu.maso`(旧 `com.maso.app` 上填过的隐私问卷 / HealthKit 声明要在新记录重做)
- [ ] 内购商品 `com.maso.app.pro.{monthly,yearly,lifetime}` → 在新 App 下重建,代码里 `SubscriptionManager.swift` 的 product ID 改成 `com.yumowu.maso.pro.*`
- [ ] `Maso/Info.plist` 里 URL scheme 名字残留 `com.maso.app`(纯标识,无功能影响)
- [ ] 语言收窄到 en + zh-Hans(现有 ~10 种语言缺翻译会 fallback 英文)
