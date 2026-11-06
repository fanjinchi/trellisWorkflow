#Requires -Version 5.1
<#
.SYNOPSIS
  Install the "Matt x Trellis for DSH" environment on Windows.

.DESCRIPTION
  Installs/checks Trellis CLI, downloads Matt skills, creates model-visible
  DSH copies, installs the global rules, the init macro, the DSH skill, and
  patches the Trellis task_store.py template.

  Idempotent. Run from the repository root:
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1
#>
[CmdletBinding()]
param(
    [string]$TrellisVersion = "0.6.17",
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME ".dsh" }),
    [string]$AgentsHome = $(if ($env:AGENTS_HOME) { $env:AGENTS_HOME } else { Join-Path $HOME ".agents" }),
    [string]$BinDir = $(Join-Path $HOME ".local\bin")
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$RepoDir = Split-Path -Parent $PSScriptRoot

function Write-Say { param([string]$Message) Write-Host $Message }
function Write-Warn { param([string]$Message) Write-Warning $Message }
function Write-Die { param([string]$Message) Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }
function Write-Step { param([string]$Message) Write-Host ""; Write-Host "== $Message ==" }

foreach ($cmd in @("git", "node", "npm")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Write-Die "$cmd is required" }
}

$Python = $null
$PythonArgs = @()
if (Get-Command python -ErrorAction SilentlyContinue) {
    $Python = "python"
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    $Python = "py"
    $PythonArgs = @("-3")
} else {
    Write-Die "Python 3 is required"
}

Write-Step "1/7 Trellis CLI"
$trellisCmd = Get-Command trellis -ErrorAction SilentlyContinue
if ($trellisCmd) {
    $current = (& trellis --version | Select-Object -Last 1)
    if ($current -match '(\d+\.\d+\.\d+)') { $current = $Matches[1] }
    if ($current -and ([version]$current -ge [version]$TrellisVersion)) {
        if ($current -eq $TrellisVersion) {
            Write-Say "OK: trellis $current"
        } else {
            Write-Warn "trellis $current is newer than the tested $TrellisVersion; continuing"
        }
    } else {
        Write-Say "Upgrading trellis $current -> $TrellisVersion"
        & npm install -g "@mindfoldhq/trellis@$TrellisVersion"
        if ($LASTEXITCODE -ne 0) { Write-Die "npm global install failed" }
    }
} else {
    Write-Say "Installing trellis $TrellisVersion"
    & npm install -g "@mindfoldhq/trellis@$TrellisVersion"
    if ($LASTEXITCODE -ne 0) { Write-Die "npm global install failed" }
}
if (-not (Get-Command trellis -ErrorAction SilentlyContinue)) {
    Write-Die "trellis is still not on PATH; add the npm global bin directory to PATH and retry"
}

Write-Step "2/7 Matt skills"
$env:DSH_HOME = $DshHome
$env:AGENTS_HOME = $AgentsHome
& (Join-Path $PSScriptRoot "sync-matt-skills.ps1")
if ($LASTEXITCODE -ne 0) { Write-Die "Matt skills sync failed" }

Write-Step "3/7 Global rules"
New-Item -ItemType Directory -Force -Path $DshHome | Out-Null
$srcAgents = Join-Path $RepoDir "dsh\AGENTS.md"
$dstAgents = Join-Path $DshHome "AGENTS.md"
if ((Test-Path $dstAgents) -and ((Get-FileHash $srcAgents).Hash -ne (Get-FileHash $dstAgents).Hash)) {
    $backup = "$dstAgents.bak." + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item $dstAgents $backup
    Write-Say "Backed up existing global rules to $backup"
}
Copy-Item -Force $srcAgents $dstAgents
Write-Say "OK: $dstAgents"

