"""Safety checks for the build coordinator, without touching running Xcode work."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "low_memory_build.py"
spec = importlib.util.spec_from_file_location("low_memory_build", SOURCE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class BuildCoordinatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.state = Path(self.temp.name)
        self.patch = patch.object(m, "STATE", self.state)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.env = patch.dict(os.environ, {}, clear=False)
        self.env.start()
        self.addCleanup(self.env.stop)
        os.environ.pop(m.LOCK_ENV, None)
        os.environ["MASO_BUILD_SESSION"] = "test"

    def test_job_cap_and_serial_tests_override_caller(self):
        args = m.limited_args(["test", "-jobs", "16", "-parallelizeTargets",
                               "-parallel-testing-enabled", "YES", "-scheme", "Example"], 1, True)
        self.assertEqual(args[args.index("-jobs") + 1], "1")
        self.assertEqual(args[args.index("-parallel-testing-enabled") + 1], "NO")
        self.assertEqual(args.count("-jobs"), 1)
        self.assertNotIn("-parallelizeTargets", args)
        self.assertIn("Example", args)

    def test_tests_require_explicit_opt_in(self):
        for action in ("test", "test-without-building"):
            with self.assertRaises(RuntimeError):
                m.limited_args([action], 2)

    def test_existing_build_is_not_stopped(self):
        with patch.object(m, "busy_pids", return_value=[123]), patch.object(m.subprocess, "Popen") as launch:
            with self.assertRaises(RuntimeError):
                m.wait_until_idle(0)
            launch.assert_not_called()

    def test_lock_excludes_another_process_and_supports_inheritance(self):
        code = ("import importlib.util, pathlib, sys; "
                f"s=importlib.util.spec_from_file_location('b',{str(SOURCE)!r}); "
                "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
                f"m.STATE=pathlib.Path({str(self.state)!r}); "
                "ctx=m.build_lock(0); fd,owner=ctx.__enter__(); "
                "print('owner='+str(owner)); ctx.__exit__(None,None,None)")
        with m.build_lock(0) as (fd, owner):
            self.assertTrue(owner)
            isolated = dict(os.environ)
            isolated.pop(m.LOCK_ENV, None)
            blocked = subprocess.run([sys.executable, "-c", code], env=isolated, capture_output=True, text=True)
            self.assertNotEqual(blocked.returncode, 0)
            nested = subprocess.run([sys.executable, "-c", code], pass_fds=(fd,), capture_output=True, text=True)
            self.assertEqual(nested.returncode, 0, nested.stderr)
            self.assertIn("owner=False", nested.stdout)
        with m.build_lock(0) as (_, owner):
            self.assertTrue(owner)

    def test_lock_released_after_body_failure(self):
        with self.assertRaises(OSError):
            with m.build_lock(0):
                raise OSError("failure")
        with m.build_lock(0) as (_, owner):
            self.assertTrue(owner)

    def test_preexisting_simulator_is_not_owned(self):
        with patch.object(m, "wait_until_idle"), patch.object(m, "devices", return_value=[
            {"udid": "existing", "state": "Booted"}
        ]), patch.object(m.subprocess, "check_call") as call:
            m.sim_prepare("existing")
            self.assertEqual(list(self.state.glob("sim-*.json")), [])
            self.assertEqual(call.call_count, 1)  # bootstatus only

    def test_additional_running_simulator_is_preserved(self):
        with patch.object(m, "wait_until_idle"), patch.object(m, "devices", return_value=[
            {"udid": "new", "state": "Shutdown"}, {"udid": "existing", "state": "Booted"}
        ]), patch.object(m.subprocess, "check_call") as call:
            with self.assertRaises(RuntimeError):
                m.sim_prepare("new")
            call.assert_not_called()

    def test_owned_simulator_is_recorded_before_boot(self):
        os.environ[m.LOCK_ENV] = "9"
        def boot(*args):
            self.assertTrue((self.state / "sim-test.json").exists())
        with patch.object(m, "wait_until_idle"), patch.object(m, "devices", return_value=[
            {"udid": "new", "state": "Shutdown"}
        ]), patch.object(m.subprocess, "check_call", side_effect=boot):
            m.sim_prepare("new")
        self.assertEqual(json.loads((self.state / "sim-test.json").read_text())["udid"], "new")

    def test_cleanup_never_stops_an_active_test(self):
        lease = self.state / "sim-test.json"
        lease.write_text(json.dumps({"udid": "owned"}))
        with patch.object(m, "busy_pids", return_value=[123]), patch.object(m.subprocess, "run") as call:
            m.cleanup_owned(lease)
            call.assert_not_called()
            self.assertTrue(lease.exists())

    def test_cleanup_targets_only_owned_device(self):
        lease = self.state / "sim-test.json"
        lease.write_text(json.dumps({"udid": "owned"}))
        with patch.object(m, "busy_pids", return_value=[]), patch.object(m.subprocess, "run") as call:
            call.return_value.returncode = 0
            m.cleanup_owned(lease)
            self.assertEqual(call.call_args.args[0], ["xcrun", "simctl", "shutdown", "owned"])
            self.assertFalse(lease.exists())

    def test_build_failure_does_not_boot_simulator(self):
        with patch.object(sys, "argv", ["tool", "ui-test", "--simulator", "example"]), \
             patch.object(m, "wait_until_idle"), patch.object(m, "xcode", return_value=65), \
             patch.object(m, "sim_prepare") as boot:
            self.assertEqual(m.main(), 65)
            boot.assert_not_called()

    def test_child_failure_is_preserved(self):
        with m.build_lock(0) as (fd, _):
            self.assertEqual(m.run([sys.executable, "-c", "raise SystemExit(17)"], fd), 17)

    def test_default_build_is_arm64_and_does_not_boot(self):
        with patch.object(sys, "argv", ["tool", "build"]), \
             patch.object(m, "wait_until_idle"), patch.object(m, "xcode", return_value=0) as build, \
             patch.object(m, "sim_prepare") as boot:
            self.assertEqual(m.main(), 0)
            self.assertIn("ARCHS=arm64", build.call_args.args[0])
            self.assertIn("ONLY_ACTIVE_ARCH=YES", build.call_args.args[0])
            boot.assert_not_called()

    def test_one_job_limit_is_inherited_by_child_workflow(self):
        def child(*args):
            self.assertEqual(os.environ["MASO_BUILD_JOBS"], "1")
            return 0
        with patch.object(sys, "argv", ["tool", "--jobs", "1", "run", "--", "example"]), \
             patch.object(m, "wait_until_idle"), patch.object(m, "run", side_effect=child):
            self.assertEqual(m.main(), 0)

    def test_ui_execution_waits_until_build_completes(self):
        order = []
        def build(args, *rest):
            order.append(args[-1])
            return 0
        with patch.object(sys, "argv", ["tool", "ui-test", "--simulator", "example"]), \
             patch.object(m, "wait_until_idle"), patch.object(m, "xcode", side_effect=build), \
             patch.object(m, "sim_prepare", side_effect=lambda _: order.append("boot")):
            self.assertEqual(m.main(), 0)
            self.assertEqual(order, ["build-for-testing", "boot", "test-without-building"])


if __name__ == "__main__":
    unittest.main()
