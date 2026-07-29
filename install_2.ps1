#Requires -Version 5.1
<#
.SYNOPSIS
  install_2.ps1 — installer for "projectifier" (https://github.com/placentaEscaper/projectifier) on Windows.

.DESCRIPTION
  Windows counterpart of install_2.sh. What this does:
    1. Checks that the OS is Windows.
    2. Checks that winget is available (App Installer) — used to install git.
    3. Installs git via winget if missing.
    4. Installs uv (Python package manager) via Astral's official installer script if missing.
    5. Clones/updates the private repository (main branch only) into
         %LOCALAPPDATA%\Programs\projectifier\projectifier
       (kept as a subfolder inside %LOCALAPPDATA%\Programs\projectifier, right next to
       the `prj` command itself — a different location from %LOCALAPPDATA%\projectifier,
       which the app itself already uses at runtime to store configs.txt and the
       "Liven_Template folder" (see projectifier/filesystem.py's _default_conf_dir).
       Those two locations are intentionally kept separate so the code checkout and
       the app's own runtime data never collide.)
    6. Runs `uv sync` to install the exact Python version (3.14, per
       .python-version / pyproject.toml) and dependencies from uv.lock.
    7. Creates the `prj` command (prj.cmd + prj.ps1) and adds its folder to the
       user PATH.
    8. Bakes a self-update check into `prj`: once a day it checks the latest
       commit on the main branch and, if a newer one exists, pulls it and
       re-syncs dependencies via uv before running main.py.
    9. Copies the "Liven_Template" template project folder into
         %LOCALAPPDATA%\projectifier
       and unpacks tokens.zip into
         %LOCALAPPDATA%\Programs\projectifier\projectifier\env
       Both Liven_Template\ and tokens.zip must sit next to this script
       (i.e. in the same folder as install_2.ps1) at install time.

  Re-running install_2.ps1 always force-updates to the latest commit on main.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install_2.ps1
#>

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$RepoOwner = "placentaEscaper"
$RepoName = "projectifier"
$Repo = "$RepoOwner/$RepoName"
$Branch = "main"
$EntryPoint = "main.py"
$CmdName = "prj"
$PythonVersion = "3.14"

$ProgramsDir = Join-Path $env:LOCALAPPDATA "Programs\projectifier"   # holds the code checkout + the prj wrapper
$BinDir = Join-Path $ProgramsDir "bin"
$CodeDir = Join-Path $ProgramsDir $RepoName                          # the actual git checkout lives here
$InstallerMetaDir = Join-Path $ProgramsDir ".installer"              # installer's own bookkeeping files
$ConfigDir = Join-Path $env:LOCALAPPDATA "projectifier"
# NOTE: the app itself (projectifier/filesystem.py, _default_conf_dir) separately
# writes %LOCALAPPDATA%\projectifier\configs.txt at runtime — that's unrelated
# to where we put the code, and is left alone.

$CredFile = Join-Path $InstallerMetaDir ".credentials"
$ShaFile = Join-Path $InstallerMetaDir ".commit_sha"
$LastCheckFile = Join-Path $InstallerMetaDir ".last_check"
$UpdateIntervalSeconds = 86400   # 24 hours

# ScriptDir is where install_2.ps1 itself lives — Liven_Template\ and
# tokens.zip are expected to sit right next to it at install time.
$ScriptDir = $PSScriptRoot
$TemplateName = "Liven_Template"
$TemplateSrc = Join-Path $ScriptDir $TemplateName
$TemplateDest = Join-Path $ConfigDir $TemplateName
$TokensZip = Join-Path $ScriptDir "tokens.zip"
$EnvDir = Join-Path $CodeDir "env"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Info([string]$msg) { Write-Host "[info]  $msg" -ForegroundColor Cyan }
function Ok([string]$msg) { Write-Host "[ok]    $msg" -ForegroundColor Green }
function Warn([string]$msg) { Write-Host "[warn]  $msg" -ForegroundColor Yellow }
function Err([string]$msg) { Write-Host "[error] $msg" -ForegroundColor Red }

# Unlike bash's `set -e`, PowerShell does NOT stop on a non-zero exit code
# from an external command (git, uv, ...) — only on terminating cmdlet
# errors. Call this right after any external command that must succeed.
function Assert-Success([string]$what) {
    if ($LASTEXITCODE -ne 0) {
        Err "$what failed (exit code $LASTEXITCODE)."
        exit 1
    }
}

# Winget/uv installs land in the machine/user PATH registry values, but this
# already-running process doesn't pick that up automatically — refresh $env:Path
# from the registry so newly installed tools are usable without a new shell.
function Update-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# ---------------------------------------------------------------------------
# 0. OS check
# ---------------------------------------------------------------------------
if ($env:OS -ne "Windows_NT") {
    Err "This installer only supports Windows. Use install_2.sh on macOS."
    exit 1
}
Info "Detected Windows ($([System.Environment]::OSVersion.VersionString))."

# ---------------------------------------------------------------------------
# 1. winget
# ---------------------------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err "winget (App Installer) was not found."
    Err "Install it from the Microsoft Store (https://aka.ms/getwinget) or via Windows Update, then re-run this script."
    exit 1
}
Ok "winget is available."

# ---------------------------------------------------------------------------
# 2. git
# ---------------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Info "Installing git via winget..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Update-SessionPath
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Err "git was installed but isn't on PATH yet. Open a new terminal and re-run this script."
        exit 1
    }
} else {
    Ok "git is already installed ($(git --version))."
}

