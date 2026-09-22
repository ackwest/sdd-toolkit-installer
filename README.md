# SDD Toolkit installer

Install the private SDD Toolkit package with one command. Your GitHub account
must have Read access to `ackwest/sdd-toolkit`.

If you already have a working `sdd-toolkit` command, choose the operation below instead of
downloading the installer again:

| Situation | Command |
|---|---|
| First setup or resume interrupted setup | `sdd-toolkit install` |
| Replace the original Reach Collective Lifecycle | `sdd-toolkit migrate` |
| Update an existing new-distribution installation | `sdd-toolkit update` |
| Restore missing or damaged managed components | `sdd-toolkit repair` |
| Diagnose workspace configuration or access | `sdd-toolkit doctor` from the workspace |

`repair` uses the installed executable; a plugin version mismatch requires `update`.
If the executable is missing or too old for the command you need, use the installer below.

## First installation

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
specific private release and checks its SHA-256 checksum. It then runs `sdd-toolkit install`
automatically. On first setup, choose your installed coding agent, or **Both** if both runtimes
are available and you use them. Supply any requested service credentials in your terminal.
Restart the selected agents after setup.

Install Codex or Claude Code separately before configuring it. The installer
does not install coding agents. Package-manager availability and enterprise
device policies may require your administrator's assistance with GitHub CLI.

The bootstrap scripts, documentation and synthetic tests are public. Executables,
Lifecycle, skills and templates are distributed through the private repository. This installer never
requests a GitHub token on the command line or copies it into Toolkit settings.

## Moving from the original Lifecycle

The original plugin is `lifecycle@reachcollective-sdd-toolkit`; the replacement is
`lifecycle@sdd-toolkit`.

1. If you only have the original plugin, first install the executable using the command above.
   The current installer runs `install`; it does not automatically choose migration.
   Open a new terminal after setup if needed for PATH changes.
2. If `sdd-toolkit` is already available and supports migration, go directly to this command;
   no separate `install` is required:

   ```text
   sdd-toolkit migrate
   ```

3. Restart the migrated agents. Use `sdd-toolkit update` for later releases.

Migration installs and verifies the replacement before removing the old user-scoped Lifecycle.
It preserves other plugins, credentials and project files. A failed replacement leaves the old
plugin installed; project-scoped installations are reported for explicit project-specific handling.
Use `sdd-toolkit migrate --dry-run` to preview the operation.

Without `--agent`, maintenance reuses the agents selected during setup. Both are covered only when
both were selected. To target an agent explicitly, use `sdd-toolkit migrate --agent codex` or
`sdd-toolkit migrate --agent claude`. The interactive first setup offers **Both**; `--agent both`
is not a supported flag value.

## Updating

To update the executable and managed plugins on Toolkit 0.2.1 or later, run:

```text
sdd-toolkit update
sdd-toolkit version
```

For Toolkit 0.2.0 or earlier, run this installer once to enable self-updates.

Current releases update once for your user across all workspaces. Restart the updated coding agents.
The output may show `Remove`, `Replace`, `Register` and `Install`: these replace the managed plugin
and its catalog. Project files and stored credentials are preserved. `Workspace access was not
checked` is expected during an update; run `sdd-toolkit doctor` from a workspace to diagnose that
access separately. Read the full [update output explanation](https://github.com/ackwest/sdd-toolkit#reading-update-output)
for the meaning of each step.

Toolkit and Lifecycle have independent versions. `sdd-toolkit version` reports the executable,
so its number need not match the installed Lifecycle plugin version.

## Installer options

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
