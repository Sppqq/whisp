"""Offline tests for the Whisp auto-updater script."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("WHISP_TEST_BASH") or shutil.which("bash")
if os.name == "nt" and Path("C:/Program Files/Git/bin/bash.exe").exists():
    BASH = "C:/Program Files/Git/bin/bash.exe"


def extract_updater_script() -> str:
    swift_source = (ROOT / "Whisp/Services/UpdateService.swift").read_text(encoding="utf-8")
    match = re.search(r'static let updaterScriptContent = #"""\n(.*?)"""#', swift_source, re.DOTALL)
    if not match:
        raise ValueError("Could not extract updaterScriptContent from UpdateService.swift")
    return match.group(1)


@unittest.skipUnless(BASH, "bash is required")
class UpdaterScriptTests(unittest.TestCase):
    def setUp(self):
        self.script_content = extract_updater_script()

    def test_syntax(self):
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False, encoding="utf-8", newline="\n") as f:
            f.write(self.script_content)
            script_path = f.name
        try:
            result = subprocess.run([BASH, "-n", script_path], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        finally:
            if os.path.exists(script_path):
                os.remove(script_path)

    def test_successful_replacement(self):
        with tempfile.TemporaryDirectory(prefix="whisp-updater-test-") as temp:
            root = Path(temp)
            mocks = root / "mocks"
            mocks.mkdir()

            commands = {
                "osascript": "exit 0",
                "xattr": "exit 0",
                "open": 'touch "$1/LAUNCHED"; exit 0',
                "ditto": 'rm -rf "$2" && cp -R "$1" "$2"',
            }
            for name, body in commands.items():
                cmd_path = mocks / name
                cmd_path.write_text(f"#!/bin/bash\n{body}\n", encoding="utf-8", newline="\n")
                cmd_path.chmod(0o755)

            stage_app = root / "Staging/Whisp.app"
            stage_app.mkdir(parents=True)
            (stage_app / "version.txt").write_text("v2", encoding="utf-8")

            target_app = root / "Applications/Whisp.app"
            target_app.mkdir(parents=True)
            (target_app / "version.txt").write_text("v1", encoding="utf-8")

            script_text = self.script_content.replace(
                'export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"',
                'export PATH="$(pwd)/mocks:$PATH"'
            )
            script_file = root / "updater.sh"
            script_file.write_text(script_text, encoding="utf-8", newline="\n")
            log_file = root / "updater.log"

            # Use a non-existent PID so kill -0 returns 1 immediately
            fake_pid = "99999999"

            cmd = [
                BASH, "-c",
                f'export PATH="$(pwd)/mocks:$PATH"; bash updater.sh "{fake_pid}" "{stage_app.as_posix()}" "{target_app.as_posix()}" "{log_file.as_posix()}"'
            ]
            result = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=15)
            log_output = log_file.read_text(encoding="utf-8") if log_file.exists() else ""

            self.assertEqual(result.returncode, 0, f"Error: {result.stderr}\nLog: {log_output}")
            self.assertTrue(target_app.exists(), "Target app must exist")
            self.assertEqual((target_app / "version.txt").read_text(encoding="utf-8"), "v2")
            self.assertTrue((target_app / "LAUNCHED").exists(), "Target app must be launched")
            self.assertFalse(stage_app.exists(), "Staging folder must be cleaned up")

    def test_rollback_on_failed_ditto(self):
        with tempfile.TemporaryDirectory(prefix="whisp-updater-fail-test-") as temp:
            root = Path(temp)
            mocks = root / "mocks"
            mocks.mkdir()

            commands = {
                "osascript": "exit 0",
                "xattr": "exit 0",
                "open": "exit 0",
                "ditto": "exit 55",
            }
            for name, body in commands.items():
                cmd_path = mocks / name
                cmd_path.write_text(f"#!/bin/bash\n{body}\n", encoding="utf-8", newline="\n")
                cmd_path.chmod(0o755)

            stage_app = root / "Staging/Whisp.app"
            stage_app.mkdir(parents=True)
            (stage_app / "version.txt").write_text("v2", encoding="utf-8")

            target_app = root / "Applications/Whisp.app"
            target_app.mkdir(parents=True)
            (target_app / "version.txt").write_text("v1", encoding="utf-8")

            script_text = self.script_content.replace(
                'export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"',
                'export PATH="$(pwd)/mocks:$PATH"'
            )
            script_file = root / "updater.sh"
            script_file.write_text(script_text, encoding="utf-8", newline="\n")
            log_file = root / "updater.log"

            fake_pid = "99999999"

            cmd = [
                BASH, "-c",
                f'export PATH="$(pwd)/mocks:$PATH"; bash updater.sh "{fake_pid}" "{stage_app.as_posix()}" "{target_app.as_posix()}" "{log_file.as_posix()}"'
            ]
            result = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=15)
            log_output = log_file.read_text(encoding="utf-8") if log_file.exists() else ""

            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(target_app.exists())
            self.assertEqual((target_app / "version.txt").read_text(encoding="utf-8"), "v1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