Write-Step "4/7 Macro and helper scripts"
$scriptsDir = Join-Path $DshHome "scripts"
New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
Copy-Item -Force (Join-Path $RepoDir "scripts\trellis-matt-init.ps1") $scriptsDir
Copy-Item -Force (Join-Path $RepoDir "scripts\sync-matt-skills.ps1") $scriptsDir
Copy-Item -Force (Join-Path $RepoDir "scripts\patch-task-store.py") $scriptsDir
Copy-Item -Force (Join-Path $RepoDir "scripts\win-fallback.mjs") $scriptsDir
Copy-Item -Force (Join-Path $RepoDir "workflows\matt\workflow.md") (Join-Path $scriptsDir "trellis-workflow-matt.md")
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
if ($DshHome.TrimEnd('\') -eq (Join-Path $HOME ".dsh").TrimEnd('\')) {
    # %USERPROFILE% keeps the generated .cmd pure ASCII (Chinese user names).
    $ps1Path = "%USERPROFILE%\.dsh\scripts\trellis-matt-init.ps1"
    $mjsPath = "%USERPROFILE%\.dsh\scripts\win-fallback.mjs"
} else {
    $ps1Path = Join-Path $scriptsDir "trellis-matt-init.ps1"
    $mjsPath = Join-Path $scriptsDir "win-fallback.mjs"
}
$cmdLines = @(
    "@echo off",
    "setlocal EnableExtensions",
    "rem Try PowerShell first; fall back to Node when PowerShell is blocked",
    "rem (ExecutionPolicy, AppLocker, Constrained Language Mode).",
    "rem Force the Node path with:  set TRELLIS_NO_POWERSHELL=1",
    'if /i "%TRELLIS_NO_POWERSHELL%"=="1" goto :node',
    "where powershell >nul 2>nul",
    "if errorlevel 1 goto :nops",
    "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ps1Path`" %*",
    "if not errorlevel 1 exit /b 0",
    "echo.",
    "echo [!] PowerShell failed; falling back to Node.",
    "goto :node",
    ":nops",
    "echo [!] PowerShell not found; using Node.",
    ":node",
    "where node >nul 2>nul",
    "if errorlevel 1 (",
    "  echo ERROR: PowerShell is unavailable and Node was not found.",
    "  exit /b 1",
    ")",
    "node `"$mjsPath`" init %*",
    "exit /b %ERRORLEVEL%"
)
$cmdText = ($cmdLines -join "`r`n") + "`r`n"
$ansi = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
[IO.File]::WriteAllText((Join-Path $BinDir "trellis-matt-init.cmd"), $cmdText, $ansi)
Write-Say "OK: $scriptsDir"
Write-Say "OK: $(Join-Path $BinDir 'trellis-matt-init.cmd')"
if (($env:PATH -split ';') -notcontains $BinDir) {
    Write-Warn "$BinDir is not on PATH; run the .cmd by full path or add that directory to PATH"
}

Write-Step "5/7 DSH skill"
$skillDir = Join-Path $DshHome "skills\trellis-matt-init"
New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
Copy-Item -Force (Join-Path $RepoDir "dsh\skills\trellis-matt-init\SKILL.md") $skillDir
Write-Say "OK: $(Join-Path $skillDir 'SKILL.md')"

Write-Step "6/7 Trellis template patch"
$npmRoot = (& npm root -g | Select-Object -Last 1).Trim()
$taskStore = $null
if ($npmRoot) {
    $taskStore = Join-Path $npmRoot "@mindfoldhq\trellis\dist\templates\trellis\scripts\common\task_store.py"
}
if ($taskStore -and (Test-Path $taskStore)) {
    & $Python @PythonArgs (Join-Path $RepoDir "scripts\patch-task-store.py") $taskStore
    if ($LASTEXITCODE -ne 0) { Write-Warn "Template patch failed: $taskStore" }
} else {
    Write-Warn "task_store.py template not found: $taskStore"
}

Write-Step "7/7 Verify"
$fail = $false
if (-not (Get-Command trellis -ErrorAction SilentlyContinue)) { Write-Warn "trellis is not available"; $fail = $true }
& (Join-Path $PSScriptRoot "sync-matt-skills.ps1") -Check
if ($LASTEXITCODE -ne 0) { Write-Warn "Matt skills are incomplete"; $fail = $true }
if (-not (Test-Path $dstAgents)) { Write-Warn "Missing $dstAgents"; $fail = $true }
if (-not (Test-Path (Join-Path $BinDir "trellis-matt-init.cmd"))) { Write-Warn "Missing trellis-matt-init.cmd"; $fail = $true }
if (-not (Test-Path (Join-Path $skillDir "SKILL.md"))) { Write-Warn "Missing DSH skill"; $fail = $true }
if (-not (Test-Path (Join-Path $scriptsDir "trellis-workflow-matt.md"))) { Write-Warn "Missing local workflow cache"; $fail = $true }
if (-not (Test-Path (Join-Path $scriptsDir "win-fallback.mjs"))) { Write-Warn "Missing Node fallback"; $fail = $true }
if ($taskStore -and (Test-Path $taskStore)) {
    & $Python @PythonArgs (Join-Path $RepoDir "scripts\patch-task-store.py") --check $taskStore | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warn "Trellis template is not patched"; $fail = $true }
}
if ($fail) { Write-Die "Installation did not fully pass; fix the warnings above" }

Write-Host ""
Write-Host "OK: environment installed"
Write-Host ""
Write-Host "Next:"
Write-Host "  1. Initialize a project: cd <project>; trellis-matt-init.cmd -User <your-name>"
Write-Host "  2. Or ask dsh: 'initialize this project with my workflow'"
Write-Host "  3. Default source: gh:fanjinchi/trellisWorkflow (use -Source for a fork)"
Write-Host "  4. Update Matt skills: powershell -File $scriptsDir\sync-matt-skills.ps1"
