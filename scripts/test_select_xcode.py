"""Xcode discovery tests with fake installations; no macOS settings are changed."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")
if os.name == "nt" and Path("C:/Program Files/Git/bin/bash.exe").exists():
    BASH = "C:/Program Files/Git/bin/bash.exe"


@unittest.skipUnless(BASH, "bash is required")
class XcodeSelectionTests(unittest.TestCase):
    def select(self, installations=(), selected="CommandLineTools", explicit="", spotlight=""):
        with tempfile.TemporaryDirectory(prefix="whisp-xcode-test-") as temp:
            root = Path(temp)
            mocks = root / "mocks"
            mocks.mkdir()
            source = (ROOT / "scripts/select_xcode.sh").read_text(encoding="utf-8")
            source = source.replace("/Applications/Xcode", '"${PWD}/Applications"/Xcode')
            source = source.replace('"${HOME}/Applications/"', '"${PWD}/UserApps/"')
            (root / "select.sh").write_text(source, encoding="utf-8", newline="\n")
            for app in installations:
                binary = root / app / "Contents/Developer/usr/bin/xcodebuild"
                binary.parent.mkdir(parents=True)
                binary.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8", newline="\n")
                binary.chmod(0o755)
            commands = {
                "xcode-select": 'if [[ "$1" != --print-path ]]; then touch MUTATED; exit 99; fi\nprintf "%s\\n" "$PWD/' + selected + '"',
                "xcrun": 'case "$DEVELOPER_DIR" in *Broken*) echo "missing macOS SDK" >&2; exit 1;; esac\nexit 0',
                "mdfind": ('printf "%s\\n" "$PWD/' + spotlight + '"') if spotlight else "exit 0",
                "sudo": "touch MUTATED; exit 99",
            }
            for name, body in commands.items():
                command = mocks / name
                command.write_text("#!/bin/bash\n" + body + "\n", encoding="utf-8", newline="\n")
                command.chmod(0o755)
            command = 'export PATH="$PWD/mocks:$PATH"; '
            if explicit:
                command += 'export DEVELOPER_DIR="$PWD/' + explicit + '"; '
            command += 'source select.sh; whisp_select_xcode'
            result = subprocess.run([BASH, "-c", command], cwd=root,
                env={**os.environ, "DEVELOPER_DIR": ""}, capture_output=True,
                text=True, encoding="utf-8", timeout=20)
            self.assertFalse((root / "MUTATED").exists())
            return result

    def test_clt_selection_falls_back_to_installed_xcode(self):
        result = self.select(installations=["Applications/Xcode.app"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Applications/Xcode.app/Contents/Developer", result.stdout)

    def test_selected_xcode_is_preserved(self):
        result = self.select(installations=["Custom Xcode.app", "Applications/Xcode.app"],
                             selected="Custom Xcode.app/Contents/Developer")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Custom Xcode.app/Contents/Developer", result.stdout)

    def test_explicit_app_path_with_spaces_is_normalized(self):
        result = self.select(installations=["Xcode beta.app", "Applications/Xcode.app"], explicit="Xcode beta.app")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Xcode beta.app/Contents/Developer", result.stdout)

    def test_beta_is_discovered(self):
        result = self.select(installations=["Applications/Xcode-beta.app"])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_spotlight_finds_renamed_xcode(self):
        result = self.select(installations=["Tools/Apple IDE.app"], spotlight="Tools/Apple IDE.app")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Tools/Apple IDE.app/Contents/Developer", result.stdout)

    def test_missing_xcode_reports_selected_directory(self):
        result = self.select()
        self.assertEqual(result.returncode, 1)
        self.assertIn("CommandLineTools", result.stderr)
        self.assertIn("DEVELOPER_DIR=", result.stderr)

    def test_broken_explicit_sdk_is_not_silently_overridden(self):
        result = self.select(installations=["Broken.app", "Applications/Xcode.app"], explicit="Broken.app")
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing macOS SDK", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
