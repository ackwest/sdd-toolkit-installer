# SDD Toolkit installer

Install the private SDD Toolkit package with one command. Your GitHub account
must have Read access to `ackwest/sdd-toolkit`.

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/ackwest/sdd-toolkit-installer/main/install.ps1 | iex
```

macOS or Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/ackwest/sdd-toolkit-installer/main/install.sh | sh
```

The installer offers to install GitHub CLI if needed, reuses its active GitHub
session or offers browser sign-in, verifies repository access, downloads a
specific private release and checks its SHA-256 checksum. It then starts setup
automatically. Choose your installed coding agent and supply the requested
service credentials in your terminal. Restart the agent after setup.

Install Codex or Claude Code separately before configuring it. The installer
does not install coding agents. Package-manager availability and enterprise
device policies may require your administrator's assistance with GitHub CLI.

The bootstrap scripts, documentation and synthetic tests are public. Executables,
Lifecycle, skills and templates are distributed through the private repository. This installer never
requests a GitHub token on the command line or copies it into Toolkit settings.

If setup is interrupted, run `sdd-toolkit install` again. Run `sdd-toolkit doctor`
for diagnosis. To update the executable and managed plugins on Toolkit 0.2.1 or
later, run:

```text
sdd-toolkit update
sdd-toolkit version
```

For Toolkit 0.2.0 or earlier, run this installer once to enable self-updates.

For an already-downloaded script, PowerShell accepts `-Version`, `-InstallDir`,
`-NoPathUpdate`, `-NoInput`, `-SkipSetup`, and `-Agent codex|claude`.
The shell equivalents are `SDD_TOOLKIT_VERSION`, `SDD_TOOLKIT_INSTALL_DIR`,
`SDD_TOOLKIT_NO_INPUT=1`, `SDD_TOOLKIT_SKIP_SETUP=1`, and
`SDD_TOOLKIT_AGENT=codex|claude`. Non-interactive callers must provision GitHub
CLI/authentication themselves; dependency installation and login never run in
that mode. Setup receives `--no-input --json`.

The shell installer defaults to `$HOME/.local/bin` and adds it to the appropriate
sh/bash/zsh startup file, preserving a backup of an existing file. Other shells
receive a PATH instruction. Windows updates the user PATH. Open a new terminal
after setup. `SDD_TOOLKIT_NO_PATH_UPDATE=1` suppresses persistent PATH changes on
both platforms. All `SDD_TOOLKIT_*` options above also work in PowerShell.

## Maintenance

This repository owns the bootstrap scripts and their tests. Make installer changes
here; do not maintain copies or export bundles from the private Toolkit repository.
The private repository owns the CLI, self-update, setup, managed plugins and releases.

Run the fixture tests with Python 3 and Go available on PATH:

```text
python scripts/test_installers.py
```

Go builds a synthetic Windows executable for the tests; users do not need Go or
Python to install the Toolkit. The tests use temporary directories and mock GitHub,
sign-in and setup; they do not download private content or configure a coding agent.
CI runs the suite on Windows, macOS and Linux without repository secrets.

Merge reviewed changes to `main` to publish the public script URLs. Preserve the
private release archive names, checksum format and CLI invocation contract when
changing either repository. No executable or Lifecycle payload belongs here.
