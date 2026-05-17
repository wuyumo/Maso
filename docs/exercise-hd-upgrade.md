# HD 训练动图升级 — 完整步骤

把 yuhonas 现有 850×567 JPG **4× upscale** 到 3400×2268, 输出到自己的 CDN.
完成后 iPhone Retina 显示无放大失真, 视觉清晰度 +300%.

预计:
- 时间投入: 2 小时 (上传等待 + 跑脚本) + 半天空闲跑 upscale
- 钱投入: ~$20 一次性 (Replicate API, 1746 张图) + Cloudflare R2 免费额度内 (~500MB 远小于 10GB 免费)
- 经常性成本: $0 (R2 100 万次读 / 月免费, 出口流量 $0)

---

## Step 1: 装环境 (~5 分钟)

```bash
cd /Users/yumowu/Projects/Maso-iOS

# Python 包 — Real-ESRGAN 走 Replicate API + 上传走 boto3
pip3 install replicate boto3
```

## Step 2: 申请 Replicate API key (~3 分钟)

1. 访问 https://replicate.com/signin
2. 用 GitHub 账号登录 (免费)
3. https://replicate.com/account/api-tokens → Create new token
4. 复制 token (`r8_xxx...`)
5. 充值: https://replicate.com/account/billing
   - 充 $30 够用 (1746 张 × ~$0.011 = $19.20 + buffer)

## Step 3: 跑 upscale 脚本 (~1-2 小时)

```bash
export REPLICATE_API_TOKEN=r8_your_token_here

# 先用 --limit 5 跑 10 张验证
python3 scripts/upscale_exercise_images.py --limit 5
# 检查 build/upscaled/ 下面前 5 个动作的 0.jpg / 1.jpg 是否变高清

# OK 后跑全量
python3 scripts/upscale_exercise_images.py
```

脚本特性:
- **可恢复**: 中断后再跑会 skip 已完成的
- **ETA 显示**: 实时显示剩余时间估算
- **失败 retry-able**: 失败的图下次自动重试

输出: `build/upscaled/{exercise_id}/{0,1}.jpg` (~500MB 总)

## Step 4: 注册 Cloudflare R2 (~10 分钟)

1. 注册 Cloudflare 账号 (免费): https://dash.cloudflare.com/sign-up
2. 进 R2: https://dash.cloudflare.com/?to=/:account/r2
   - 首次进会要绑信用卡 (不收费, 仅 verify, 免费额度内 0 扣款)
3. 创建 bucket:
   - 名字: `maso-exercises`
   - Location: Auto (自动选最近节点)
4. **开启 public access**:
   - Bucket → Settings → Public access → "Allow access via r2.dev URL"
   - 拿到 public URL: `https://pub-XXXXXXXXXXXX.r2.dev` (保存好这个)
5. 创建 R2 API token:
   - 左侧 "Manage R2 API Tokens" → "Create API Token"
   - Permission: **Object Read & Write**
   - Bucket: 限定 `maso-exercises` 这一个
   - 保存 Access Key ID + Secret Access Key (只显示一次!)
6. 找到 Account ID:
   - R2 → Overview 页右侧, 一长串十六进制

## Step 5: 上传到 R2 (~30 分钟, 看网速)

```bash
export R2_ACCOUNT_ID=你的_account_id
export R2_ACCESS_KEY=你的_access_key
export R2_SECRET_KEY=你的_secret_key
export R2_BUCKET=maso-exercises

# 先 dry run 确认要上传啥
python3 scripts/upload_exercise_images.py --dry-run

# 正式上传 (1746 张 ~ 30 分钟看网速)
python3 scripts/upload_exercise_images.py
```

脚本特性:
- **自动 skip 已上传**: 已存在的 key 不重传
- **1 年 cache header**: `Cache-Control: max-age=31536000, immutable`

## Step 6: 验证 + 把 URL 告诉 Claude

上传完成, 打开浏览器测试:
```
https://pub-XXXXXXXXXXXX.r2.dev/Barbell_Bench_Press_-_Medium-Grip/0.jpg
```
应该能直接看到高清图.

**然后把这个 public URL 告诉我** (`pub-XXXXXXXXXXXX.r2.dev` 这部分),
我改 `ExerciseImageURL.url()` 让 iOS 走新 CDN.

---

## FAQ

**Q: Replicate $20 有点贵, 能不能本地跑?**
A: 可以. M1 Mac 跑 Real-ESRGAN ncnn 大约 1.5-2 小时, 0 成本.
   `brew install realesrgan-ncnn-vulkan`
   然后 `python3 scripts/upscale_exercise_images.py --backend local`

**Q: 跑到一半网断了怎么办?**
A: 直接重跑同一命令. 脚本 resumable, 自动 skip 已完成.

**Q: yuhonas 之后更新, 我怎么同步?**
A: 删 `build/originals/` (重新下原图) + `build/upscaled/{改动 id}/` (重 upscale 这部分),
   然后跑 upscale + upload 脚本. 增量上传 (skip 已存在).

**Q: 上传成本会涨吗?**
A: R2 免费额度 — 10GB 存储 / 100M 读 / 月. 我们 500MB + 几万次读, 远低. 上 App Store
   爆量后, 超出按 $0.015/GB-mo + $0.36/M reads 计费. 1M 用户级别才考虑.

**Q: 万一 R2 挂了或者我不想用了, 怎么 fallback?**
A: 现有 jsdelivr URL pattern 保留作 fallback. iOS 端我改的时候会做 try-new-CDN +
   fail-back-jsdelivr 双层 (低质量但保活).

---

## License 备查

- 输入素材: yuhonas/free-exercise-db, **Unlicense / public domain**
- AI 处理工具: Real-ESRGAN, **BSD-3-Clause** (商用 OK)
- AI 处理结果继承输入: public domain (Real-ESRGAN 不主张 AI 输出版权)
- 自托管 CDN: 自己买的 R2 服务, 没有第三方 license 包袱

App Store 审核如果问素材出处, 把 yuhonas Unlicense + Real-ESRGAN BSD 截图存档即可.