# ---------------------------------------------------------------------------
# 3. uv (via Astral's official installer — it will fetch the right Python
#    version itself, no separate Python install needed)
# ---------------------------------------------------------------------------
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Info "Installing uv..."
    Invoke-Expression (Invoke-RestMethod "https://astral.sh/uv/install.ps1")
    Update-SessionPath
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Err "uv was installed but isn't on PATH yet. Open a new terminal and re-run this script."
        exit 1
    }
} else {
    Ok "uv is already installed ($(uv --version))."
}

Info "Ensuring Python $PythonVersion is available (uv will install it if needed)..."
uv python install $PythonVersion
Assert-Success "uv python install $PythonVersion"

# ---------------------------------------------------------------------------
# 4. Directories
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
New-Item -ItemType Directory -Force -Path $InstallerMetaDir | Out-Null

# ---------------------------------------------------------------------------
# 4b. Template project ("Liven_Template" folder -> %LOCALAPPDATA%\projectifier)
# ---------------------------------------------------------------------------
if (Test-Path $TemplateSrc -PathType Container) {
    Info "Copying $TemplateName\ into $ConfigDir..."
    Remove-Item -Recurse -Force $TemplateDest -ErrorAction SilentlyContinue
    Copy-Item -Recurse -Force -Path $TemplateSrc -Destination $TemplateDest
    Ok "Template project installed at $TemplateDest"
} else {
    Warn "No '$TemplateName' folder found next to this script ($ScriptDir) — skipping template copy."
}

# ---------------------------------------------------------------------------
# 5. Fine-grained GitHub token (the repo is private)
# ---------------------------------------------------------------------------
$GithubToken = ""

if (Test-Path $CredFile) {
    $GithubToken = Get-Content $CredFile -Raw
    Ok "Found a saved GitHub access token."
} else {
    Warn "Repository $Repo is private — a GitHub Fine-grained Personal Access Token is required."
    Write-Host ""
    Info "Create one here: https://github.com/settings/personal-access-tokens/new"
    Info "  Resource owner:        $RepoOwner"
    Info "  Repository access:     Only select repositories -> $Repo"
    Info "  Permissions:            Repository permissions -> Contents: Read-only"
    Write-Host ""
    $secureToken = Read-Host "Paste your token (github_pat_...)" -AsSecureString
    $GithubToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
    )
    if ([string]::IsNullOrWhiteSpace($GithubToken)) {
        Err "No token entered. Can't clone a private repository without one."
        exit 1
    }
    Set-Content -Path $CredFile -Value $GithubToken -NoNewline
    # Restrict the credential file to the current user only (chmod 600 equivalent).
    icacls $CredFile /inheritance:r | Out-Null
    icacls $CredFile /grant:r "$($env:USERNAME):(R,W)" | Out-Null
    Ok "Token saved to $CredFile (access restricted to the current user)."
}

$AuthRepoUrl = "https://$GithubToken@github.com/$Repo.git"

