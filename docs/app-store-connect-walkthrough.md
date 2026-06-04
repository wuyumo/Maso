# App Store Connect 上架手册 — Maso

按顺序跟着做. 跳步骤会被卡在某个 "field is required" 上死循环.

预计总耗时:
- 第一次熟悉流程: 3-4 小时
- 后续 build 更新: 30 分钟

---

## 前提

- [x] Apple Developer Program 已付费 ($99/yr) — **Eric Ng 付费 team**
- [x] Apple ID: `wuyumoawuyumo@outlook.com` (US store, **Team ID `TW8ZVVX529`**)
      ⚠️ 旧免费个人 team `UR6F66266C` 只能装机不能上架,别用它登 ASC
- [x] Privacy Policy + Terms 已部署到 GitHub Pages (2026-06 验证 HTTP 200)
- [x] 截图已生成: `build/screenshots/{en-US,zh-Hans}/` 各 8 张
- [ ] (本手册要做的) Xcode archive (新 bundle `com.yumowu.maso`) + ASC 配置 + 上传

---

## Step 1 — App 创建 (10 分钟)

去: <https://appstoreconnect.apple.com/apps>

点 **`+` → New App**, 填:

| 字段 | 填什么 |
|---|---|
| Platforms | iOS |
| Name | `Maso` (或 `Maso: AI Workout Tracker` 拉关键词) |
| Primary Language | English (U.S.) |
| Bundle ID | **`com.yumowu.maso`** (从下拉选; 必须先在 Xcode 用 TW8ZVVX529 archive 过一次, 它才会出现在下拉里) |
| SKU | `maso-ios-001` (内部 SKU, 随意) |
| User Access | Full Access |

→ Create

---

## Step 2 — In-App Purchase 注册 (30 分钟)

进 App → 左边栏 **Monetization → In-App Purchases**.

点 `+` 创建 3 个 product:

### 2.1 月度订阅
- Type: **Auto-Renewable Subscription**
- Reference Name: `Pro Monthly`
- Product ID: `com.yumowu.maso.pro.monthly`
- Subscription Group: 创建新 group 命名 `Maso Pro` (group ID 系统自动生成)
- Subscription Duration: **1 Month**
- Price: **USD 4.99** (Tier 5 or 自定义)
- Free Trial: **7 days, free**, eligibility: New subscribers
- Localization (至少 en-US + zh-Hans):
  - Display Name: `Maso Pro — Monthly` / `Maso Pro — 月度`
  - Description: 短一句, e.g. `Unlimited plans, full history, Apple Health sync.` / `无限训练计划, 完整历史, Apple Health 同步.`

### 2.2 年度订阅
- Type: **Auto-Renewable Subscription**
- Reference Name: `Pro Yearly`
- Product ID: `com.yumowu.maso.pro.yearly`
- Subscription Group: 选已建的 `Maso Pro`
- **Subscription Level**: 设为比 monthly 高 (e.g. Level 1, monthly 是 Level 2) — Apple 用 level 判断"升级 vs 降级", 让用户从 monthly 切 yearly 走 upgrade flow
- Subscription Duration: **1 Year**
- Price: **USD 29.99**
- Free Trial: **7 days, free**
- Localization:
  - `Maso Pro — Yearly` / `Maso Pro — 年度`
  - `Unlimited plans, full history, Apple Health sync. Save 50% vs monthly.` / `无限训练计划, 完整历史, Apple Health 同步. 比月度省 50%.`

### 2.3 永久买断
- Type: **Non-Consumable**
- Reference Name: `Pro Lifetime`
- Product ID: `com.yumowu.maso.pro.lifetime`
- Price: **USD 79.99**
- Localization:
  - `Maso Pro Lifetime` / `Maso Pro 永久版`
  - `One-time purchase. Unlock everything forever, no recurring charges.` / `一次性购买. 永久解锁所有 Pro 功能, 无续费.`

**注意**: 创建后 product 状态是 "Missing Metadata" 或 "Ready to Submit". 必须在 app 提交时**同一份 build 提交订阅** (左侧 In-App Purchase tab 旁边的 "Add to App Version" 链接).

---

## Step 3 — App 信息填写 (30 分钟)

### 3.1 App Information (左栏)
- Subtitle: `AI workout tracker` (30 字符内, 出现在 App Store 搜索结果)
- Privacy Policy URL: `https://wuyumo.github.io/Maso/privacy-policy.html`
- Category:
  - Primary: **Health & Fitness**
  - Secondary: **Lifestyle** (可选)
- Age Rating: 点 **Edit** → 全部填 None → 显示 **4+**

### 3.2 Pricing and Availability
- Price: **Free** (Pro 通过 IAP 解锁)
- Availability: All countries/regions

### 3.3 App Privacy
点 "Get Started" 走问卷, 答:
- Do you or your third-party partners collect data? → **No** (Maso 完全 local-first)
- 如果系统因 HealthKit 权限或 IAP 强制要求声明, 选最小化:
  - Health & Fitness data → **Not Linked to User**, **Not Used for Tracking**
  - Purchase History → **Not Linked to User**, **Not Used for Tracking**

### 3.4 App Review Information
- Sign-in required: **No** (Maso 无登录)
- Contact: 自己的姓名 + 邮箱 + 电话
- Notes: 给审核员的提示, 比如:
  ```
  Maso is an offline-first fitness tracker. No login required.

  To test Pro features, sandbox tester can purchase any of the 3 IAP plans
  (monthly / yearly / lifetime). Trial is 7 days, no payment required.

  AI workout suggestions require Pro. After purchase: Today tab → Pro banner
  → toggle "AI workouts" in Settings.
  ```

