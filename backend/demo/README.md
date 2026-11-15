# Shared exercise demo generation

Status: App/API flow implemented; production generation is **disabled**. A real GPU renderer, credit pricing/grants, and approved visual/technique contract are still required. No paid generation has been run. The delivered batch contains 100 real H.264 clips (736 square); 83 passed initial variant screening and are published. 17 are withheld for mismatch/review. See docs/core100-delivery-2026-10-17. Initial screening is not frame-by-frame technique certification.

## Ownership

| App | Server | GPU / reviewer |
| --- | --- | --- |
| Exercise and Coach-plan entry points | Canonical exercise ID/version and recipes | Implement the actual image/video model workflow |
| Show server quote, available and reserved credits | D1 credit ledger and atomic reservations | Claim a leased job; heartbeat while rendering |
| Native explicit cost/sharing confirmation | One global job per exact exercise + style version | Upload a genuine square H.264/HEVC clip |
| Poll while visible; fetch again on reopen | Queue survives closing the App | Human checks technique, equipment, identity, crop and loop |
| Download bounded ranges, verify SHA-256, cache and play | R2 private quarantine + approved public library | Approval alone publishes and captures credits |
| Keep original images if video is absent or fails | Failure/rejection/expiry releases credits once | Rejected results never enter the public library |

## Scope and limits

- Only existing exact exercise IDs outside the core 100 are eligible. No invented exercises, user photos, training history, health records or chat text are accepted as generation input. Canonical English recipes come from the current live App library and require technique review.
- No automatic paid task when generating a plan. The Coach card opens the shared per-exercise flow. Ready or pending canonical assets are reused at zero additional cost.
- A new installation has **zero** credits. No local counter and no free grant from a client token. The app stores a random wallet bearer in ThisDeviceOnly Keychain; D1 stores its SHA-256. This is an installation wallet, not a cross-device account. Loss of the device/Keychain requires support; account authentication/recovery must precede commercial credit sales.
- Existing Pro/chat access is NOT an existing paid credit balance. This implementation does not invent a conversion or sell top-ups. Before selling credits, implement verified payment/receipt entitlement and account recovery; the admin grant endpoint is for authorized grants only.
- Reserves are held at job creation; approval captures; failure/rejection releases. D1 triggers execute these with the job mutation, and unique indexes handle concurrent duplicate submissions. Grants have unique server-controlled receipt/reference IDs.
- New endpoints use the existing shared client token as an abuse gate, not a billing identity. Keep GPU and review secrets separate and off the App. Strengthen with account auth/App Attest, rate limits and purchase validation before public commercial rollout. No admin routes are relayed by Vercel.
- GPU worker cannot self-approve. A separate reviewer bearer and all four explicit QA flags are required. Upload validation is only an MP4 signature/size check; it is NOT technique/video-content validation. Human review and renderer-side ffprobe checks are mandatory. Keep the service disabled until the six-image/pilot-video approval and reference delivery are finished.
- Queue waits expire after 24h, GPU leases after 15m (heartbeat extends), review after 72h. Fifteen-minute cron releases outstanding holds. Reopening refreshes shared job status. No push notification is implemented; the UI does not promise one.
- Opaque H.264/HEVC is sufficient for the selected fixed baked scene; alpha and scene/person selection are out of scope. Style changes require a new canonical version so old videos/charges are not mixed.

## Cloudflare configuration

Migration `0002_exercise_demos.sql` is additive in existing `FEEDBACK_DB`; no feedback schema changes. R2 was enabled by the account owner on 2026-10-17; the private masso-exercise-demos bucket is bound below.

The private bucket binding is:

```toml
[[r2_buckets]]
binding = "DEMO_BUCKET"
bucket_name = "masso-exercise-demos"
```

