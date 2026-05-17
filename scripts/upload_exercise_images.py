#!/usr/bin/env python3
"""把 build/upscaled/ 下的 1746 张 upscaled JPG 上传到 Cloudflare R2.

R2 兼容 S3 API, 用 boto3 即可. R2 免费额度:
- 10GB 存储 / 月 (我们 ~500MB)
- 100 万次读 / 月 (够中等规模 app)
- **0 出口流量费** ← 关键, AWS S3 出口贵, R2 是核心优势

Setup (一次性):
1. 注册 Cloudflare (免费): https://dash.cloudflare.com/sign-up
2. 进 R2: https://dash.cloudflare.com/?to=/:account/r2
3. 创建 bucket — 名字推荐 "maso-exercises"
4. Bucket → Settings → Public access → Allow access via r2.dev URL
   (拿到 public URL e.g. https://pub-xxxx.r2.dev)
5. R2 → Manage R2 API Tokens → Create API Token
   - Permission: Object Read & Write
   - 拿 Access Key ID + Secret Access Key

用法:
    export R2_ACCOUNT_ID=xxx           # 在 R2 Overview 页右侧
    export R2_ACCESS_KEY=xxx
    export R2_SECRET_KEY=xxx
    export R2_BUCKET=maso-exercises
    pip install boto3
    python3 scripts/upload_exercise_images.py

上传后, 每张图的 public URL:
    https://pub-xxxx.r2.dev/{exercise_id}/0.jpg

跟着把这个 base URL 告诉 Claude, 我改 iOS 端的 ExerciseImageURL.
"""
import argparse
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
UPSCALED_DIR = REPO_ROOT / "build/upscaled"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="只列出要上传的文件, 不实际上传")
    parser.add_argument("--force", action="store_true",
                        help="覆盖 R2 已存在的文件 (默认 skip)")
    args = parser.parse_args()

    # env 检查
    required = ["R2_ACCOUNT_ID", "R2_ACCESS_KEY", "R2_SECRET_KEY", "R2_BUCKET"]
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        print(f"ERROR: missing env vars: {missing}")
        print("       see script header for setup steps")
        sys.exit(1)

    try:
        import boto3
        from botocore.exceptions import ClientError
    except ImportError:
        print("ERROR: pip install boto3")
        sys.exit(1)

    if not UPSCALED_DIR.exists():
        print(f"ERROR: {UPSCALED_DIR} doesn't exist. Run upscale_exercise_images.py first.")
        sys.exit(1)

    account_id = os.environ["R2_ACCOUNT_ID"]
    bucket = os.environ["R2_BUCKET"]
    endpoint = f"https://{account_id}.r2.cloudflarestorage.com"

    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=os.environ["R2_ACCESS_KEY"],
        aws_secret_access_key=os.environ["R2_SECRET_KEY"],
        region_name="auto",
    )

    files = sorted(UPSCALED_DIR.rglob("*.jpg"))
    print(f"Found {len(files)} JPGs to upload to r2://{bucket}/")

    # 拿 R2 已有 keys (走 list_objects), 决定 skip 哪些
    existing: set[str] = set()
    if not args.force:
        print("Listing existing R2 keys (for skip)...")
        paginator = s3.get_paginator("list_objects_v2")
        try:
            for page in paginator.paginate(Bucket=bucket):
                for obj in page.get("Contents", []):
                    existing.add(obj["Key"])
            print(f"  → {len(existing)} keys already exist (will skip)")
        except ClientError as e:
            print(f"  ⚠️  list_objects failed (continuing): {e}")

    uploaded = 0
    skipped = 0
    failed = 0

    for f in files:
        # key = "{exercise_id}/{frame}.jpg" (relative to UPSCALED_DIR)
        key = str(f.relative_to(UPSCALED_DIR))
        if not args.force and key in existing:
            skipped += 1
            continue

        if args.dry_run:
            print(f"DRY: {key} ({f.stat().st_size // 1024} KB)")
            uploaded += 1
            continue

        try:
            s3.upload_file(
                str(f), bucket, key,
                ExtraArgs={
                    "ContentType": "image/jpeg",
                    "CacheControl": "public, max-age=31536000, immutable",  # 1 yr cache
                },
            )
            uploaded += 1
            if uploaded % 50 == 0:
                print(f"  [{uploaded}/{len(files) - skipped}] {key}")
        except Exception as e:
            print(f"  ✗ {key}: {e}")
            failed += 1

    print()
    print(f"Done. {uploaded} uploaded, {skipped} skipped, {failed} failed.")
    print()
    print("Public URL pattern (use this in iOS):")
    print(f"  https://pub-<your-r2-public-hash>.r2.dev/{{exercise_id}}/{{frame}}.jpg")
    print()
    print("To find your public URL: R2 dashboard → bucket → Settings → Public access")


if __name__ == "__main__":
    main()
