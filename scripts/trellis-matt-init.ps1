#Requires -Version 5.1
<#
.SYNOPSIS
  Initialize the current project with the Matt x Trellis workflow on Windows.

.DESCRIPTION
  Uses the workflow cached by install.ps1 by default (offline). Pass -Refresh
  or -Source to fetch from GitHub. Falls back to a direct download when the
  marketplace is slow, and to the local cache when the network is unavailable.

  Examples:
    trellis-matt-init.cmd -User alice
    trellis-matt-init.cmd -User alice -Refresh
    trellis-matt-init.cmd -User alice -Source gh:me/fork
    trellis-matt-init.cmd -User alice -Force
#>
[CmdletBinding()]
param(
    [string]$User,
    [string]$Source = "gh:fanjinchi/trellisWorkflow",
    [string]$Template = "matt",
    [switch]$Force,
    [switch]$Refresh
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$SourceGiven = $PSBoundParameters.ContainsKey("Source")
$UserGiven = $PSBoundParameters.ContainsKey("User")
$Marker = "Single-source rule (every planning artifact"
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME ".dsh" }
$LocalWorkflow = if ($env:TRELLIS_WORKFLOW_CACHE) { $env:TRELLIS_WORKFLOW_CACHE } else { Join-Path $DshHome "scripts\trellis-workflow-matt.md" }
$SourceLabel = $Source

function Write-Say { param([string]$Message) Write-Host $Message }
function Write-Warn { param([string]$Message) Write-Warning $Message }
function Write-Die { param([string]$Message) Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

function Test-MattWorkflow {
    if (-not (Test-Path ".trellis\workflow.md")) { return $false }
    return [bool](Select-String -Path ".trellis\workflow.md" -SimpleMatch -Pattern $Marker -Quiet)
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
if (-not (Get-Command trellis -ErrorAction SilentlyContinue)) {
    Write-Die "trellis not found; run scripts\install.ps1 first"
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { Set-Location $gitRoot }
}
$ProjectRoot = (Get-Location).Path

if (-not $User) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $User = (& git config user.name 2>$null | Select-Object -First 1)
    }
    if (-not $User) { $User = $env:USERNAME }
}
$User = ([string]$User).Trim()
if (-not $User) { $User = "developer" }

if (-not (Test-Path ".git")) {
    Write-Warn "Current directory is not a git repository; workflow Phase 3.4 needs commits"
}

$devFile = ".trellis\.developer"
if (Test-Path $devFile) {
    $line = Get-Content $devFile | Where-Object { $_ -match '^name=' } | Select-Object -First 1
    if ($line) {
        $currentDev = $line.Substring(5).Trim()
        if ($UserGiven -and $currentDev -ne $User) {
            Write-Warn "Project already has developer '$currentDev'; -User only applies on first init. Delete .trellis\.developer to change it."
        }
        $User = $currentDev
    }
}