Configure server secrets with `wrangler secret put DEMO_GPU_TOKEN` and `wrangler secret put DEMO_REVIEW_TOKEN` (different random values, >=32 characters). Neither goes to Vercel or the App. Set `DEMO_CREDIT_COST` to a positive integer only after measuring actual renderer cost. Default switches:

```toml
DEMO_GENERATION_ENABLED = "false"
DEMO_STYLE_APPROVED = "false"
DEMO_GPU_READY = "false"
```

Turn all three to true only after real renderer acceptance, user style approval and credit provisioning. There is deliberately no fabricated default price. Main endpoint ai.replai.sh relays requests to canonical Worker D1/R2; both gateways must run latest shared source. Video responses are capped at 1MiB ranges for gateway limits.

## API

Prefix `/v1/exercise-demos`. Public App requests require `X-Maso-Client-Token`; wallet/quote/jobs also require installation `Authorization: Bearer <random token>`.

- `GET /config`: readiness and price.
- `POST /wallet`: idempotent zero-balance installation wallet.
- `GET /assets/:exerciseId`: ready metadata, shared task, core_pending, or missing.
- `POST /quote`: `{exerciseId}`; server price, style version, balance and shared task.
- `POST /jobs`: `{exerciseId, acceptedCost, version, shareConsent:true}`; refuses disabled service, core pending assets, unknown ID, insufficient funds or changed quote.
- `GET /jobs/:jobId`: sanitized state and current wallet (no sponsor information).
- `GET /video/:sha256`: only approved R2 object; validated bounded byte ranges.

Worker-only GPU bearer:
- `POST /internal/claim`: atomic oldest-job lease and server-authored recipe.
- `POST /internal/jobs/:id/heartbeat`, `/fail`, `/upload`: require `X-Demo-Claim` current lease token. Upload is video body, max25MiB. No arbitrary external URLs are fetched.

Worker-only reviewer bearer:
- `POST /internal/review`: `{jobId,approve:true,techniqueVerified:true,identityVerified:true,cropVerified:true,loopVerified:true}`. To reject use `{jobId,approve:false}`. Never approve just because a file exists.
- `POST /internal/import/:exerciseId`: owner-reviewed offline clip, raw video body plus `X-Demo-Reviewed: technique,identity,crop,loop`. Requires style approval and R2, but does not require an online GPU or credits. Never debits users; rejects active billable jobs to prevent a sponsorship race. Use owner-only `import_library.py` with a human-approved manifest, dry-run by default.
- `POST /internal/grant`: `{walletId,amount,reference}`. Idempotent reference. Only verified entitlement or an explicitly authorized support/testing grant should call it. No client grant endpoint.

## Friend's GPU adapter

`gpu_agent.py` uses Python standard library, subprocess and installed ffprobe. It is a queue adapter, **not a video generator**. Supply a trusted executable renderer that accepts `job.json output.mp4` and implements the approved source references and video model. Give the friend the GPU bearer, never reviewer bearer. Keep it in environment, not CLI/history. Run:

```sh
python3 gpu_agent.py --base https://maso-ai.wuyumo.workers.dev --renderer /absolute/path/to/your-renderer --once
```

The current static pilot package is at `design/muscle-3d-demo/fitness-assets/handoff/core100/`. It still contains known crop/pose review issues. Its batch gate remains false; no actual renderer is supplied or verified in this change.

## Validation

`node --test backend/demo/service.test.mjs backend/shared/handler.test.mjs` uses real in-memory SQLite tables/triggers via a D1 adapter, not mocked ledger logic. It covers duplicate requests, holds/capture/release, fixed recipes/costs, role-separated auth, failed/expired leases, quarantine, approval and approved byte-range retrieval. Synthetic bytes test storage protocol only, never motion accuracy or real playable video. Native and production readiness checks are recorded separately.

The current canonical style version is single-model07-env03-v2: MODEL-07-photo-v1, the new black-haired mixed-heritage fictional man, with ENV-03. It supersedes the old Asian pilot identity; do not mix their references, recipes or review decisions.
