# Installs the custom Claude Code statusline on Windows.
# Requires Git for Windows (for bash.exe) — https://git-scm.com/download/win
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$StatuslineSrc = Join-Path $ScriptDir "statusline-command.sh"
$StatuslineDest = Join-Path $ClaudeDir "statusline-command.sh"
$SettingsPath = Join-Path $ClaudeDir "settings.json"

Write-Host "Installing Claude Code statusline into $ClaudeDir ..."
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
Copy-Item -Path $StatuslineSrc -Destination $StatuslineDest -Force

# --- find a bash.exe (Git for Windows) ---
$BashCmd = Get-Command bash.exe -ErrorAction SilentlyContinue
if ($BashCmd) {
    $BashPath = $BashCmd.Source
} else {
    $Candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LocalAppData\Programs\Git\bin\bash.exe"
    )
    $BashPath = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $BashPath) {
    Write-Error "Could not find bash.exe. Install Git for Windows (https://git-scm.com/download/win), then re-run this script."
    exit 1
}
Write-Host "Using bash: $BashPath"

# --- ensure jq is available ---
$JqCmd = Get-Command jq.exe -ErrorAction SilentlyContinue
if (-not $JqCmd) { $JqCmd = Get-Command jq -ErrorAction SilentlyContinue }
if (-not $JqCmd) {
    Write-Host "jq not found — attempting to install it..."
    $Winget = Get-Command winget -ErrorAction SilentlyContinue
    $Choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($Winget) {
        winget install -e --id jqlang.jq --accept-package-agreements --accept-source-agreements
    } elseif ($Choco) {
        choco install jq -y
    } else {
        Write-Warning "Could not detect winget or choco. Install jq manually (https://jqlang.org/download/) and ensure jq.exe is on PATH, then re-run this script."
        exit 1
    }
}

# --- convert the Windows script path to the /c/... form bash.exe expects ---
$UnixPath = "/" + $StatuslineDest.Substring(0,1).ToLower() + $StatuslineDest.Substring(2).Replace('\', '/')
$Command = "`"$BashPath`" `"$UnixPath`""

# --- merge (not overwrite) the statusLine key into settings.json ---
if (Test-Path $SettingsPath) {
    $Json = Get-Content $SettingsPath -Raw | ConvertFrom-Json
} else {
    $Json = [PSCustomObject]@{}
}

$StatusLineObj = [PSCustomObject]@{ type = "command"; command = $Command }
if ($Json.PSObject.Properties.Name -contains "statusLine") {
    $Json.statusLine = $StatusLineObj
} else {
    $Json | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $StatusLineObj -Force
}
$Json | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsPath -Encoding utf8

Write-Host "Done. Statusline installed at $StatuslineDest"
Write-Host "settings.json updated at $SettingsPath (other keys preserved)."
Write-Host "Restart Claude Code (or start a new session) to see it."