$RawBase = $null
if ($Source -match '^(gh|github):(.+)$') {
    $repo = $Matches[2]
    $ref = "main"
    if ($repo -match '#(.+)$') {
        $ref = $Matches[1]
        $repo = $repo -replace '#.+$', ''
    }
    $RawBase = "https://raw.githubusercontent.com/$repo/$ref"
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("trellis-matt-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Get-WorkflowFile {
    if (-not $RawBase) { return $false }
    $index = Join-Path $tmp "index.json"
    $path = $null
    for ($i = 0; $i -lt 3; $i++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$RawBase/index.json" -OutFile $index -TimeoutSec 30
            $data = Get-Content $index -Raw | ConvertFrom-Json
            $entry = $data.templates | Where-Object { $_.id -eq $Template -and $_.type -eq "workflow" } | Select-Object -First 1
            if ($entry) { $path = $entry.path }
            break
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    if (-not $path) { $path = "workflows/$Template/workflow.md" }
    Write-Say "Fallback: downloading $RawBase/$path"
    for ($i = 0; $i -lt 3; $i++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$RawBase/$path" -OutFile (Join-Path $tmp "workflow.md") -TimeoutSec 60
            if (Test-Path (Join-Path $tmp "workflow.md")) { return $true }
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

function Install-WorkflowFile {
    Copy-Item -Force (Join-Path $tmp "workflow.md") ".trellis\workflow.md"
    $hashPath = ".trellis\.template-hashes.json"
    if (Test-Path $hashPath) {
        $data = Get-Content $hashPath -Raw | ConvertFrom-Json
        if ($data.hashes -and ($data.hashes.PSObject.Properties.Name -contains ".trellis/workflow.md")) {
            $data.hashes.PSObject.Properties.Remove(".trellis/workflow.md")
        }
        $json = $data | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText((Resolve-Path $hashPath).Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    }
}

function Cache-Workflow {
    if ($SourceGiven -or $Template -ne "matt") { return }
    if (-not (Test-Path ".trellis\workflow.md")) { return }
    $dir = Split-Path -Parent $LocalWorkflow
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -Force ".trellis\workflow.md" $LocalWorkflow
}

function Use-LocalWorkflow {
    if ($Template -ne "matt" -or -not (Test-Path $LocalWorkflow)) { return $false }
    Copy-Item -Force $LocalWorkflow (Join-Path $tmp "workflow.md")
    Install-WorkflowFile
    $script:SourceLabel = "local cache"
    Write-Say "Using local cached workflow: $LocalWorkflow"
    return $true
}

function Invoke-Init {
    if (-not $Refresh -and -not $SourceGiven -and $Template -eq "matt" -and (Test-Path $LocalWorkflow)) {
        Write-Say "trellis init (offline, local cache)"
        & trellis init --dsh --yes --user $User
        if ($LASTEXITCODE -ne 0) { Write-Die "trellis init failed" }
        Copy-Item -Force $LocalWorkflow (Join-Path $tmp "workflow.md")
        Install-WorkflowFile
        $script:SourceLabel = "local cache"
        return
    }

    $ok = $false
    for ($i = 1; $i -le 3; $i++) {
        Write-Say "trellis init (attempt $i/3, marketplace: $Source)"
        & trellis init --dsh --yes --user $User --workflow $Template --workflow-source $Source
        if ($LASTEXITCODE -eq 0) {
            if ($Template -ne "matt" -or (Test-MattWorkflow)) {
                $ok = $true
                break
            }
            Write-Warn "init succeeded but workflow is not the Matt template"
        }
        Write-Warn "attempt $i failed"
        Start-Sleep -Seconds 2
    }
    if ($ok) { Cache-Workflow; return }

    Write-Warn "marketplace failed; falling back to native init + direct download"
    & trellis init --dsh --yes --user $User
    if ($LASTEXITCODE -ne 0) { Write-Die "trellis init failed" }
    if (Get-WorkflowFile) { Install-WorkflowFile; Cache-Workflow; return }
    if (Test-Path $LocalWorkflow) {
        Write-Warn "network unavailable; using local cache"
        Copy-Item -Force $LocalWorkflow (Join-Path $tmp "workflow.md")
        Install-WorkflowFile
        $script:SourceLabel = "local cache"
        return
    }
    Write-Die "Could not download workflow.md and no local cache exists."
}

function Invoke-Switch {
    if (-not $Refresh -and -not $SourceGiven -and $Template -eq "matt" -and (Test-Path $LocalWorkflow)) {
        Use-LocalWorkflow | Out-Null
        return
    }
    Write-Say "Switching workflow to $Template (marketplace: $Source)"
    & trellis workflow --marketplace $Source --template $Template --force
    if ($LASTEXITCODE -eq 0) {
        if ($Template -ne "matt" -or (Test-MattWorkflow)) {
            Cache-Workflow
            return
        }
        Write-Warn "switch succeeded but content is not the Matt template"
    }
    Write-Warn "marketplace switch failed; falling back to direct download"
    if (Get-WorkflowFile) { Install-WorkflowFile; Cache-Workflow; return }
    if (Test-Path $LocalWorkflow) {
        Write-Warn "network unavailable; using local cache"
        Copy-Item -Force $LocalWorkflow (Join-Path $tmp "workflow.md")
        Install-WorkflowFile
        $script:SourceLabel = "local cache"
        return
    }
    Write-Die "Could not download workflow.md and no local cache exists."
}

function Refresh-DshEntry {
    $f = ".dsh\skills\trellis-start\SKILL.md"
    if (-not (Test-Path $f)) { return }
    $s = [IO.File]::ReadAllText($f)
    $new = $s.Replace('| Done coding / quality check | `trellis-check` |', '| Done coding / quality check | `code-review` |')
    if ($new -ne $s) {
        [IO.File]::WriteAllText($f, $new, (New-Object System.Text.UTF8Encoding($false)))
    }
}

function Patch-TaskStore {
    $target = ".trellis\scripts\common\task_store.py"
    if (-not (Test-Path $target)) { return }
    $patch = Join-Path $PSScriptRoot "patch-task-store.py"
    if (Test-Path $patch) {
        & $Python @PythonArgs $patch $target | Out-Null
    } else {
        Write-Warn "patch-task-store.py not found; skipping parent pointer patch"
    }
}

function Verify-Workflow {
    if (-not (Test-Path ".trellis\workflow.md")) { Write-Die "workflow.md is missing" }
    if ($script:ExpectMatt -and $Template -eq "matt" -and -not (Test-MattWorkflow)) {
        Write-Die "workflow.md is not the Matt template"
    }
    & $Python @PythonArgs ".trellis\scripts\get_context.py" --mode phase | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Die "get_context.py cannot parse workflow.md" }
}

try {
    Write-Say "Project: $ProjectRoot"
    Write-Say "Developer: $User (first init only; -User sets .trellis\.developer)"

    $script:ExpectMatt = $false
    if ((Test-Path ".trellis\workflow.md") -and -not $Force) {
        Write-Say "Existing workflow kept (use -Force to switch)"
        if ($Template -eq "matt" -and -not (Test-MattWorkflow)) {
            Write-Warn "Current workflow is not the Matt version; use -Force to switch"
        }
    } else {
        $script:ExpectMatt = $true
        if (Test-Path ".trellis\workflow.md") { Invoke-Switch } else { Invoke-Init }
    }

    Refresh-DshEntry
    Patch-TaskStore
    Verify-Workflow

    Write-Host ""
    Write-Host "OK: initialization complete"
    Write-Host "   .trellis/workflow.md -> $Template (source: $SourceLabel)"
    Write-Host "   .trellis/.developer  -> $User"
    Write-Host "   Next: start dsh in this directory; the global rule loads trellis-start first."
} finally {
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}
