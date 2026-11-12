# Masso local builds on a 16 GB Mac

Run these commands from the repository root. Default simulator builds target only
arm64 on this Apple silicon Mac, avoiding duplicate x86_64 compilation. Python 3 uses only the standard
library. No global Xcode settings or launchd jobs are changed.

```sh
# Incremental compilation; no simulator boot
python3 scripts/low_memory_build.py build
python3 scripts/low_memory_build.py --jobs 1 build

# Project generation, runtime data checks, compilation; no UI claim
bash .claude/skills/verify-app/driver.sh

# Explicit screenshot smoke checks
bash .claude/skills/verify-app/driver.sh --ui "iPhone 17 Pro"

# Focused XCTest UI verification: compile first, boot if needed, then test serially
python3 scripts/low_memory_build.py ui-test \
  --simulator <UDID> --scheme MasoExerciseUI \
  --only-testing MasoUITests/YourTestClass/yourTest

# Preserve an existing invocation, including archive/signing options
python3 scripts/low_memory_build.py xcodebuild -- <xcodebuild arguments>
# Raw test invocations require explicit opt-in
python3 scripts/low_memory_build.py xcodebuild --ui -- <test arguments>

# Hold the lock through a whole workflow (nested managed commands reuse it)
python3 scripts/low_memory_build.py --jobs 1 run -- bash your-workflow.sh

# Retry cleanup only for devices this tool previously booted
python3 scripts/low_memory_build.py cleanup-owned
```

The shared per-user advisory lock lives in the macOS user cache directory (`~/Library/Caches/MasoBuild`), outside
the checkout, so different chats and worktrees serialize. Existing install,
nightly, verification and screenshot scripts acquire it for their entire run.
Default timeout is one hour; `--wait-seconds 0` exits immediately with status 75
if busy. The lock is released by the OS when its last owning process exits; the
lock file is deliberately never deleted. Nested calls inherit the lock and job
limit. A new workflow also waits for existing `xcodebuild` and UI test runner
processes, including work started before this tool was added. It never kills them.

The lock is cooperative: direct `xcodebuild`, Xcode GUI builds, and scripts in other
projects that do not adopt this wrapper cannot be prevented from starting later.
Do not launch those concurrently. `-jobs` limits build operations; it is not a
strict memory limit for every compiler subprocess. This reduces peaks but does not
guarantee the machine cannot run out of memory.

Use `ui-test` for managed XCTest lifecycle. The raw `xcodebuild --ui` form preserves
the caller's simulator lifecycle; it does not assume ownership of devices Xcode
boots. For a custom simulator script, hold `run` and call
`python3 scripts/low_memory_build.py sim-prepare <UDID>` before using the device.
It rejects additional running simulators, waits for boot completion, and records
ownership only when it booted a shutdown device. The outer workflow shuts down
owned devices on success, failure, or handled cancellation. Pre-existing devices
are preserved. If another build/test has started, cleanup is deferred; no blanket
`shutdown all` is used. A hard kill can leave an owned-device lease for an explicit
`cleanup-owned` retry. This never erases simulator data or removes runtimes.

Nightly checks default to project/data/compile validation and then best-effort
iPhone installation, in sequence. Set `MASO_NIGHTLY_UI=1` for an intentional UI
smoke run. Reports distinguish whether UI checks ran. There is no new App release,
upload or launchd configuration. Keep incremental caches; do not routinely clean
DerivedData. Build tooling changes alone do not require rebuilding/installing the App.

Tooling tests (no real compilation, test cancellation, or simulator shutdown):

```sh
python3 -m unittest discover -s scripts/tests -p 'test_low_memory_build.py' -v
```
