[CmdletBinding()]
param(
    [string]$Version = $(if ($env:SDD_TOOLKIT_VERSION) { $env:SDD_TOOLKIT_VERSION } else { 'latest' }),
    [string]$InstallDir = $(if ($env:SDD_TOOLKIT_INSTALL_DIR) { $env:SDD_TOOLKIT_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\sdd-toolkit' }),
    [switch]$NoPathUpdate = ($env:SDD_TOOLKIT_NO_PATH_UPDATE -eq '1'),
    [switch]$NoInput = ($env:SDD_TOOLKIT_NO_INPUT -eq '1'),
    [switch]$SkipSetup = ($env:SDD_TOOLKIT_SKIP_SETUP -eq '1'),
    [ValidateSet('', 'codex', 'claude')][string]$Agent = $env:SDD_TOOLKIT_AGENT
)

$ErrorActionPreference = 'Stop'
$repository = 'ackwest/sdd-toolkit'
function Confirm-ToolkitStep([string]$Message) {
    if ($NoInput) { return $false }
    return (Read-Host "$Message [y/N]") -match '^(y|yes)$'
}

Write-Host 'SDD Toolkit setup'
$architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    'X64' { 'amd64' }
    'Arm64' { 'arm64' }
    default { throw "Unsupported Windows architecture: $_" }
}
$archive = "sdd-toolkit_windows_${architecture}.zip"
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI is missing. Install it from https://cli.github.com and run this installer again.'
    }
    if (-not (Confirm-ToolkitStep 'Install GitHub CLI using WinGet?')) {
        throw 'GitHub CLI is required to download the private package. Nothing was installed.'
    }
    & winget install --id GitHub.cli --exact --source winget
    if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI installation failed; run this installer again after resolving the WinGet error.' }
    $env:Path = @($env:Path, [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';'
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI was installed. Open a new terminal and run this same installer again.'
    }
}
& gh auth status --active --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) {
    if (-not (Confirm-ToolkitStep 'Sign in to GitHub in your browser to download SDD Toolkit?')) {
        throw 'GitHub authentication is required. Run gh auth login or rerun this installer interactively.'
    }
    & gh auth login --hostname github.com --web --git-protocol https
    if ($LASTEXITCODE -ne 0) { throw 'GitHub sign-in was not completed. Nothing was installed.' }
}
& gh api "repos/$repository" --silent
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot access ackwest/sdd-toolkit. Check your active GitHub account, repository Read access, organization SSO authorization, and connectivity.'
}
if ($Version -eq 'latest') {
    $releaseTag = & gh release view --repo $repository --json tagName --jq .tagName
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the latest private release.' }
    $releaseTag = "$releaseTag".Trim()
} else {
    $releaseTag = "v$($Version.TrimStart('v'))"
}
if ($releaseTag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$') { throw 'Invalid release version.' }
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("sdd-toolkit-" + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    $archivePath = Join-Path $temporary $archive
    $checksumsPath = Join-Path $temporary 'checksums.txt'
    $downloadArgs = @('release', 'download', '--repo', $repository, '--pattern', $archive, '--pattern', 'checksums.txt', '--dir', $temporary, $releaseTag)
    & gh @downloadArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Release download failed. Check GitHub connectivity and gh authentication/access to ackwest/sdd-toolkit; no binary was replaced.'
    }

    $expectedLine = Get-Content -LiteralPath $checksumsPath | Where-Object { $_ -match "\s+$([regex]::Escape($archive))$" } | Select-Object -First 1
    if (-not $expectedLine) { throw "No checksum published for $archive" }
    $expected = ($expectedLine -split '\s+')[0].ToLowerInvariant()
    if ($expected -notmatch '^[0-9a-f]{64}$') { throw 'Invalid release checksum.' }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Checksum mismatch for $archive" }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $temporary -Force
    $stagedBinary = Join-Path $temporary 'sdd-toolkit.exe'
    $binaryVersion = & $stagedBinary version
    if ($LASTEXITCODE -ne 0 -or "$binaryVersion".Trim() -ne $releaseTag.Substring(1)) {
        throw 'Downloaded executable does not match the requested release; no binary was replaced.'
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $temporary 'sdd-toolkit.exe') -Destination (Join-Path $InstallDir 'sdd-toolkit.exe') -Force

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathParts = @($userPath -split ';' | Where-Object { $_ })
    if (-not $NoPathUpdate -and $pathParts -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable('Path', (($pathParts + $InstallDir) -join ';'), 'User')
        $env:Path = "$env:Path;$InstallDir"
        Write-Host "Added $InstallDir to your user PATH. Open a new terminal after this command."
    }
    # The child setup must see this executable even when user PATH writes were disabled.
    $env:Path = "$InstallDir;$env:Path"
    Write-Host "Installed SDD Toolkit $($releaseTag.Substring(1)) for this Windows user."
    if ($SkipSetup) {
        Write-Host 'Setup skipped. Next: sdd-toolkit install'
    } else {
        $setupArgs = @('install')
        if ($Agent) { $setupArgs += @('--agent', $Agent) }
        if ($NoInput) { $setupArgs += @('--no-input', '--json') }
        & (Join-Path $InstallDir 'sdd-toolkit.exe') @setupArgs
        if ($LASTEXITCODE -ne 0) {
            throw "The executable is installed, but setup needs attention (code $LASTEXITCODE). Resolve the message above, then run sdd-toolkit install."
        }
        Write-Host 'Setup complete. Restart your coding agent to load Lifecycle.'
    }
} finally {
    if (Test-Path -LiteralPath $temporary) {
        $resolvedTemporary = (Resolve-Path -LiteralPath $temporary).Path
        $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolvedTemporary.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a directory outside the temporary root.'
        }
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
