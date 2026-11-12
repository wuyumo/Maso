#!/usr/bin/env python3
"""Serialized, low-memory local Xcode workflows. Python standard library only."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
# One lock per login user, shared by worktrees and scripts using this entry point.
STATE = Path.home() / "Library" / "Caches" / "MasoBuild"
LOCK_ENV = "MASO_BUILD_LOCK_FD"


def note(message):
    print(f"[low-memory] {message}", file=sys.stderr, flush=True)


def processes():
    output = subprocess.check_output(["ps", "-axo", "pid=,ppid=,comm="], text=True)
    rows = []
    for line in output.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3:
            rows.append((int(parts[0]), int(parts[1]), parts[2]))
    return rows


def busy_pids():
    # Also wait for builds started before adoption of the lock. Do not kill them.
    return [pid for pid, _, cmd in processes()
            if Path(cmd).name == "xcodebuild" or "UITests-Runner.app/" in cmd]


def wait_until_idle(timeout):
    deadline = time.monotonic() + timeout
    announced = False
    while True:
        busy = busy_pids()
        if not busy:
            return
        if not announced:
            note(f"Waiting for existing build/test processes {busy}; leaving them running.")
            announced = True
        if time.monotonic() >= deadline:
            raise RuntimeError("Existing build/test still active; retry later (nothing was stopped).")
        time.sleep(2)


@contextlib.contextmanager
def build_lock(timeout):
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = STATE / "build.lock"
    inherited = os.environ.get(LOCK_ENV)
    valid = False
    if inherited:
        try:
            fd = int(inherited)
            stat = os.fstat(fd)
            expected = path.stat()
            if (stat.st_dev, stat.st_ino) == (expected.st_dev, expected.st_ino):
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                valid = True
        except (OSError, ValueError):
            pass
    if valid:
        yield fd, False
        return
    with path.open("a+") as handle:
        deadline = time.monotonic() + timeout
        announced = False
        while True:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if not announced:
                    note("Another managed workflow owns the build lock; waiting.")
                    announced = True
                if time.monotonic() >= deadline:
                    raise RuntimeError("Timed out waiting for shared build lock.")
                time.sleep(1)
        os.environ[LOCK_ENV] = str(handle.fileno())
        os.environ["MASO_BUILD_SESSION"] = uuid.uuid4().hex
        try:
            yield handle.fileno(), True
        finally:
            os.environ.pop(LOCK_ENV, None)
            os.environ.pop("MASO_BUILD_SESSION", None)
            # Do not unlink: a stable inode prevents split locks between waiters.


def run(command, fd):
    child = subprocess.Popen(command, cwd=ROOT, pass_fds=(fd,), start_new_session=True)
    old_handlers = {}

    def forward(signum, _frame):
        # Cancel only our own child; never signal unrelated builds.
        if child.poll() is None:
            os.killpg(child.pid, signum)

    for sig in (signal.SIGINT, signal.SIGTERM):
        old_handlers[sig] = signal.signal(sig, forward)
    try:
        result = child.wait()
        return result if result >= 0 else 128 - result
    finally:
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)


def limited_args(args, jobs, allow_ui=False):
    if not allow_ui and any(x in args for x in ("test", "test-without-building")):
        raise RuntimeError("Tests require explicit --ui consent or the ui-test command.")
    # Enforce the cap even if a caller supplies conflicting flags later.
    paired = {"-jobs", "-parallel-testing-enabled", "-parallel-testing-worker-count",
              "-maximum-concurrent-test-simulator-destinations",
              "-maximum-concurrent-test-device-destinations"}
    result = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in paired:
            if index + 1 >= len(args):
                raise RuntimeError(f"Missing value for {arg}")
            index += 2
            continue
        if arg == "-parallelizeTargets" or arg.startswith("SWIFT_MAXIMUM_CONCURRENT_COMPILE_TASKS="):
            index += 1
            continue
        result.append(arg)
        index += 1
    result += ["-jobs", str(jobs)]
    if allow_ui:
        result += ["-parallel-testing-enabled", "NO", "-parallel-testing-worker-count", "1",
                   "-maximum-concurrent-test-simulator-destinations", "1",
                   "-maximum-concurrent-test-device-destinations", "1"]
    return result


def xcode(args, fd, jobs, allow_ui=False):
    wait_until_idle(0)  # The outer workflow already waited; detect late unmanaged work.
    return run(["/usr/bin/xcodebuild", *limited_args(args, jobs, allow_ui)], fd)


def devices():
    data = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
    return [d for group in json.loads(data)["devices"].values() for d in group]


def sim_prepare(udid):
    wait_until_idle(0)
    entries = devices()
    selected = next((d for d in entries if d["udid"] == udid), None)
    if not selected:
        raise RuntimeError(f"Simulator not available: {udid}")
    others = [d["udid"] for d in entries if d["state"] != "Shutdown" and d["udid"] != udid]
    if others:
        raise RuntimeError(f"Other simulators are running: {others}. Close unused devices explicitly first.")
    if selected["state"] == "Shutdown":
        # Record ownership before boot so failure/cancellation can still be cleaned up.
        lease = STATE / f"sim-{os.environ['MASO_BUILD_SESSION']}.json"
        lease.write_text(json.dumps({"udid": udid}))
        subprocess.check_call(["xcrun", "simctl", "boot", udid])
    subprocess.check_call(["xcrun", "simctl", "bootstatus", udid, "-b"])


def cleanup_owned(lease):
    if not lease.exists():
        return
    udid = json.loads(lease.read_text())["udid"]
    if busy_pids():
        note(f"Preserving simulator {udid}: a build/test is active. Lease retained for cleanup.")
        return
    result = subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True, text=True)
    if result.returncode == 0 or any(d["udid"] == udid and d["state"] == "Shutdown" for d in devices()):
        lease.unlink(missing_ok=True)
        note(f"Shut down workflow-owned simulator {udid}.")
    else:
        note(f"Could not shut down {udid}; lease retained: {result.stderr.strip()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, choices=(1, 2), default=int(os.environ.get("MASO_BUILD_JOBS", "2")))
    parser.add_argument("--wait-seconds", type=int, default=3600)
    sub = parser.add_subparsers(dest="mode", required=True)
    sub.add_parser("build", help="Incremental simulator build; does not boot a device")
    command = sub.add_parser("run", help="Hold lock for an entire script, including simulator use")
    command.add_argument("args", nargs=argparse.REMAINDER)
    raw = sub.add_parser("xcodebuild", help="Guard an existing xcodebuild invocation")
    raw.add_argument("--ui", action="store_true", help="Explicitly permit tests")
    raw.add_argument("args", nargs=argparse.REMAINDER)
    ui = sub.add_parser("ui-test", help="Explicit, serial UI tests; clean up only devices we boot")
    ui.add_argument("--simulator", required=True)
    ui.add_argument("--scheme", default="Maso")
    ui.add_argument("--only-testing", default="MasoUITests")
    prepare = sub.add_parser("sim-prepare", help="Use only within a managed run workflow")
    prepare.add_argument("udid")
    sub.add_parser("sim-release", help="Release this inherited workflow's owned device only")
    sub.add_parser("cleanup-owned", help="Retry cleanup of devices previously booted by this tool")
    ns = parser.parse_args()
    os.environ["MASO_BUILD_JOBS"] = str(ns.jobs)
    if ns.mode in ("sim-prepare", "sim-release"):
        if not os.environ.get(LOCK_ENV):
            raise RuntimeError("sim-prepare requires a managed run workflow")
        with build_lock(0) as (_, owner):
            if owner:
                raise RuntimeError("No valid inherited build lock; run via the managed workflow")
            if ns.mode == "sim-prepare":
                sim_prepare(ns.udid)
            else:
                cleanup_owned(STATE / f"sim-{os.environ['MASO_BUILD_SESSION']}.json")
        return 0
    with build_lock(ns.wait_seconds) as (fd, owner):
        wait_until_idle(ns.wait_seconds)
        if ns.mode == "cleanup-owned":
            for lease in STATE.glob("sim-*.json"):
                cleanup_owned(lease)
            return 0
        try:
            if ns.mode == "run":
                args = ns.args[1:] if ns.args[:1] == ["--"] else ns.args
                if not args:
                    raise RuntimeError("run requires a command after --")
                return run(args, fd)
            if ns.mode == "xcodebuild":
                args = ns.args[1:] if ns.args[:1] == ["--"] else ns.args
                return xcode(args, fd, ns.jobs, ns.ui)
            common = ["-project", "Maso.xcodeproj", "-scheme", "Maso", "-configuration", "Debug"]
            if ns.mode == "build":
                return xcode(common + ["-destination", "generic/platform=iOS Simulator",
                             "-derivedDataPath", "build/DerivedData", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "build"], fd, ns.jobs)
            common = ["-project", "Maso.xcodeproj", "-scheme", ns.scheme, "-configuration", "Debug",
                      "-destination", f"platform=iOS Simulator,id={ns.simulator}",
                      "-derivedDataPath", "build/DerivedData", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES",
                      f"-only-testing:{ns.only_testing}"]
            result = xcode(common + ["build-for-testing"], fd, ns.jobs, True)
            if result:
                return result
            sim_prepare(ns.simulator)
            return xcode(common + ["test-without-building"], fd, ns.jobs, True)
        finally:
            if owner:
                cleanup_owned(STATE / f"sim-{os.environ['MASO_BUILD_SESSION']}.json")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        note(str(exc))
        sys.exit(75)
    except KeyboardInterrupt:
        sys.exit(130)
