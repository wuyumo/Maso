# Maso — Privacy Policy / 隐私政策

**Last updated / 最后更新:** 2026-05-17

---

## English

### Summary

Maso is a fitness tracking app that runs almost entirely **on your device**. We do not run user accounts, we do not collect personal data, and we do not sell or share any information about you with third parties for marketing or analytics.

The only network call Maso makes is when you explicitly use the AI workout suggestion feature, which sends your training preferences to our backend proxy and then to DeepSeek's language model API.

### Data We Do NOT Collect

- We do not require sign-up. No email, password, name, or account.
- We do not run analytics SDKs (no Firebase, no Mixpanel, no third-party tracking).
- We do not show ads or share data with advertising networks.
- We do not access your contacts, location, microphone, or other personal data.

### Data Stored Locally on Your Device

The following data is stored **only on your iPhone or iPad**, using iOS's local storage. It never leaves your device unless you explicitly choose to share it:

- Workout plans you create (exercises, sets, reps, weights, rest durations)
- Workout history (which exercises you did, when, how heavy, how many reps)
- Personal records (PRs) computed from your history
- Your profile data entered during onboarding (gender, age, body weight, training days per week, target muscles)
- App preferences (units, language, default rest time, muscle detail toggle)

This data is included in **iCloud Backup** of your device when you back up your iPhone via Apple, following Apple's standard backup mechanism. We do not have access to your iCloud Backup.

### HealthKit Integration

If you grant permission, Maso may:

- **Write** completed workouts to Apple Health so they appear in your Activity rings and Health timeline.
- **Read** basic workout history from Health to keep your training timeline consistent across devices.

HealthKit data stays on your device under Apple's strict permission model. We never read this data on our servers. You can revoke HealthKit permission at any time in iOS Settings → Privacy → Health.

### Camera and Photo Library

When you create a shareable workout summary card, Maso may ask permission to:

- **Take a photo** with your camera (optional — only when you tap the "Add Photo" entry)
- **Read a photo** you select from your library (optional — same entry)

The chosen photo is embedded into your shareable summary card and **stays on your device**. We do not upload it anywhere. The card image is created locally and only leaves your device when you share it through iOS's system share sheet (e.g. Messages, Mail, Instagram).

### AI Workout Suggestions (Optional, Network)

If you have Maso Pro and enable AI workout suggestions, Maso may send the following to our backend proxy, which then forwards to DeepSeek's language model API:

- Your training profile (age, gender, body weight, target muscles, weekly training days)
- The last 14 days of your training history (exercise names, sets, reps, weights, dates)
- A list of candidate exercises to choose from

The proxy is hosted by us solely to keep API credentials secure; it does not store or log your data beyond the lifetime of the request. DeepSeek processes the prompt to generate a suggested workout plan and may retain it under their own privacy policy. See: https://www.deepseek.com/privacy

You can disable AI workout suggestions at any time in **Settings → Pro → AI suggestions**. With AI disabled, no data ever leaves your device.

### Sharing

When you tap **Share** on a workout card or muscle status card, Maso renders an image and hands it to iOS's system share sheet. From that point, the destination app (Messages, AirDrop, Instagram, etc.) decides what to do with the image, governed by that app's own privacy policy.

### Live Activities and Dynamic Island

Maso uses iOS Live Activities to display your active workout on the Lock Screen and Dynamic Island. This information is rendered on your device by iOS and never sent to our servers.

### Children

Maso is not directed at children under 13. We do not knowingly collect any data from anyone, including children.

### Data Retention