Info "Verifying repository access with this token..."
git ls-remote $AuthRepoUrl *> $null
if ($LASTEXITCODE -ne 0) {
    Err "Could not access $Repo with this token."
    Err "Check that: (1) the token hasn't expired, (2) it grants access to this specific repo,"
    Err "(3) the 'Contents: Read-only' permission is enabled."
    Remove-Item -Force $CredFile -ErrorAction SilentlyContinue
    exit 1
}
Ok "Access verified."

# ---------------------------------------------------------------------------
# 6. Clone / update the repository (main branch only)
# ---------------------------------------------------------------------------
if (Test-Path (Join-Path $CodeDir ".git")) {
    Info "Updating existing checkout to the latest commit on $Branch..."
    git -C $CodeDir remote set-url origin $AuthRepoUrl
    Assert-Success "git remote set-url"
    git -C $CodeDir fetch origin $Branch --depth=1
    Assert-Success "git fetch"
    git -C $CodeDir checkout $Branch
    Assert-Success "git checkout $Branch"
    git -C $CodeDir reset --hard "origin/$Branch"
    Assert-Success "git reset --hard origin/$Branch"
} else {
    Info "Cloning repository (branch $Branch) into $CodeDir..."
    git clone --branch $Branch --single-branch --depth=1 $AuthRepoUrl $CodeDir
    Assert-Success "git clone"
}

$CurrentSha = (git -C $CodeDir rev-parse HEAD).Trim()
Set-Content -Path $ShaFile -Value $CurrentSha -NoNewline
Set-Content -Path $LastCheckFile -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -NoNewline
Ok "Installed commit: $($CurrentSha.Substring(0,7))"

# ---------------------------------------------------------------------------
# 7. Dependencies via uv (venv + resolution come from uv.lock, created
#    automatically inside $CodeDir\.venv)
# ---------------------------------------------------------------------------
Info "Installing dependencies via 'uv sync' (per pyproject.toml / uv.lock)..."
Push-Location $CodeDir
try {
    uv sync
    Assert-Success "uv sync"
} finally {
    Pop-Location
}
Ok "Dependencies installed."

# ---------------------------------------------------------------------------
# 7b. Tokens (tokens.zip -> %LOCALAPPDATA%\Programs\projectifier\projectifier\env)
# ---------------------------------------------------------------------------
if (Test-Path $TokensZip -PathType Leaf) {
    Info "Unpacking tokens.zip into $EnvDir..."
    New-Item -ItemType Directory -Force -Path $EnvDir | Out-Null
    Expand-Archive -Path $TokensZip -DestinationPath $EnvDir -Force
    # Restrict the env folder to the current user only (chmod 700/600 equivalent).
    icacls $EnvDir /inheritance:r | Out-Null
    icacls $EnvDir /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
    Ok "Tokens unpacked into $EnvDir"
} else {
    Warn "No 'tokens.zip' found next to this script ($ScriptDir) — skipping token extraction."
}

# ---------------------------------------------------------------------------
# 8. Wrapper command `prj` with self-update (prj.ps1 does the work,
#    prj.cmd is a thin shim so `prj` resolves from both cmd.exe and
#    PowerShell — PowerShell won't run a bare-name .ps1 from PATH, but it
#    will run a bare-name .cmd, same as npm's global-bin shims do).
# ---------------------------------------------------------------------------
$WrapperPs1 = Join-Path $BinDir "$CmdName.ps1"
$WrapperCmd = Join-Path $BinDir "$CmdName.cmd"

