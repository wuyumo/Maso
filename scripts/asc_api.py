#!/usr/bin/env python3
"""App Store Connect API 最小客户端 —— 只依赖标准库 + openssl(走 cryptography 不可用时的兜底).

为什么自己搓 JWT: 这台机器没有 PyJWT, 而发版链路不该为了一个 token 去装依赖。
ES256 签名用 `openssl dgst -sha256 -sign`, 再把 DER 签名转成 JOSE 的 r||s 拼接格式。
"""
import base64, json, subprocess, time, sys, urllib.request, os

KEY_ID = "SB3695GPYD"
ISSUER = "29f7fc6b-0be6-4a52-b8e2-0a5ddffa2823"
KEY_PATH = os.path.join(os.path.dirname(__file__), "..", ".keys", f"AuthKey_{KEY_ID}.p8")

def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")

def der_to_jose(der: bytes) -> bytes:
    """DER ECDSA 签名 → JOSE r||s (各 32 字节). ASC 只认后者。"""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 3
    def take(idx):
        assert der[idx] == 0x02
        ln = der[idx + 1]
        v = der[idx + 2: idx + 2 + ln].lstrip(b"\x00")
        return v.rjust(32, b"\x00"), idx + 2 + ln
    r, i = take(i)
    s, _ = take(i)
    return r + s

def token() -> str:
    hdr = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time())
    pay = {"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64u(json.dumps(hdr).encode())}.{b64u(json.dumps(pay).encode())}"
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
                         input=signing_input.encode(), capture_output=True, check=True).stdout
    return f"{signing_input}.{b64u(der_to_jose(der))}"

def call(path, method="GET", body=None):
    url = path if path.startswith("http") else f"https://api.appstoreconnect.apple.com/v1/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:600]
        raise SystemExit(f"HTTP {e.code} on {method} {url}\n{detail}")

if __name__ == "__main__":
    print(json.dumps(call(sys.argv[1] if len(sys.argv) > 1 else "apps"), indent=1, ensure_ascii=False)[:1500])
