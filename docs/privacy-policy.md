# Masso — Privacy Policy / 隐私政策

Last updated: 12 November 2026

Contact: wuyumoawuyumo@gmail.com

## English

### Your records

Masso stores your workout plans, sets, progress, meal records, selected photos, sleep summaries and preferences on your device. No Masso account is required. iOS backups may include these records under your Apple settings. Deleting the app removes its local data; an Apple backup may retain a separate copy.

We do not sell personal data, use advertising SDKs or track you across other companies’ apps. Local storage does not mean every feature works offline: AI, purchases, feedback, and uncached exercise media require a network connection.

### AI features and your choice

In version 3.0 and later, Masso asks for permission before sending personal content for AI processing. You may decline and keep using basic workout logging, history and local calculations. You can withdraw permission in Settings → AI data sharing. Automatic workout recommendations send no AI request before this permission is granted. Earlier versions may request recommendations automatically; update to use the new control.

Depending on the feature you use, AI requests may contain:

- Your entered training profile, goals, available equipment, preferences and notes
- Recent strength-training records and the messages you send to AI Coach
- A photo you select for meal, physique or workout-plan analysis, or your meal description

Our backend forwards these requests to **Anthropic (Claude) or Alibaba Cloud Bailian (Qwen)**, depending on the configured service and fallback route. Bailian uses its Beijing endpoint, so processing may occur in mainland China; Anthropic processing is governed by its policy linked below. Information visible in the screenshots you select is included in image analysis. Cloudflare and Vercel host our request-routing infrastructure. Our application handler does not keep AI request bodies as a chat database; chat history and meal-analysis results are retained locally. Infrastructure and AI providers may retain operational or security records according to their terms. Do not submit information you do not want these providers to process.

AI data-sharing permission does not grant permission to publish your photos. Share-card photos stay local unless you explicitly share the card. AI may be inaccurate: meal nutrients are estimates, and muscle recovery is a training estimate rather than a medical measurement.

