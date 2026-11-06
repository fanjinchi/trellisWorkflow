#Requires -Version 5.1
<#
.SYNOPSIS
  Download Matt skills and generate model-visible copies for DSH on Windows.

.DESCRIPTION
  DSH hides skills whose frontmatter contains "disable-model-invocation: true".
  The workflow needs 12 such skills, so this script copies them into
  %USERPROFILE%\.dsh\skills and removes that line. The other 11 skills are
  discovered directly from %USERPROFILE%\.agents\skills.

  Idempotent. Run with -Check to verify without network access.
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$AgentsHome = if ($env:AGENTS_HOME) { $env:AGENTS_HOME } else { Join-Path $HOME ".agents" }
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME ".dsh" }
$MattRepo = if ($env:MATT_REPO) { $env:MATT_REPO } else { "https://github.com/mattpocock/skills.git" }
$MattRef = if ($env:MATT_REF) { $env:MATT_REF } else { "main" }

$MattSkills = @(
    "ask-matt", "codebase-design", "code-review", "diagnosing-bugs",
    "domain-modeling", "grill-me", "grill-with-docs", "grilling",
    "handoff", "implement", "implement-spec", "improve-codebase-architecture",
    "pr", "prototype", "research", "retro", "setup-matt-pocock-skills",
    "tdd", "to-spec", "to-tickets", "triage", "wayfinder", "writing-for-agents"
)

$DshVisible = @(
    "ask-matt", "grill-me", "grill-with-docs", "handoff", "implement",
    "implement-spec", "improve-codebase-architecture", "retro",
    "to-spec", "to-tickets", "triage", "wayfinder"
)

function Write-Say { param([string]$Message) Write-Host $Message }
function Write-Warn { param([string]$Message) Write-Warning $Message }
function Write-Die { param([string]$Message) Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

function Remove-ModelInvocationFlag {
    param([string]$Path)
    $lines = [IO.File]::ReadAllLines($Path)
    [string[]]$kept = @($lines | Where-Object { $_ -notmatch '^disable-model-invocation:\s*true\s*$' })
    [IO.File]::WriteAllLines($Path, $kept, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-State {
    $missing = 0
    $flagged = 0
    foreach ($name in $MattSkills) {
        $p = Join-Path $AgentsHome "skills\$name\SKILL.md"
        if (-not (Test-Path $p)) { Write-Warn "Missing $p"; $missing++ }
    }
    foreach ($name in $DshVisible) {
        $p = Join-Path $DshHome "skills\$name\SKILL.md"
        if (-not (Test-Path $p)) {
            Write-Warn "Missing $p"
            $missing++
        } elseif (Select-String -Path $p -Pattern '^disable-model-invocation:\s*true\s*$' -Quiet) {
            Write-Warn "$p still hides the skill from the model"
            $flagged++
        }
    }
    if ($missing -eq 0 -and $flagged -eq 0) {
        Write-Say "OK: Matt skills and DSH copies are complete"
        return $true
    }
    return $false
}

if ($Check) {
    if (Test-State) { exit 0 } else { exit 1 }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Die "git is required" }
New-Item -ItemType Directory -Force -Path (Join-Path $AgentsHome "skills") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DshHome "skills") | Out-Null

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("matt-skills-" + [guid]::NewGuid().ToString("N"))
try {
    Write-Say "Downloading Matt skills ($MattRef)..."
    & git clone --depth 1 --branch $MattRef $MattRepo $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Die "git clone failed: $MattRepo" }

    $copied = 0
    foreach ($name in $MattSkills) {
        $skillMd = Get-ChildItem -Path (Join-Path $tmp "skills") -Recurse -Filter "SKILL.md" -ErrorAction SilentlyContinue |
            Where-Object { $_.Directory.Name -eq $name } |
            Select-Object -First 1
        if (-not $skillMd) {
            Write-Warn "Skill not found upstream: $name (skipped)"
            continue
        }
        $dst = Join-Path $AgentsHome "skills\$name"
        if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
        Copy-Item -Path $skillMd.Directory.FullName -Destination $dst -Recurse -Force
        $copied++
    }
    Write-Say "Installed $copied Matt skills into $AgentsHome\skills"

    foreach ($name in $DshVisible) {
        $src = Join-Path $AgentsHome "skills\$name"
        if (-not (Test-Path (Join-Path $src "SKILL.md"))) {
            Write-Warn "$name is not installed; cannot create the DSH copy"
            continue
        }
        $dst = Join-Path $DshHome "skills\$name"
        if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
        Copy-Item -Path $src -Destination $dst -Recurse -Force
        Remove-ModelInvocationFlag (Join-Path $dst "SKILL.md")
    }
    Write-Say "Generated $($DshVisible.Count) model-visible DSH copies in $DshHome\skills"
} finally {
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}

if (-not (Test-State)) { exit 1 }
