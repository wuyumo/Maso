# Masso — Privacy Policy / 隐私政策

**Last updated / 最后更新:** 2026-08-15

---

## English

### Summary

Masso is a fitness tracking app that runs almost entirely **on your device**. We do not run user accounts, and we never sell or share information about you with anyone for marketing or advertising. We do collect a small amount of anonymous usage data to understand which parts of the app work — you can turn it off in Settings, and it is described in full below.

When you use the AI coach, Masso sends your training profile and recent workout history to our backend proxy, which forwards it to Anthropic's Claude API. This also happens automatically when the app refreshes your recommended workout for the day. Masso additionally contacts our servers to validate a Masso Pro licence key, to send feedback you submit from within the app, and to fetch exercise images from a public CDN.

### Data We Do NOT Collect

- We do not require sign-up. No email, password, name, or account.
- We do not run advertising SDKs, and we are not in any ad network. No Firebase, no Facebook SDK, no cross-app tracking, no IDFA.
- We do not collect anything you type or log: your workouts, weights, reps, routine names, custom exercises, and coach notes never leave your device as analytics.
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

If you grant permission, Masso may:

- **Write** completed workouts to Apple Health so they appear in your Activity rings and Health timeline.
- **Read** basic workout history from Health to keep your training timeline consistent across devices.

**Apple Watch.** If you use the Masso watch app, it runs a workout session on your watch to show your live heart rate and record calories. Heart rate and workout data collected on the watch are stored only in Apple Health (HealthKit) on your devices — they are never transmitted to us or any third party.

HealthKit data stays on your device under Apple's strict permission model. We never read this data on our servers. You can revoke HealthKit permission at any time in iOS Settings → Privacy → Health.

### Anonymous usage analytics (optional, on by default — you can turn it off)

To see which parts of the app people actually use, Masso sends a small number of anonymous **counters** to TelemetryDeck (a privacy-focused analytics provider based in Germany, GDPR-compliant, no advertising business).

What is sent:

- The name of an event, e.g. `onboarding_completed`, `ai_routine_generate_success`, `data_export`
- A few non-identifying attributes attached to that event — always plain numbers or short fixed labels, e.g. `count: 4`, `surface: "coach"`, `reason: "network"`
- Your app version, iOS version, and language
- A random ID generated on first launch. It is not your Apple ID, email, phone, or advertising ID. It is reset if you delete and reinstall the app, and it cannot be traced back to you.

What is **never** sent: your workouts, sets, reps, weights, personal records, routine or exercise names, anything you typed to the coach, your profile numbers, or your Health data. The event system is built so that only numbers and fixed labels can be attached — free text cannot be sent even by mistake.

**Turning it off:** Settings → Your data → "Share anonymous usage data". With it off, nothing is sent at all.

### Camera and Photo Library

When you create a shareable workout summary card, Masso may ask permission to:

- **Take a photo** with your camera (optional — only when you tap the "Add Photo" entry)
- **Read a photo** you select from your library (optional — same entry)

The chosen photo is embedded into your shareable summary card and **stays on your device**. We do not upload it anywhere. The card image is created locally and only leaves your device when you share it through iOS's system share sheet (e.g. Messages, Mail, Instagram).

### AI Workout Suggestions (Optional, Network)

The AI coach is available to all users. When it runs — either because you asked it to, or because the app is refreshing your recommended workout on launch — Masso sends the following to our backend proxy, which forwards it to Anthropic's Claude API:

- Your training profile (age, gender, body weight, target muscles, weekly training days)
- The last 14 days of your training history (exercise names, sets, reps, weights, dates)
- Your best recent sets, and any notes you have written for the coach (for example an injury you asked it to work around)
- A list of candidate exercises to choose from

The proxy is hosted by us solely to keep API credentials secure; it does not store or log your data beyond the lifetime of the request. Anthropic processes the prompt to generate a suggested workout plan under its own privacy policy. See: https://www.anthropic.com/legal/privacy

There is currently no in-app switch to turn the AI coach off. If you do not want this data sent, turn off network access for Masso in iOS Settings; the app keeps working and falls back to generating plans on-device.

### Other network calls

- **Masso Pro licence validation** — if you activate Pro, your licence key is sent to our proxy to be checked.
- **In-app feedback** — if you send feedback from inside the app, your message is delivered to our email, together with the app version, iOS version, and device language.
- **Exercise images** — exercise photos are fetched on demand from a public CDN (jsDelivr) and cached on your device.

### Sharing

When you tap **Share** on a workout card or muscle status card, Masso renders an image and hands it to iOS's system share sheet. From that point, the destination app (Messages, AirDrop, Instagram, etc.) decides what to do with the image, governed by that app's own privacy policy.

### Live Activities and Dynamic Island

Masso uses iOS Live Activities to display your active workout on the Lock Screen and Dynamic Island. This information is rendered on your device by iOS and never sent to our servers.

### Children

Masso is not directed at children under 13. We do not knowingly collect any data from anyone, including children.

### Data Retention

