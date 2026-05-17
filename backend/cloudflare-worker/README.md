# Maso AI Proxy — Cloudflare Worker

50 行 Cloudflare Worker,把 DeepSeek API key 从 iOS app binary 移到 server 端 — 满足 App Store 审核要求,顺便防 key 被反编译盗用。

## 部署

```bash
# 一次性
npm i -g wrangler
wrangler login

# 设置 secret (不会写进 git, 不会出现在 binary)
wrangler secret put DEEPSEEK_API_KEY     # 粘你的 DeepSeek API key
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

Cloudflare Worker 免费版:每天 100k 请求,单次 10ms CPU 时间 — Maso 用户量 10k 以内绰绰有余。超了可以加 $5/月 升级到 10M 请求。

DeepSeek API 实际成本走你自己的账户(被 Maso 用户量决定)。

## 如果想严格限制(Pro 用户才能用 AI)

当前的 `MASO_CLIENT_TOKEN` 只是轻量防滥用 — 任何人解 iOS binary 都能拿到 token。要严格区分 Pro / Free 用户:

1. iOS 端用 `StoreKit 2` 拿当前 user 的 `transaction.deviceVerification`
2. 跟 token 一起发给 worker
3. worker 调 Apple App Store Server API 验证用户买过 Pro

这部分需要 Apple Developer 账号 + 几天工作量,1.0 不一定要做,可以 1.1 加。
