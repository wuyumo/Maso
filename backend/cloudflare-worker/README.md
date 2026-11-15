# Masso AI Proxy — Cloudflare Worker

## Weekly bug reports

`POST /feedback` stores user-submitted reports in the `maso-feedback` D1 database. The Worker sends up to 100 pending reports to the configured FormSubmit email endpoint every Monday at 09:00 China Standard Time (`0 1 * * 1` UTC). Rows are deleted only after FormSubmit explicitly accepts the digest; failed sends stay queued for the next run.

The app sends only the report text, report UUID, app version, iOS version, and language. It does not attach account or device identifiers. Schema: `migrations/0001_bug_reports.sql`.

模型凭证仅保存在服务端，不打包进 iOS App。

## 2026-11-05 素材目录增量上线

当前主入口从生产 Git 版本 `923e875` 隔离增加审核目录及素材只读转发，备用 Worker 仅增加审核目录读取。具体基线、验证、回滚标识和自动同步范围见 `docs/remote-exercise-catalog-2026-11-05/README.md`；下方 10 月记录为历史基线。

## 当前生产核对（2026-10-26）

- 主入口 `ai.replai.sh` 是 Vercel **maso**（Root Directory `backend`）。实际生产代码基线为 GitHub `c43b006dfb99485dd3bdbcbeffc76e7eabd31759`，仍走 `claude-haiku-5-5` / `claude-sonnet-5`；本次没有切换模型或复制凭证。已配置百炼 secret 不代表这个旧部署使用了百炼。
- 本地 shared handler 支持百炼北京 `qwen3.7-flash` / `qwen3.5-plus`（配置 DASHSCOPE_API_KEY 时），但不能把本地代码当作当前线上路由的证据。旧“两个生产入口均为 Flash”记录已失效。
- 训练计划新增 `routine_contract` v1：从同一次器械筛选得到的 ID / programming group / 数量快照构建；服务端对未知 ID、重复组和数量错误触发已有强模型兜底。旧客户端没有此字段时保留兼容。客户端仍最终校验，连续无效时保留模板，不猜测替换动作。
- 此次主入口只在上述线上基线加入合同校验，未发布工作区里其他 Worker / demo 改动。完整证据见 `docs/ai-routine-contract-2026-10-26`。后续不要用未审查的工作区覆盖这份生产补丁。
- 备用 `maso-ai.wuyumo.workers.dev` 本机 Python 请求收到 Cloudflare1010/403；这不是上游余额或用户手机同样失败的证明。
- 服务端仅记录模型及固定失败分类；不记录用户画像、对话、完整返回或照片。

## 部署

```bash
# 一次性
npm i -g wrangler
wrangler login

# 设置 secret (不会写进 git, 不会出现在 binary)
wrangler secret put DASHSCOPE_API_KEY    # 百炼北京 API key
wrangler secret put MASO_CLIENT_TOKEN    # 任意 32 字符随机串

# 部署
wrangler deploy
```

部署完会拿到一个 URL,大致是:
```
https://maso-ai.<your-username>.workers.dev
```

## iOS 端改造

把 `Maso/Data/AIWorkoutService.swift` 里的:

```swift
// 之前:
let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
```

改成:

```swift
// 现在:
let url = URL(string: "https://maso-ai.<your-username>.workers.dev/v1/chat/completions")!
request.setValue(MASO_CLIENT_TOKEN, forHTTPHeaderField: "X-Maso-Client-Token")
// 不再传 Authorization header — worker 端会加
```

把 `Maso/Secrets.xcconfig` 里的 `DEEPSEEK_API_KEY` 删了,新增:
```
MASO_CLIENT_TOKEN = <跟 wrangler secret 同一个值>
MASO_AI_PROXY_URL = https://maso-ai.<your-username>.workers.dev
```

然后在 `Info.plist`(`project.yml` 里)用 `$(MASO_CLIENT_TOKEN)` 暴露给 app。

## 工作原理

```
iOS app
  │ POST /v1/chat/completions
  │ X-Maso-Client-Token: <baked-in token>
  │ Body: { model, messages, ... }
  ▼
Cloudflare Worker (free tier)
  ├─ 校验 token (轻量 abuse 拦截)
  ├─ 限制 body 大小 (50KB), model 白名单, max_tokens (4000)
  ├─ 加 DeepSeek API key
  ▼
DeepSeek API
  └─ 返回 OpenAI 兼容 JSON
```

## 隐私

Worker 不写日志、不存数据。请求过完即丢。跟 Privacy Policy 里写的一致。

## 成本

Cloudflare Worker 免费版:每天 100k 请求,单次 10ms CPU 时间 — Masso 用户量 10k 以内绰绰有余。超了可以加 $5/月 升级到 10M 请求。

DeepSeek API 实际成本走你自己的账户(被 Masso 用户量决定)。

## 如果想严格限制(Pro 用户才能用 AI)

当前的 `MASO_CLIENT_TOKEN` 只是轻量防滥用 — 任何人解 iOS binary 都能拿到 token。要严格区分 Pro / Free 用户:

1. iOS 端用 `StoreKit 2` 拿当前 user 的 `transaction.deviceVerification`
2. 跟 token 一起发给 worker
3. worker 调 Apple App Store Server API 验证用户买过 Pro

这部分需要 Apple Developer 账号 + 几天工作量,1.0 不一定要做,可以 1.1 加。
