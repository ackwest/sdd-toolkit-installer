"""Exercise authenticated bootstrap downloads without touching user installations."""

import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import zipfile


REPO = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix="sdd-installer-tests-")
        cls.root = Path(cls.scratch.name)
        cls.addClassCleanup(cls.scratch.cleanup)
        cls.shells = []
        shell = shutil.which("sh")
        if os.name == "nt":
            git_shell = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/usr/bin/sh.exe"
            if git_shell.exists():
                shell = str(git_shell)
            cls.powershell = shutil.which("pwsh") or shutil.which("powershell")
            if not cls.powershell:
                raise RuntimeError("PowerShell is required for the Windows installer tests")
            source = cls.root / "version.go"
            source.write_text('''package main
import ("fmt"; "os"; "strings")
func main() {
 if len(os.Args) > 1 && os.Args[1] == "install" {
  os.WriteFile(os.Getenv("TEST_SETUP"), []byte(strings.Join(os.Args[1:], "\\n")), 0600)
  if os.Getenv("TEST_FAILURE") == "setup" { os.Exit(2) }
  fmt.Println("fixture setup completed")
  return
 }
 fmt.Println("0.1.0")
}
''')
            binary = cls.root / "sdd-toolkit.exe"
            subprocess.run(["go", "build", "-o", str(binary), str(source)], check=True, capture_output=True)
            cls.windows_binary = binary.read_bytes()
            cls.shells.append("powershell")
        if shell:
            cls.shell = shell
            cls.shells.extend(["linux", "darwin"])
        if not cls.shells:
            raise RuntimeError("No supported shell available for installer tests")

    def run_installer(self, platform, version="latest", failure="", setup=False, login=False, pipe=False, missing_gh=False, profile_shell=""):
        scratch = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        fixture, destination, mock_bin = root / "fixture", root / "installed", root / "bin"
        if profile_shell:
            destination = root / "installed folder's $literal"
        for directory in (fixture, destination, mock_bin):
            directory.mkdir()
        args_file = root / "arguments"
        setup_file, calls_file = root / "setup-arguments", root / "calls"
        env = os.environ.copy()
        env.pop("PSModulePath", None)
        env.pop("PSMODULEPATH", None)
        env.update({
            "TEST_FIXTURE": fixture.as_posix(), "TEST_ARGS": args_file.as_posix(),
            "TEST_FAILURE": failure, "TEST_DEST": str(destination), "TEST_VERSION": version,
            "TEST_SETUP": str(setup_file), "TEST_CALLS": calls_file.as_posix(),
            "TEST_SKIP_SETUP": "0" if setup else "1", "TEST_LOGIN": "1" if login else "0",
            "TEST_MISSING_GH": "1" if missing_gh else "0", "TEST_PIPE": "1" if pipe else "0",
            "SDD_TOOLKIT_NO_PATH_UPDATE": "1",
        })
        if profile_shell:
            profile_home = root / "profile"
            profile_home.mkdir()
            profile = profile_home / (".zshenv" if profile_shell == "zsh" else ".profile")
            original_profile = "# existing user configuration\nexport TEST_PROFILE_VALUE=kept\n"
            profile.write_text(original_profile)
            env.update(HOME=profile_home.as_posix(), SHELL="/bin/" + profile_shell, SDD_TOOLKIT_NO_PATH_UPDATE="0")
            env.pop("ZDOTDIR", None)
        if platform == "powershell":
            arch = "arm64" if os.environ.get("PROCESSOR_ARCHITECTURE", "").lower() == "arm64" else "amd64"
            archive = f"sdd-toolkit_windows_{arch}.zip"
            expected = self.windows_binary
            installed = destination / "sdd-toolkit.exe"
            with zipfile.ZipFile(fixture / archive, "w") as output:
                output.writestr("sdd-toolkit.exe", expected)
            wrapper = root / "run.ps1"
            wrapper.write_text('''
$ErrorActionPreference = 'Stop'
$env:TEST_GH_READY = if ($env:TEST_MISSING_GH -eq '1') { '0' } else { '1' }
function Get-Command {
    param([string]$Name, $ErrorAction)
    if ($Name -eq 'gh' -and $env:TEST_GH_READY -eq '0') { return }
    Microsoft.PowerShell.Core\\Get-Command $Name -ErrorAction SilentlyContinue
}
function winget {
    ('winget ' + ($args -join ' ')) | Add-Content -LiteralPath $env:TEST_CALLS
    $env:TEST_GH_READY = '1'
    $global:LASTEXITCODE = 0
}
function gh {
    $arguments = @($args)
    ($arguments -join ' ') | Add-Content -LiteralPath $env:TEST_CALLS
    if ($arguments[0] -eq 'auth') {
        $global:LASTEXITCODE = 0
        if ($arguments[1] -eq 'status' -and ($env:TEST_FAILURE -eq 'auth' -or $env:TEST_LOGIN -eq '1')) { $global:LASTEXITCODE = 1 }
        return
    }
    if ($arguments[0] -eq 'api') { $global:LASTEXITCODE = 0; if ($env:TEST_FAILURE -eq 'access') { $global:LASTEXITCODE = 1 }; return }
    if ($arguments[1] -eq 'view') { $global:LASTEXITCODE = 0; 'v0.1.0'; return }
    ConvertTo-Json -InputObject $arguments | Set-Content -LiteralPath $env:TEST_ARGS
    if ($env:TEST_FAILURE -eq 'download') { $global:LASTEXITCODE = 17; return }
    $target = $arguments[[Array]::IndexOf($arguments, '--dir') + 1]
    Get-ChildItem -LiteralPath $env:TEST_FIXTURE -File | Copy-Item -Destination $target
    $global:LASTEXITCODE = 0
}
function Read-Host { 'y' }
if ($env:TEST_PIPE -eq '1') {
    $env:SDD_TOOLKIT_INSTALL_DIR = $env:TEST_DEST
    $env:SDD_TOOLKIT_NO_PATH_UPDATE = '1'
    $env:SDD_TOOLKIT_VERSION = $env:TEST_VERSION
    $env:SDD_TOOLKIT_NO_INPUT = if ($env:TEST_LOGIN -eq '1') { '0' } else { '1' }
    $env:SDD_TOOLKIT_SKIP_SETUP = $env:TEST_SKIP_SETUP
    $env:SDD_TOOLKIT_AGENT = 'codex'
    Get-Content -Raw -LiteralPath $env:TEST_INSTALLER | Invoke-Expression
} else {
    & $env:TEST_INSTALLER -InstallDir $env:TEST_DEST -NoPathUpdate -Version $env:TEST_VERSION -NoInput:($env:TEST_LOGIN -ne '1') -SkipSetup:($env:TEST_SKIP_SETUP -eq '1') -Agent codex
}
''', encoding="utf-8")
            env["TEST_INSTALLER"] = str(REPO / "install.ps1")
            command = [self.powershell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(wrapper)]
        else:
            archive = f"sdd-toolkit_{platform}_amd64.tar.gz"
            expected = b'''#!/bin/sh
if [ "$1" = install ]; then
  printf '%s\\n' "$@" > "$TEST_SETUP"
  [ "$TEST_FAILURE" != setup ] || exit 2
  echo 'fixture setup completed'
else
  echo '0.1.0'
fi
'''
            installed = destination / "sdd-toolkit"
            with tarfile.open(fixture / archive, "w:gz") as output:
                entry = tarfile.TarInfo("sdd-toolkit")
                entry.mode, entry.size = 0o755, len(expected)
                output.addfile(entry, io.BytesIO(expected))
            (mock_bin / "gh").write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_CALLS"