Because data is stored on your device, you control retention. Delete a workout, plan, or session inside Maso and it is removed immediately. Uninstall Maso and **all local data is permanently deleted** (except whatever you may have backed up to iCloud through Apple's backup mechanism).

### Your Rights (GDPR / CCPA)

Because we do not collect personal data on our servers, there is nothing to access, port, correct, or delete on our side beyond the AI proxy request lifetime. If you used AI suggestions and want to verify nothing is retained, contact us at the address below.

### Changes to This Policy

If we make material changes to this policy, we will update the "Last updated" date and post a notice in the app's next update.

### Contact

Questions or concerns?

**Email:** wuyumoawuyumo@gmail.com

---

## 简体中文

### 摘要

Maso 是一款健身追踪 App,几乎所有功能都在 **你的设备本地** 运行。我们不设用户账户,不收集个人数据,也不将你的任何信息出售或共享给第三方做营销或分析。

Maso 唯一的网络调用发生在你显式使用 AI 训练推荐功能时 — 此时会把你的训练偏好发送到我们的后端代理,再转发给 DeepSeek 语言模型 API。

### 我们 **不** 收集的数据

- 不需要注册。无邮箱、密码、姓名、账户。
- 不接入分析 SDK(不用 Firebase / Mixpanel / 第三方追踪)。
- 不显示广告,不共享数据给广告网络。
- 不访问你的通讯录、位置、麦克风或其他个人数据。

### 仅存储在你设备本地的数据

以下数据 **只存储在你的 iPhone / iPad 本地**(通过 iOS 本地存储)。除非你显式选择分享,数据不会离开你的设备:

- 你创建的训练计划(动作、组数、次数、重量、休息时长)
- 训练历史记录(做了哪些动作、时间、重量、次数)
- 基于历史自动计算的个人最佳记录(PR)
- 引导流程中填写的个人资料(性别、年龄、体重、每周训练天数、目标肌群)
- App 偏好设置(单位、语言、默认休息时间、肌肉细分开关)

当你通过 Apple 的标准机制备份 iPhone 时,这些数据会包含在 **iCloud 备份** 中。我们无法访问你的 iCloud 备份。

### HealthKit 集成

如果你授权,Maso 可能:

- **写入** 完成的训练到 Apple 健康,让训练数据出现在你的活动圆环和健康时间线里。
- **读取** 基础训练历史,让你的训练时间线在设备间保持一致。

HealthKit 数据受 Apple 严格的权限模型保护,留在设备本地。我们不会在服务器上读取这类数据。你可以随时在 iOS 设置 → 隐私 → 健康 里撤销权限。

### 相机和相册

当你为训练总结卡添加照片时,Maso 会请求权限:

- **使用相机** 拍照(可选 — 仅当你点击"添加照片"入口)
- **读取相册中的一张照片**(可选 — 同上入口)

选中的照片嵌入到分享卡片里,**留在你的设备本地**。我们不会上传到任何地方。卡片图在本地生成,只有当你通过 iOS 系统分享面板分享(给 Messages / 邮件 / Instagram 等)时才离开设备。

### AI 训练推荐(可选,需要网络)

如果你订阅了 Maso Pro 并启用 AI 训练推荐,Maso 会将以下内容发送到我们的后端代理,再转发给 DeepSeek 语言模型 API:

- 你的训练资料(年龄、性别、体重、目标肌群、每周训练天数)
- 最近 14 天的训练历史(动作名、组数、次数、重量、日期)
- 候选动作清单

后端代理仅用于保护 API 凭证安全 — 我们不会在请求生命周期之外存储或记录你的数据。DeepSeek 处理 prompt 生成推荐,可能根据其隐私政策保留请求数据。参见:https://www.deepseek.com/privacy

你可以随时在 **设置 → Pro → AI 推荐** 中关闭 AI 功能。关闭后,任何数据都不会离开你的设备。

### 分享

当你点击训练卡或肌肉状态卡上的 **分享** 时,Maso 在本地渲染图片然后递交给 iOS 系统分享面板。从那一刻起,目标 App(信息 / AirDrop / Instagram 等)如何处理图片,由该 App 自身的隐私政策决定。

### Live Activity 和灵动岛

Maso 使用 iOS Live Activity 在锁屏和灵动岛上显示进行中的训练。这些信息由 iOS 在设备上渲染,不会发送到我们的服务器。

### 儿童

Maso 不面向 13 岁以下儿童。我们不会有意识地收集任何人(包括儿童)的数据。

### 数据保留

由于数据存在你的设备本地,保留期由你控制。在 Maso 内删除某次训练 / 计划 / 历史 → 即时删除。卸载 Maso → **所有本地数据永久删除**(除非你通过 Apple 备份机制把它备份到了 iCloud)。

### 你的权利(GDPR / CCPA)

由于我们不在服务器上收集个人数据,除了 AI 代理请求的生命周期内,我们这边没有可以访问 / 导出 / 修正 / 删除的内容。如果你使用过 AI 推荐功能且想验证没有数据被保留,请通过下方邮箱联系我们。

### 政策变更

如有重大变更,我们会更新"最后更新"日期,并在下一次 App 更新中公告。

### 联系方式

有疑问或顾虑?

**邮箱:** wuyumoawuyumo@gmail.com
