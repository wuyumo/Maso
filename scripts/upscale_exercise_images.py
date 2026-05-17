#!/usr/bin/env python3
"""把 yuhonas/free-exercise-db 873 个动作 × 2 帧 = 1746 张 850×567 JPG
用 Real-ESRGAN 4× 升级到 3400×2268, 输出到 build/upscaled/.

三种 backend (通过 --backend 参数切换):

1. pytorch (推荐 Mac M1/M2) — 本地 PyTorch + MPS GPU
   - 0 成本 (第一次下载 ~64MB model 权重)
   - M1 Pro ~1-2s/image → 1746 张 ~30-60min
   - 装: 见 build/venv (脚本会自动检测)
     source build/venv/bin/activate
     pip install torch torchvision realesrgan basicsr

2. replicate — 云端 Replicate API
   - 不需要本地 GPU
   - 1746 张 × ~$0.011 = ~$20 一次性
   - 申请: https://replicate.com/account/api-tokens
   - 装: pip install replicate

3. local — 用本地 Real-ESRGAN ncnn-vulkan CLI
   - 需要单独下载 binary + model files (v0.2.0 release 没 bundle model)
   - 不推荐, 走 pytorch backend 更简单

用法:
    export REPLICATE_API_TOKEN=r8_xxx
    python3 scripts/upscale_exercise_images.py --backend replicate
    # 中断后再跑会 skip 已完成的, 安全可恢复

输出: build/upscaled/{exercise_id}/{0,1}.jpg (~300KB 每张, 总 ~500MB)
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Optional
from urllib.request import urlretrieve
import urllib.request
import urllib.error

REPO_ROOT = Path(__file__).resolve().parent.parent
JSON_PATH = REPO_ROOT / "Maso/Resources/exercises.json"
OUT_DIR = REPO_ROOT / "build/upscaled"
TMP_DIR = REPO_ROOT / "build/originals"

YUHONAS_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises"

# Real-ESRGAN model — general 4× photo upscaler (vs anime variant).
# 这个 model 对真人健身照片最合适.
REPLICATE_MODEL = "nightmareai/real-esrgan:f121d640bd286e1fdc67f9799164c1d5be36ff74576ee11c803ae5b665dd46aa"


def download_original(exercise_id: str, frame: int) -> Optional[Path]:
    """从 GitHub raw 下载原图到 TMP_DIR. 已存在直接返回路径."""
    local = TMP_DIR / exercise_id / f"{frame}.jpg"
    if local.exists():
        return local
    local.parent.mkdir(parents=True, exist_ok=True)
    # yuhonas URL 用 percent-encoded folder name (包含 +, %, () 等字符的动作)
    from urllib.parse import quote
    safe_id = quote(exercise_id, safe="")
    url = f"{YUHONAS_BASE}/{safe_id}/{frame}.jpg"
    try:
        urlretrieve(url, local)
        return local
    except urllib.error.HTTPError as e:
        print(f"  ✗ Failed to download {exercise_id}/{frame}.jpg: HTTP {e.code}")
        return None


def upscale_pytorch(local_jpg: Path, out_jpg: Path, upsampler) -> bool:
    """用本地 PyTorch RealESRGANer 把 local_jpg upscale 4× 输出到 out_jpg.
    upsampler 在 main() 里只初始化一次 (model 加载 ~3s, 复用避免每张图重复)."""
    try:
        import cv2
        img = cv2.imread(str(local_jpg), cv2.IMREAD_COLOR)
        if img is None:
            return False
        output, _ = upsampler.enhance(img, outscale=4)
        # 保存为 JPG quality 92 (跟 yuhonas 原 JPG 一致)
        cv2.imwrite(str(out_jpg), output, [cv2.IMWRITE_JPEG_QUALITY, 92])
        return True
    except Exception as e:
        print(f"  ✗ PyTorch upscale failed for {local_jpg}: {e}")
        return False


def init_pytorch_upsampler():
    """初始化 PyTorch RealESRGAN — Mac M1/M2 用 MPS, 其它用 CPU.
    第一次跑会从 GitHub 下载 ~64MB 的 model 权重到 ~/.cache."""
    # basicsr 1.4.2 引用了已经移除的 torchvision.transforms.functional_tensor.
    # 新 torchvision (0.16+) 把这个 module merge 到 functional.
    # 在 import basicsr 前 monkey-patch 兼容回去.
    import torchvision.transforms.functional as _tvf
    import torchvision.transforms as _tv
    if not hasattr(_tv, "functional_tensor"):
        _tv.functional_tensor = _tvf
    import sys as _sys
    _sys.modules.setdefault("torchvision.transforms.functional_tensor", _tvf)

    import torch
    from basicsr.archs.rrdbnet_arch import RRDBNet
    from realesrgan import RealESRGANer

    # 选 device — M1/M2 MPS > CUDA > CPU
    if torch.backends.mps.is_available():
        device = torch.device("mps")
        print("Using MPS (Apple Silicon GPU)")
    elif torch.cuda.is_available():
        device = torch.device("cuda")
        print("Using CUDA GPU")
    else:
        device = torch.device("cpu")
        print("⚠️  Using CPU (slow). 1746 张可能要几小时.")

    model = RRDBNet(
        num_in_ch=3, num_out_ch=3, num_feat=64,
        num_block=23, num_grow_ch=32, scale=4,
    )
    upsampler = RealESRGANer(
        scale=4,
        model_path="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth",
        model=model,
        tile=0,
        tile_pad=10,
        pre_pad=0,
        half=False,  # MPS 不支持 fp16; CUDA 可以打开但 RealESRGAN 默认 false
        device=device,
    )
    return upsampler


def upscale_replicate(local_jpg: Path, out_jpg: Path) -> bool:
    """用 Replicate API 把 local_jpg upscale 4× 输出到 out_jpg."""
    import replicate
    try:
        with open(local_jpg, "rb") as f:
            output_url = replicate.run(
                REPLICATE_MODEL,
                input={"image": f, "scale": 4, "face_enhance": False},
            )
        # output_url 可能是 str 或 FileOutput object
        url_str = str(output_url) if not isinstance(output_url, str) else output_url
        urlretrieve(url_str, out_jpg)
        return True
    except Exception as e:
        print(f"  ✗ Replicate failed for {local_jpg}: {e}")
        return False


def upscale_local(local_jpg: Path, out_jpg: Path) -> bool:
    """用本地 realesrgan-ncnn-vulkan CLI upscale 4×."""
    import subprocess
    try:
        result = subprocess.run(
            [
                "realesrgan-ncnn-vulkan",
                "-i", str(local_jpg),
                "-o", str(out_jpg),
                "-n", "realesrgan-x4plus",
                "-s", "4",
                "-f", "jpg",
            ],
            capture_output=True, text=True, timeout=120,
        )
        return result.returncode == 0
    except Exception as e:
        print(f"  ✗ Local upscale failed for {local_jpg}: {e}")
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--backend", choices=["pytorch", "replicate", "local"], default="pytorch",
        help="upscale backend (default: pytorch — 本地 MPS/CUDA/CPU)",
    )
    parser.add_argument(
        "--limit", type=int, default=None,
        help="只处理前 N 个动作 (dev 测试用; 不指定 = 全部 873)",
    )
    parser.add_argument(
        "--skip-download", action="store_true",
        help="只 upscale 已下载到 build/originals 的图 (不重新拉)",
    )
    args = parser.parse_args()

    # 读 exercise list
    with open(JSON_PATH) as f:
        exercises = json.load(f)
    if args.limit:
        exercises = exercises[: args.limit]
    print(f"Processing {len(exercises)} exercises × 2 frames = {len(exercises) * 2} images")
    print(f"Backend: {args.backend}")
    print(f"Output: {OUT_DIR}")
    print()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)

    # backend 初始化
    pytorch_upsampler = None
    if args.backend == "pytorch":
        try:
            pytorch_upsampler = init_pytorch_upsampler()
        except ImportError as e:
            print(f"ERROR: {e}")
            print("       source build/venv/bin/activate  # 或安装到全局")
            print("       pip install torch torchvision realesrgan basicsr")
            sys.exit(1)
    elif args.backend == "replicate":
        if not os.environ.get("REPLICATE_API_TOKEN"):
            print("ERROR: set REPLICATE_API_TOKEN env var first.")
            print("       https://replicate.com/account/api-tokens")
            sys.exit(1)
        try:
            import replicate  # noqa: F401
        except ImportError:
            print("ERROR: pip install replicate")
            sys.exit(1)

    total = len(exercises) * 2
    done = 0
    skipped = 0
    failed = 0
    start = time.time()

    for ex in exercises:
        ex_id = ex["id"]
        out_dir = OUT_DIR / ex_id
        out_dir.mkdir(parents=True, exist_ok=True)
        for frame in [0, 1]:
            out_path = out_dir / f"{frame}.jpg"
            # 已 upscale 过, 跳过 (resumable)
            if out_path.exists() and out_path.stat().st_size > 10_000:
                skipped += 1
                done += 1
                continue

            # 下载原图
            if args.skip_download:
                local = TMP_DIR / ex_id / f"{frame}.jpg"
                if not local.exists():
                    print(f"  ✗ {ex_id}/{frame}.jpg: no local original (run without --skip-download)")
                    failed += 1
                    done += 1
                    continue
            else:
                local = download_original(ex_id, frame)
                if local is None:
                    failed += 1
                    done += 1
                    continue

            # Upscale
            if args.backend == "pytorch":
                ok = upscale_pytorch(local, out_path, pytorch_upsampler)
            elif args.backend == "replicate":
                ok = upscale_replicate(local, out_path)
            else:
                ok = upscale_local(local, out_path)
            done += 1
            if not ok:
                failed += 1
                continue

            # 进度 + ETA
            elapsed = time.time() - start
            rate = (done - skipped) / max(elapsed, 1)
            remaining = total - done
            eta_min = remaining / max(rate, 0.01) / 60
            print(f"[{done:4d}/{total}] {ex_id}/{frame}.jpg "
                  f"(ETA {eta_min:.0f}m, failed {failed})")

    print()
    print(f"Done. {done - failed - skipped} upscaled, {skipped} already existed, {failed} failed.")
    print(f"Output: {OUT_DIR}")
    print(f"Total size: {sum(p.stat().st_size for p in OUT_DIR.rglob('*.jpg')) / 1024 / 1024:.0f} MB")


if __name__ == "__main__":
    main()
