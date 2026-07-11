# Installs the custom Claude Code statusline on Windows using a native PowerShell
# script — no Git for Windows, bash.exe, or jq required.
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$StatuslineSrc = Join-Path $ScriptDir "statusline-command.ps1"
$StatuslineDest = Join-Path $ClaudeDir "statusline-command.ps1"
$SettingsPath = Join-Path $ClaudeDir "settings.json"

Write-Host "Installing Claude Code statusline into $ClaudeDir ..."
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
Copy-Item -Path $StatuslineSrc -Destination $StatuslineDest -Force

# Prefer PowerShell 7+ (pwsh) if present for better Unicode/emoji handling,
# otherwise fall back to the Windows PowerShell that ships with every Windows install.
$PwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$ShellExe = if ($PwshCmd) { $PwshCmd.Source } else { (Get-Command powershell.exe).Source }

$Command = "`"$ShellExe`" -NoProfile -ExecutionPolicy Bypass -File `"$StatuslineDest`""

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
Write-Host "Note: the branch segment needs git.exe on PATH; everything else has no external dependency."
Write-Host "Restart Claude Code (or start a new session) to see it."
