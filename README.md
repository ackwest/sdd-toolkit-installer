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

Only these bootstrap scripts are public. Executables, Lifecycle, skills and
templates are distributed through the private repository. This installer never
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