case "$1 $2" in
  'auth status') [ "$TEST_FAILURE" != auth ]; exit $?;;
  'auth login') exit 0;;
  'api repos/ackwest/sdd-toolkit') [ "$TEST_FAILURE" != access ]; exit $?;;
  'release view') echo v0.1.0; exit 0;;
esac
printf '%s\\n' "$@" > "$TEST_ARGS"
[ "$TEST_FAILURE" != download ] || exit 17
while [ "$#" -gt 0 ]; do
  if [ "$1" = --dir ]; then shift; target="$1"; fi
  shift
done
cp "$TEST_FIXTURE"/* "$target/"
''', encoding="utf-8", newline="\n")
            os_name = "Linux" if platform == "linux" else "Darwin"
            (mock_bin / "uname").write_text(f'#!/bin/sh\ncase "$1" in -s) echo {os_name};; -m) echo x86_64;; esac\n', newline="\n")
            for path in mock_bin.iterdir():
                path.chmod(0o755)
            shell_tools = str(Path(self.shell).parent)
            env.update({"PATH": os.pathsep.join([str(mock_bin), shell_tools, env["PATH"]]), "SDD_TOOLKIT_INSTALL_DIR": destination.as_posix(), "SDD_TOOLKIT_VERSION": version, "SDD_TOOLKIT_NO_INPUT": "1", "SDD_TOOLKIT_SKIP_SETUP": "0" if setup else "1", "SDD_TOOLKIT_AGENT": "codex", "TEST_SETUP": setup_file.as_posix()})
            command = [self.shell, str(REPO / "install.sh")]
            if pipe:
                command = [self.shell]
        digest = hashlib.sha256((fixture / archive).read_bytes()).hexdigest()
        if failure == "checksum":
            digest = "0" * 64
        (fixture / "checksums.txt").write_text(f"{digest}  {archive}\n")
        installed.write_bytes(b"existing working binary")
        result = subprocess.run(command, env=env, input=(REPO / "install.sh").read_text() if pipe and platform != "powershell" else None, capture_output=True, text=True, timeout=45)
        if profile_shell:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(profile.read_text().startswith(original_profile))
            self.assertEqual(Path(str(profile) + ".sdd-toolkit-backup").read_text(), original_profile)
            repeat = subprocess.run(command, env=env, capture_output=True, text=True, timeout=45)
            self.assertEqual(repeat.returncode, 0, repeat.stdout + repeat.stderr)
            self.assertEqual(profile.read_text().count("# SDD Toolkit executable"), 1)
            env["TEST_PROFILE"] = profile.as_posix()
            sourced = subprocess.run([self.shell, "-c", '. "$TEST_PROFILE"; printf "%s" "$PATH"'], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(sourced.returncode, 0, sourced.stderr)
            self.assertTrue(sourced.stdout.startswith(destination.as_posix() + ":"), sourced.stdout)
        if missing_gh and not login:
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(args_file.exists())
            self.assertFalse(calls_file.exists(), "non-interactive install must not install dependencies")
            return
        if failure in ("auth", "access"):
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(args_file.exists(), "download started without authorization")
            self.assertEqual(installed.read_bytes(), b"existing working binary")
            self.assertFalse(setup_file.exists())
            return
        self.assertTrue(args_file.exists(), result.stdout + result.stderr)
        if platform == "powershell":
            arguments = json.loads(args_file.read_text(encoding="utf-8-sig"))
        else:
            arguments = args_file.read_text().splitlines()
        self.assertEqual(arguments[:2], ["release", "download"])
        self.assertEqual(arguments[arguments.index("--repo") + 1], "ackwest/sdd-toolkit")
        self.assertIn(archive, arguments)
        self.assertIn("checksums.txt", arguments)
        self.assertEqual(arguments[-1], "v0.1.0", "latest must resolve once to an immutable release")
        if failure in ("download", "checksum"):
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(installed.read_bytes(), b"existing working binary")
            message = "Release download failed" if failure == "download" else "Checksum mismatch"
            self.assertIn(message, result.stdout + result.stderr)
        else:
            if failure == "setup":
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("setup needs attention", result.stdout + result.stderr)
                self.assertNotIn("Setup complete.", result.stdout)
            else:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(installed.read_bytes(), expected)
            self.assertIn("0.1.0", result.stdout)
            self.assertEqual(setup_file.exists(), setup)
            if setup:
                setup_args = setup_file.read_text().splitlines()
                self.assertEqual(setup_args[:3], ["install", "--agent", "codex"])
                if not login:
                    self.assertEqual(setup_args[3:], ["--no-input", "--json"])
            calls = calls_file.read_text()
            if missing_gh:
                self.assertIn("winget install --id GitHub.cli --exact --source winget", calls)
            if login:
                self.assertIn("auth login --hostname github.com --web --git-protocol https", calls)
            else:
                self.assertNotIn("auth login", calls, "existing authentication must be reused")

    def test_authenticated_download_latest_and_explicit_release(self):
        for platform in self.shells:
            for version in ("latest", "0.1.0", "v0.1.0"):
                with self.subTest(platform=platform, version=version):
                    self.run_installer(platform, version)

    def test_download_failure_preserves_existing_binary(self):
        for platform in self.shells:
            with self.subTest(platform=platform):
                self.run_installer(platform, failure="download")

    def test_checksum_failure_preserves_existing_binary(self):
        for platform in self.shells:
            with self.subTest(platform=platform):
                self.run_installer(platform, failure="checksum")

    def test_automatic_setup_and_incomplete_setup(self):
        for platform in self.shells:
            for failure in ("", "setup"):
                with self.subTest(platform=platform, failure=failure):
                    self.run_installer(platform, setup=True, failure=failure)

    def test_missing_authentication_and_repository_access_stop_before_download(self):
        for platform in self.shells:
            for failure in ("auth", "access"):
                with self.subTest(platform=platform, failure=failure):
                    self.run_installer(platform, failure=failure)

    def test_powershell_offers_browser_login(self):
        if "powershell" not in self.shells:
            self.skipTest("Windows only")
        self.run_installer("powershell", setup=True, login=True)

    def test_powershell_bootstrap_prepares_missing_gh_and_runs_through_iex(self):
        if "powershell" not in self.shells:
            self.skipTest("Windows only")
        self.run_installer("powershell", setup=True, login=True, missing_gh=True, pipe=True)
        self.run_installer("powershell", missing_gh=True)

    def test_shell_script_can_be_received_through_stdin(self):
        for platform in self.shells:
            if platform != "powershell":
                with self.subTest(platform=platform):
                    self.run_installer(platform, setup=True, pipe=True)

    def test_shell_path_setup_preserves_profile_and_quotes_install_directory(self):
        if "linux" not in self.shells:
            self.skipTest("POSIX shell required")
        for shell in ("sh", "bash", "zsh"):
            with self.subTest(shell=shell):
                self.run_installer("linux", profile_shell=shell)


if __name__ == "__main__":
    unittest.main()