Because data is stored on your device, you control retention. Delete a workout, plan, or session inside Masso and it is removed immediately. Uninstall Masso and **all local data is permanently deleted** (except whatever you may have backed up to iCloud through Apple's backup mechanism).

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

Masso 是一款健身追踪 App,几乎所有功能都在 **你的设备本地** 运行。我们不设用户账户,也绝不会把你的任何信息出售或共享给任何人做营销或广告。我们会收集少量**匿名使用统计**以了解 App 的哪些部分真的有人用 —— 你可以在设置里关掉,详细说明见下文。

使用 AI 教练时,Masso 会把你的训练档案和近期训练记录发送到我们的后端代理,再转发给 Anthropic 的 Claude API。App 启动时自动刷新当日推荐训练也会触发同一条链路。此外还有三类网络请求:校验 Masso Pro 授权码、发送你在 app 内提交的反馈、以及从公共 CDN 拉取动作图片。

### 我们 **不** 收集的数据

- 不需要注册。无邮箱、密码、姓名、账户。
- 不接入广告 SDK,不在任何广告网络里。没有 Firebase、没有 Facebook SDK、没有跨 App 追踪、不读 IDFA。
- 你输入和记录的一切 —— 训练、重量、次数、计划名、自创动作、教练备注 —— 都不会作为统计数据离开你的设备。
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

如果你授权,Masso 可能:

- **写入** 完成的训练到 Apple 健康,让训练数据出现在你的活动圆环和健康时间线里。
- **读取** 基础训练历史,让你的训练时间线在设备间保持一致。

HealthKit 数据受 Apple 严格的权限模型保护,留在设备本地。我们不会在服务器上读取这类数据。你可以随时在 iOS 设置 → 隐私 → 健康 里撤销权限。

### 匿名使用统计(可选,默认开启,可随时关闭)

为了解 App 的哪些部分真的有人用,Masso 会向 TelemetryDeck(德国的注重隐私的统计服务商,符合 GDPR,不做广告业务)发送少量**匿名计数**。

发送的内容:

- 事件名称,例如 `onboarding_completed`、`ai_routine_generate_success`、`data_export`
- 附在该事件上的少量非身份属性,永远是纯数字或短的固定标签,例如 `count: 4`、`surface: "coach"`、`reason: "network"`
- App 版本、iOS 版本、语言
- 首次启动时随机生成的一个 ID。它不是你的 Apple ID、邮箱、手机号或广告标识符;删除重装即重置,无法回溯到你本人。

**绝不**发送的内容:你的训练记录、组次、重量、个人记录、计划名与动作名、你对教练说过的任何文字、你的身体数据、以及健康数据。事件系统在类型层面就只允许附加数字和固定标签 —— 自由文本想发也发不出去。

**关闭方法**:设置 → 你的数据 → 「共享匿名使用数据」。关闭后一条都不会发送。

### 相机和相册

当你为训练总结卡添加照片时,Masso 会请求权限:

- **使用相机** 拍照(可选 — 仅当你点击"添加照片"入口)
- **读取相册中的一张照片**(可选 — 同上入口)

选中的照片嵌入到分享卡片里,**留在你的设备本地**。我们不会上传到任何地方。卡片图在本地生成,只有当你通过 iOS 系统分享面板分享(给 Messages / 邮件 / Instagram 等)时才离开设备。

### AI 训练推荐(可选,需要网络)

AI 教练对所有用户开放。当它运行时 — 无论是你主动触发,还是 app 启动时刷新当日推荐 — Masso 会将以下内容发送到我们的后端代理,再转发给 Anthropic 的 Claude API:

- 你的训练资料(年龄、性别、体重、目标肌群、每周训练天数)
- 最近 14 天的训练历史(动作名、组数、次数、重量、日期)
- 候选动作清单

后端代理仅用于保护 API 凭证安全 — 我们不会在请求生命周期之外存储或记录你的数据。Anthropic 处理 prompt 生成推荐,适用其自身的隐私政策。参见:https://www.anthropic.com/legal/privacy

目前 app 内没有关闭 AI 教练的开关。如果你不希望这些数据被发送,可以在 iOS 设置里关掉 Masso 的网络权限 — app 仍可正常使用,会回退到完全在本地生成计划。

### 其他网络请求

- **Masso Pro 授权校验** — 激活 Pro 时,授权码会发到我们的代理做校验。
- **App 内反馈** — 你从 app 内发送反馈时,内容会连同 app 版本、iOS 版本、设备语言一起发到我们的邮箱。
- **动作图片** — 动作照片按需从公共 CDN(jsDelivr)拉取并缓存在本机。

### 分享

当你点击训练卡或肌肉状态卡上的 **分享** 时,Masso 在本地渲染图片然后递交给 iOS 系统分享面板。从那一刻起,目标 App(信息 / AirDrop / Instagram 等)如何处理图片,由该 App 自身的隐私政策决定。

### Live Activity 和灵动岛

Masso 使用 iOS Live Activity 在锁屏和灵动岛上显示进行中的训练。这些信息由 iOS 在设备上渲染,不会发送到我们的服务器。

### 儿童

Masso 不面向 13 岁以下儿童。我们不会有意识地收集任何人(包括儿童)的数据。

### 数据保留

由于数据存在你的设备本地,保留期由你控制。在 Masso 内删除某次训练 / 计划 / 历史 → 即时删除。卸载 Masso → **所有本地数据永久删除**(除非你通过 Apple 备份机制把它备份到了 iCloud)。

### 你的权利(GDPR / CCPA)

由于我们不在服务器上收集个人数据,除了 AI 代理请求的生命周期内,我们这边没有可以访问 / 导出 / 修正 / 删除的内容。如果你使用过 AI 推荐功能且想验证没有数据被保留,请通过下方邮箱联系我们。

### 政策变更

如有重大变更,我们会更新"最后更新"日期,并在下一次 App 更新中公告。

### 联系方式

有疑问或顾虑?

**邮箱:** wuyumoawuyumo@gmail.com