$wrapperContent = @"
# Auto-generated by install_2.ps1 for $Repo. Don't edit by hand —
# changes will be overwritten the next time install_2.ps1 runs.
`$ErrorActionPreference = "Stop"

`$CodeDir = "$CodeDir"
`$Branch = "$Branch"
`$Repo = "$Repo"
`$EntryPoint = "$EntryPoint"
`$ShaFile = "$ShaFile"
`$LastCheckFile = "$LastCheckFile"
`$CredFile = "$CredFile"
`$UpdateIntervalSeconds = $UpdateIntervalSeconds

function Self-Update {
    if (-not (Test-Path `$CredFile)) { return }
    `$token = Get-Content `$CredFile -Raw

    try {
        `$response = Invoke-RestMethod -Headers @{ Authorization = "token `$token" } ``
            -Uri "https://api.github.com/repos/`$Repo/commits/`$Branch" -ErrorAction Stop
        `$remoteSha = `$response.sha
    } catch {
        return
    }
    if ([string]::IsNullOrEmpty(`$remoteSha)) { return }

    `$localSha = if (Test-Path `$ShaFile) { Get-Content `$ShaFile -Raw } else { "" }

    if (`$remoteSha -ne `$localSha) {
        Write-Host "[$CmdName] New version found (`$(`$remoteSha.Substring(0,7))) — updating..."
        git -C `$CodeDir fetch origin `$Branch --depth=1 --quiet
        if (`$LASTEXITCODE -ne 0) { throw "git fetch failed (exit code `$LASTEXITCODE)" }
        git -C `$CodeDir reset --hard "origin/`$Branch" --quiet
        if (`$LASTEXITCODE -ne 0) { throw "git reset failed (exit code `$LASTEXITCODE)" }
        Push-Location `$CodeDir
        try {
            uv sync --quiet
            if (`$LASTEXITCODE -ne 0) { throw "uv sync failed (exit code `$LASTEXITCODE)" }
        } finally { Pop-Location }
        Set-Content -Path `$ShaFile -Value `$remoteSha -NoNewline
        Write-Host "[$CmdName] Updated to `$(`$remoteSha.Substring(0,7))."
    }
    Set-Content -Path `$LastCheckFile -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -NoNewline
}

`$forwardArgs = `$args
if (`$forwardArgs.Count -gt 0 -and `$forwardArgs[0] -eq "--update") {
    Self-Update
    `$forwardArgs = `$forwardArgs[1..(`$forwardArgs.Count - 1)]
    if (`$forwardArgs.Count -eq 0) { exit 0 }
}

`$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
`$lastCheck = if (Test-Path `$LastCheckFile) { [int64](Get-Content `$LastCheckFile -Raw) } else { 0 }
if ((`$now - `$lastCheck) -ge `$UpdateIntervalSeconds) {
    try { Self-Update } catch { }
}

# IMPORTANT: cd into `$CodeDir is required because main.py reads "env/.env"
# and "env/credentials.json" as paths relative to the current working directory.
Push-Location `$CodeDir
try {
    uv run `$EntryPoint @forwardArgs
} finally {
    Pop-Location
}
"@

Set-Content -Path $WrapperPs1 -Value $wrapperContent

$shimContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$CmdName.ps1" %*
"@
Set-Content -Path $WrapperCmd -Value $shimContent

Ok "Created the $CmdName command at $WrapperCmd"

# ---------------------------------------------------------------------------
# 9. Add BinDir to the user PATH (persisted via the registry — Windows has
#    no shell rc file to source; a new terminal picks it up automatically)
# ---------------------------------------------------------------------------
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ";") -notcontains $BinDir) {
    $newUserPath = if ([string]::IsNullOrEmpty($userPath)) { $BinDir } else { "$userPath;$BinDir" }
    [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    Ok "PATH updated (User scope) with $BinDir"
} else {
    Ok "$BinDir is already on PATH."
}
Update-SessionPath

# ---------------------------------------------------------------------------
# 10. Reminder about secrets that aren't part of the repo (they're gitignored)
# ---------------------------------------------------------------------------
Write-Host ""
Ok "Done! Installed $Repo ($Branch@$($CurrentSha.Substring(0,7)))."
Info "Open a new terminal, after which the '$CmdName' command will be available."
Info "To force an update check manually: $CmdName --update"
Write-Host ""

if (-not (Test-Path (Join-Path $EnvDir ".env"))) {
    Warn "$EnvDir\.env is missing (it's gitignored, so it doesn't come with the repo,"
    Warn "and no tokens.zip with it was found next to install_2.ps1)."
    Warn "Create it manually before the first run:"
    Warn "  New-Item -ItemType Directory -Force -Path '$EnvDir'"
    Warn "  Set-Content -Path '$EnvDir\.env' -Value 'TOKEN=<your Airtable Personal Access Token>'"
    Warn "If you use the Google Drive download feature ('Related creative' field),"
    Warn "you'll also need an OAuth client secret from Google Cloud Console at:"
    Warn "  $EnvDir\credentials.json"
}