Provider information: [Anthropic privacy policy](https://www.anthropic.com/legal/privacy), [Bailian data privacy notice](https://help.aliyun.com/zh/model-studio/privacy-notice), [Alibaba Cloud privacy policy](https://help.aliyun.com/zh/document_detail/2705225.html), [Cloudflare privacy policy](https://www.cloudflare.com/privacypolicy/), [Vercel privacy policy](https://vercel.com/legal/privacy-policy). Bailian states that API data is not used for model training, but model/application call data is stored under its service agreement; this is not a zero-retention service.

### Apple Health and Apple Watch

Health permissions are separate and optional. Masso can read authorized sleep stages and workout summaries, and write completed workouts. The Watch companion can record workouts, heart rate and energy in Apple Health. Imported Apple Health sleep, heart-rate and workout records are processed on your devices; they are not included in requests to our AI provider or our analytics service. Turn permissions off in Apple Health or iOS Settings. Removing an imported Masso record does not delete the original Health record.

### Camera, photos and speech

Camera and photo-library access are requested when you choose to add an image. An image submitted to an AI feature follows the AI section above; an image added only to a share card stays on your device. iOS keyboard dictation is controlled by Apple and your system settings. Masso does not continuously record your microphone.

### Purchases

New subscriptions in version 3.0 use Apple In-App Purchase. Apple processes payment and provides signed entitlement information to restore and validate access. We do not receive your card or bank details. Restore Purchase on the upgrade screen restores Apple purchases for the signed-in Apple ID. The app does not show a web-purchase restore form. A Polar licence already saved on the device can still be rechecked through our backend. Polar handles information provided during its original checkout under [its privacy policy](https://polar.sh/legal/privacy).

### Optional referral program

Optional referral codes: When you choose Check referral code in a compatible Masso version, we bind the first code to a random installation identifier held in the device Keychain. We receive that identifier, code and claim time, and verified Apple subscription records: transaction and original transaction identifiers, product, price/currency, purchase and expiry dates, trial/offer status, and refund or revocation status. We use them to validate the referral, prevent duplicate credit, measure trial-to-paid conversion and reconcile partner commissions. Partners see aggregate results and statements, rather than customer transaction identifiers or contact details. This feature does not send health, workout, photo or AI-chat content. Creator portal login separately uses email/name and Resend email codes; Cloudflare hosts the program, and Vercel routes App referral requests. Login codes expire after ten minutes and sessions after seven days. Daily salted link-visit hashes are kept for up to 90 days. Transaction and accounting records are retained for reconciliation, disputes and applicable obligations. Referral handling is separate from optional usage analytics and AI sharing. Contact support for access, correction or deletion requests; we may need the code and enough information to locate a record. We do not receive Apple passwords or card/bank details.

### Optional usage analytics

In version 3.0 and later, optional usage analytics stays off until you explicitly enable “Share anonymous usage data” in Settings. Earlier versions may have enabled it by default; you can turn it off in Settings. When enabled, Masso sends event counts, short predefined event attributes, app/OS version, language and a random installation identifier to **TelemetryDeck**. The provider further hashes identifiers. These records help us understand feature use and reliability; they are not advertising data. Training usage events can include the number of planned and completed sets and elapsed workout time, together with a hashed plan identifier. We do not attach exercise weights or repetitions, meal descriptions, AI messages, photos, imported Apple Health records or heart rate to these events. Turning analytics off stops new event transmission. See [TelemetryDeck privacy information](https://telemetrydeck.com/privacy/).

### Bug reports

When you submit a bug report, we receive its text, app version, OS version and language. Reports are queued in Cloudflare storage and grouped into a weekly email to our support inbox using FormSubmit. Queued copies are removed after successful delivery; the delivered email remains for support follow-up. Avoid including sensitive details in reports. You may contact support to request deletion where we can identify your report.

### Exercise media and generation requests

Exercise covers and approved videos may be fetched from a CDN, including Cloudflare R2, and cached locally. Hosting providers receive the network information needed to deliver them. If a future demo-generation service is enabled, its separate confirmation must show the material shared, cost and shared-library use before a job is created. Selecting a workout plan does not itself authorize a paid generation job.

### Sharing, widgets and notifications

Share images are rendered locally and handed to the destination you select in the iOS share sheet. That service then applies its own policy. Widgets use a local shared App Group snapshot. Workout, meal and sleep reminders are scheduled locally after notification permission; you can switch each kind off in Settings.

### Retention and requests

Local records remain until you edit/delete them or remove the app. AI messages are not retained as a chat database by our application backend, but provider processing/retention is governed by the policies linked above. Feedback and analytics have the separate handling described above. Apple and Polar retain purchase information under their policies and applicable requirements. To request access, correction or deletion of information held by us, email support. We may need enough information to locate a report; do not send passwords or payment details.

Masso is not designed for children under 13. We update this page when practices change. Fitness, nutrition and sleep information is general guidance, not medical advice.

## 简体中文

### 你的记录

Masso 将训练计划、组数、进步、餐食、所选照片、睡眠汇总与偏好保存在设备上，无需注册 Masso 账户。iOS 可能按你的 Apple 设置备份这些记录。删除 App 会删除其本地数据，但 Apple 备份可能保留独立副本。

我们不出售个人资料，不接入广告 SDK，也不进行跨 App 广告追踪。AI、购买、反馈及尚未缓存的动作素材需要联网，不能将本地存储理解为所有功能均可离线使用。

### AI 功能及你的选择

从 3.0 版起，Masso 在向 AI 发送个人内容前会征求许可。拒绝后仍可使用基础训练记录、历史与本地计算。你可以在「设置 → AI 数据共享」中撤回许可。许可前，自动训练推荐不会发送 AI 请求。旧版本可能自动请求推荐，更新后可使用此控制。

根据你使用的功能，请求可能包含：

- 你填写的训练资料、目标、器械、偏好和备注
- 近期力量训练记录，以及发送给 AI Coach 的聊天内容
- 你主动选择用于餐食、体型或训练计划分析的照片，或餐食文字描述

我们的后端根据配置和备用路由，将请求转发给 **Anthropic（Claude）或阿里云百炼（通义千问）**。百炼使用北京端点，数据可能在中国大陆处理；Anthropic 的处理方式见下方政策。你主动选择的截图中可见的信息也会包含在图片分析中。Cloudflare 和 Vercel 提供请求转发基础设施。我们的应用处理程序不将 AI 请求正文保存为服务器聊天数据库；聊天记录和餐食分析结果保存在本地。基础设施及 AI 服务商可能按其条款保留运行或安全记录。请勿提交你不希望这些服务商处理的信息。

同意 AI 数据共享不等于同意公开照片。仅用于分享卡片的照片保留在本地，直到你主动分享。AI 可能出错：餐食营养为估算值，肌肉恢复也是训练参考，并非医学测量。

服务商政策：[Anthropic 隐私政策](https://www.anthropic.com/legal/privacy)、[百炼数据隐私说明](https://help.aliyun.com/zh/model-studio/privacy-notice)、[阿里云隐私政策](https://help.aliyun.com/zh/document_detail/2705225.html)、[Cloudflare](https://www.cloudflare.com/privacypolicy/)、[Vercel](https://vercel.com/legal/privacy-policy)。百炼说明 API 数据不用于模型训练，但会按服务协议保存模型与应用调用数据，并非零留存服务。

### Apple 健康与 Apple Watch

健康权限独立且可选。Masso 可读取获准的睡眠阶段、训练汇总，并写入已完成训练。手表可将训练、心率和能量记录到 Apple 健康。导入的 Apple 健康睡眠、心率及训练记录在设备上处理，不发送给 AI 服务商或统计服务。你可在 Apple 健康或 iOS 设置撤销权限。删除 Masso 内的导入记录不会删除健康中的原记录。

### 相机、照片与语音

只有你选择添加图片时才请求相关权限。用于 AI 分析的图片遵循上文；仅用于分享卡片的图片保留在本地。iOS 键盘听写由 Apple 和系统设置管理，Masso 不持续录音。

### 购买

3.0 版的新订阅通过 Apple 内购完成。Apple 处理付款并提供签名权益信息，用于恢复和验证权限；我们不会收到银行卡或银行账户资料。升级页的「恢复购买」只恢复当前 Apple ID 的 Apple 购买。App 不提供网页购买恢复表单。已经保存在本机的 Polar 授权仍可通过我们的后端复核。Polar 按[其隐私政策](https://polar.sh/legal/privacy)处理其原始结账资料。

### 可选推荐计划

可选推荐码：在支持此功能的 Masso 版本中主动点击「检查推荐码」后，我们会将首个推荐码与保存在设备钥匙串中的随机安装标识绑定，接收该标识、推荐码、绑定时间及 Apple 验证的订阅记录，包括交易与原始交易标识、商品、价格和币种、购买与到期日期、试用及优惠状态、退款或撤销状态，用于核验推荐、避免重复计数、统计试用转付费及核对合作佣金。合作方看到汇总结果及结算单，不会看到顾客的交易标识或联系方式。推荐功能不发送健康、训练、照片或 AI 聊天内容。合作方门户另以邮箱和名称登录，由 Resend 发送验证码、Cloudflare 托管服务，Vercel 转发 App 推荐请求。验证码十分钟有效，登录会话七天有效；按日加盐的链接访问哈希最长保留九十天，交易及会计记录按核对、争议处理和适用义务保留。推荐处理与可选使用统计、AI 数据共享分别管理。访问、更正或删除请求请联系支持，并提供足以定位记录的推荐码等资料；请勿发送密码或付款资料。我们不会收到 Apple 密码或银行卡、银行账户信息。

### 可关闭的使用统计

3.0 及后续版本的可选使用统计默认不发送，只有你在设置主动开启「共享匿名使用数据」后才启用。早期版本可能默认开启，你可以随时在设置关闭。开启后，Masso 会向 TelemetryDeck 发送事件次数、预定义的简短属性、App／系统版本、语言及随机安装标识。服务商会进一步哈希标识，用于了解功能使用及可靠性，不用于广告。训练使用事件可能包含计划与完成组数、训练经过时长及哈希化计划标识；不附带动作重量或次数、餐食描述、聊天、照片、导入的 Apple 健康记录或心率。关闭后停止新统计发送。[TelemetryDeck 隐私信息](https://telemetrydeck.com/privacy/)。

### 问题反馈

主动提交反馈时，我们收到反馈文字、App／系统版本及语言。内容暂存于 Cloudflare，通过 FormSubmit 汇总成每周邮件发送到支持邮箱；成功发送后删除队列副本，邮件保留用于支持跟进。请勿在反馈中填写敏感资料。如能定位你的反馈，可联系支持申请删除。

### 动作素材与生成请求

动作封面和已审核视频可能从 CDN（含 Cloudflare R2）下载并缓存。服务商会收到完成网络传输所需的信息。未来若开启动作生成服务，创建任务前须另外说明共享素材、价格及共享素材库用途；选择训练计划本身不代表同意付费生成。

### 分享、小组件及通知

分享图片在本地生成，仅交给你在系统分享面板中选择的应用，之后由目标服务的政策管理。小组件读取本地 App Group 快照。训练、用餐、睡眠提醒在获得通知权限后本地安排，可分别关闭。

### 保存期限与你的权利

本地记录保留至你修改、删除或卸载。我们的应用后端不将 AI 消息保存为聊天数据库，但服务商处理和保留数据的方式依其政策。反馈、统计按上述独立方式处理。Apple、Polar 按其政策及适用要求保存交易资料。需要访问、更正或删除由我们持有的信息，请联系支持；我们可能需要足够信息定位反馈，请勿发送密码或付款资料。

Masso 不面向 13 岁以下儿童。数据处理方式变化时会更新本页。健身、饮食及睡眠信息仅供一般参考，不构成医疗建议。