---

## Step 4 — Metadata + Assets (60 分钟)

复用我们已经写好的中英文案: `docs/app-store-metadata.md`

### 4.1 截图 (必填)
要求: **6.7" iPhone 16 Pro Max** (1320 × 2868) + 至少 3 张, 推荐 8 张
- 我们已经生成的位置: `build/screenshots/en-US/*.png` 和 `build/screenshots/zh-Hans/*.png`
- 如果分辨率不对, 跑 `scripts/screenshot_simulator.sh` 重新生成
- 上传顺序建议: 主流程 → 训练记录 → 肌肉状态 → 设置

### 4.2 App Preview (可选)
15-30 秒短视频. 跳过即可, 上线后再补.

### 4.3 Localizations
点右上角 "+" 加语言. 至少加这 2 个:
- English (U.S.) — 默认必填
- Simplified Chinese — 提升中国 / 海外华人下载

每个语言要填:
- Name, Subtitle, Promotional Text, Description, Keywords, Support URL, Marketing URL (optional)

**从 `docs/app-store-metadata.md` 直接拷贝**, 内容已经审过.

Support URL: `https://wuyumo.github.io/Maso/`
Marketing URL: 同上, 可选

---

## Step 5 — Build 上传 (20 分钟)

### 5.1 Xcode archive
1. Xcode 打开 `Maso.xcodeproj`
2. 上方选 destination: **Any iOS Device (arm64)** (注意不是 Simulator)
3. 菜单: **Product → Archive**
4. 等 ~2 分钟. Archive 完成后弹 Organizer 窗口.

### 5.2 上传到 App Store Connect
在 Organizer:
1. 选 Maso archive → **Distribute App**
2. Distribution method: **App Store Connect**
3. Destination: **Upload**
4. Signing: **Automatically manage signing**
5. 走完 → 上传开始, 大概 5 分钟

### 5.3 等 Build 处理
回到 App Store Connect: TestFlight tab.
Build 上传后状态 "Processing", 等 10-30 分钟变 "Ready to Test".

期间可能收邮件:
- ⚠️ "Missing Compliance" → 在 build 详情页填 export compliance (我们 Info.plist 已经 bake 了 `ITSAppUsesNonExemptEncryption=false`, 应该不再问)
- ❌ "Invalid Binary" → 看邮件具体原因, 常见是 Privacy Manifest 缺 / icon 缺 / entitlement 不匹配

---

## Step 6 — TestFlight 内测 (1-2 天)

### 6.1 Internal Testing (自己用)
- Build 状态 Ready → 加自己作为 Internal Tester (邮箱自动用 Apple ID)
- iPhone 装 TestFlight app → 收邀请 → 装 Maso → 跑一遍主流程
- **必测**:
  - [ ] IAP 全 flow (sandbox 不扣钱)
  - [ ] Restore Purchases
  - [ ] Privacy / Terms URL 跳通
  - [ ] HealthKit 权限弹窗 + 写入
  - [ ] 相机 / 相册权限
  - [ ] Live Activity 锁屏显示
  - [ ] 切系统语言 → app 跟着切
  - [ ] 关网络后 free workout 仍能用

### 6.2 External Testing (可选, 0-2 天审核)
邀请最多 10000 个外部测试员. 第一次需要 Apple Beta 审核 (1-2 天).
不急的话跳过, 直接走 6.3.

### 6.3 Submit for Review
回 App Store tab → 选 Build → "Submit for Review"

回答两个问题:
- Q: 该 build 是否使用 advertising identifier (IDFA)? → **No**
- Q: 该 build 是否使用 encryption beyond exempt? → **No** (我们已经 bake 了)

提交. Apple 审核 1-3 天 (这一两年快了, 多数 24 小时内).

---

## 常见拒审原因 (预防)

| 拒审条款 | 我们的预防 |
|---|---|
| 2.1 — Crash | TestFlight 内测尽量跑过主流程 |
| 1.4.1 — 健身类无医疗免责 | ✅ Settings → Health & Safety 已加 |
| 3.1.1 — IAP 非 StoreKit | ✅ 已用 StoreKit2 |
| 3.1.2(a) — 订阅 paywall 无 Terms/Privacy 链接 | ✅ Paywall footer 两个 Link 都接好 |
| 3.1.2(b) — 订阅条款不全 | ✅ Terms 4.2-4.5 已覆盖 trial / 续费 / 取消 / 退款 |
| 5.1.1 — Privacy Policy 链接坏 | ✅ GitHub Pages 部署 |
| 5.1.2 — Privacy Manifest 缺 reason code | ✅ PrivacyInfo.xcprivacy 已带 |
| 5.1.5 — HealthKit 用途说明不清 | ✅ NSHealthShare/Update UsageDescription 已写 |
| 4.0 — 设计不像 native iOS | ✅ 用了 native TabView / .sheet / .swipeActions |

---

## 提交后

1. **Status 变化**: Waiting for Review → In Review → Pending Developer Release (或 Ready for Sale)
2. **Pending Developer Release** = 通过审核, 等你点 "Release this version" 上线. 通常你自己控制发布时机.
3. **Ready for Sale** = 公开上架. App Store 全球可下载, 一般 4-24 小时世界各区生效.

---

## 紧急联系

审核被拒 / 异常情况:
- App Store Connect 内部消息 (有未读会邮件提醒)
- Developer Support: <https://developer.apple.com/contact/>

每次更新只需要从 **Step 5** 开始 (新 archive → 上传 → TestFlight → Submit).
