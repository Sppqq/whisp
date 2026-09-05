"""Offline tests of installer preflight/failure paths; never runs a real install."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("WHISP_TEST_BASH") or shutil.which("bash")
if os.name == "nt" and Path("C:/Program Files/Git/bin/bash.exe").exists():
    BASH = "C:/Program Files/Git/bin/bash.exe"


@unittest.skipUnless(BASH, "bash is required")
class ReinstallTests(unittest.TestCase):
    def prepare_xcode(self, root):
        shutil.copy2(ROOT / "scripts/select_xcode.sh", root / "scripts/select_xcode.sh")
        binary = root / "Fake Xcode.app/Contents/Developer/usr/bin/xcodebuild"
        binary.parent.mkdir(parents=True)
        binary.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8", newline="\n")
        binary.chmod(0o755)

    def run_transaction(self, fail_at=None):
        with tempfile.TemporaryDirectory(prefix="whisp-transaction-test-") as temp:
            root = Path(temp)
            (root / "scripts").mkdir()
            self.prepare_xcode(root)
            mocks = root / "mocks"
            mocks.mkdir()
            installed = root / "Applications/Whisp.app"
            installed.mkdir(parents=True)
            (installed / "old-version").write_text("old", encoding="utf-8")
            app = root / "build/DerivedData/Build/Products/Release/Whisp.app"
            (app / "Contents/MacOS").mkdir(parents=True)
            binary = app / "Contents/MacOS/Whisp"
            binary.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8", newline="\n")
            binary.chmod(0o755)
            (app / "new-version").write_text("new", encoding="utf-8")
            source = (ROOT / "scripts/reinstall.sh").read_text(encoding="utf-8")
            source = source.replace('export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"',
                                    'export PATH="$ROOT/mocks:$PATH"')
            source = source.replace("/Applications", "$ROOT/Applications")
            source = source.replace("/usr/libexec/PlistBuddy", "PlistBuddy")
            (root / "scripts/reinstall.sh").write_text(source, encoding="utf-8", newline="\n")
            commands = {
                "uname": "echo Darwin", "id": "echo 501", "xcrun": "exit 0",
                "xcode-select": 'printf "%s\\n" "$PWD/Fake Xcode.app/Contents/Developer"',
                "xcodegen": "exit 0", "xcodebuild": "exit 0", "codesign": "exit 0",
                "PlistBuddy": "echo app.whisp.lectures", "pgrep": "exit 1",
                "open": "touch OPENED", "ditto": 'cp -R "$1" "$2"',
                "sudo": "touch UNEXPECTED_SUDO; exit 99",
            }
            if fail_at == "copy":
                commands["ditto"] = "exit 43"
            elif fail_at == "replace":
                commands["mv"] = 'case "$1" in */New.app) exit 43;; esac\n/bin/mv "$@"'
            for name, body in commands.items():
                command = mocks / name
                command.write_text("#!/bin/bash\n" + body + "\n", encoding="utf-8", newline="\n")
                command.chmod(0o755)
            result = subprocess.run(
                [BASH, "-c", 'export PATH="$(pwd)/mocks:$PATH"; bash scripts/reinstall.sh'],
                cwd=root, env={**os.environ, "DEVELOPER_DIR": "", "WHISP_DERIVED_DATA": str(root / "build/DerivedData")}, capture_output=True, text=True, encoding="utf-8", timeout=30,
            )
            self.assertFalse((root / "UNEXPECTED_SUDO").exists(), result.stdout + result.stderr)
            self.assertFalse((root / "build/reinstall.lock").exists())
            if fail_at:
                self.assertEqual(result.returncode, 43, result.stdout + result.stderr)
                self.assertTrue((installed / "old-version").exists(), result.stdout + result.stderr)
                self.assertFalse((root / "OPENED").exists())
            else:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((installed / "new-version").exists())
                self.assertTrue(list((root / "Applications").glob(".Whisp-install.*/Previous.app/old-version")))
                self.assertTrue((root / "OPENED").exists())

    def test_successful_install_retains_backup(self):
        self.run_transaction()

    def test_copy_failure_preserves_installed_app(self):
        self.run_transaction(fail_at="copy")

    def test_replace_failure_restores_previous_app(self):
        self.run_transaction(fail_at="replace")

    def run_installer(self, platform="Darwin", uid="501", fail_at="xcodebuild", existing_lock=False):
        with tempfile.TemporaryDirectory(prefix="whisp-installer-test-") as temp:
            root = Path(temp)
            (root / "scripts").mkdir()
            self.prepare_xcode(root)
            shutil.copy2(ROOT / "scripts/reinstall.sh", root / "scripts/reinstall.sh")
            mocks = root / "mocks"
            mocks.mkdir()
            commands = {
                "uname": f"printf '%s\\n' '{platform}'",
                "id": f"printf '%s\\n' '{uid}'",
                "xcrun": "exit 0",
                "xcode-select": 'printf "%s\\n" "$PWD/Fake Xcode.app/Contents/Developer"',
                "xcodegen": "exit 0",
                "xcodebuild": "exit 0",
                "brew": "exit 0",
            }
            if fail_at:
                commands[fail_at] = "exit 42"
            # These commands must NEVER be reached by any test in this suite.
            for name in ["sudo", "ditto", "codesign", "osascript", "open"]:
                commands[name] = "touch FORBIDDEN_INSTALL_ACTION; exit 99"
            for name, body in commands.items():
                path = mocks / name
                path.write_text("#!/bin/bash\n" + body + "\n", encoding="utf-8", newline="\n")
                path.chmod(0o755)
            script = root / "scripts/reinstall.sh"
            # Insert mocked commands AFTER the installer's Homebrew PATH setup.
            # This keeps tests isolated even on Macs with a real Homebrew/Xcode.
            source = script.read_text(encoding="utf-8")
            source = source.replace('export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"',
                                    'export PATH="$ROOT/mocks:$PATH"')
            script.write_text(source, encoding="utf-8", newline="\n")
            if existing_lock:
                (root / "build/reinstall.lock").mkdir(parents=True)
            result = subprocess.run(
                [BASH, "-c", 'export PATH="$(pwd)/mocks:$PATH"; bash scripts/reinstall.sh'],
                cwd=root, env={**os.environ, "DEVELOPER_DIR": ""}, capture_output=True, text=True, encoding="utf-8", timeout=30,
            )
            self.assertFalse((root / "FORBIDDEN_INSTALL_ACTION").exists(), result.stdout + result.stderr)
            lock = (root / "build/reinstall.lock").exists()
            return result, lock

    def test_shell_syntax(self):
        for script in [ROOT / "scripts/reinstall.sh", ROOT / "scripts/select_xcode.sh", ROOT / "Reinstall Whisp.command"]:
            subprocess.run([BASH, "-n", script.as_posix()], check=True)

    def test_non_macos_exits_before_build(self):
        result, lock = self.run_installer(platform="Linux")
        self.assertEqual(result.returncode, 1)
        self.assertIn("macOS", result.stderr)
        self.assertFalse(lock)

    def test_root_execution_is_refused(self):
        result, lock = self.run_installer(uid="0")
        self.assertEqual(result.returncode, 1)
        self.assertIn("sudo", result.stderr)
        self.assertFalse(lock)

    def test_failed_tests_do_not_install_and_release_lock(self):
        result, lock = self.run_installer()
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertFalse(lock)

    def test_failed_generation_does_not_install_and_release_lock(self):
        result, lock = self.run_installer(fail_at="xcodegen")
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertFalse(lock)

    def test_concurrent_run_does_not_remove_other_lock(self):
        result, lock = self.run_installer(existing_lock=True)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(lock)


if __name__ == "__main__":
    unittest.main(verbosity=2)
