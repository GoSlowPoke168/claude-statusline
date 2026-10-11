# Installs the custom Claude Code statusline on Windows using a native PowerShell
# script — no Git for Windows, bash.exe, or jq required.
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1 [-WaterSession] [-WaterLifetime] [-WaterEquivalents]
#    or: irm https://raw.githubusercontent.com/GoSlowPoke168/claude-statusline/master/install.ps1 | iex
param([switch]$WaterSession, [switch]$WaterLifetime, [switch]$WaterEquivalents)

$ErrorActionPreference = "Stop"

# Empty when run via irm | iex, in which case files are downloaded from GitHub instead of copied
$ScriptDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { "" }
$RawUrl = "https://raw.githubusercontent.com/GoSlowPoke168/claude-statusline/master"
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$StatuslineDest = Join-Path $ClaudeDir "statusline-command.ps1"
$SettingsPath = Join-Path $ClaudeDir "settings.json"

function Install-File([string]$name) {
    $dest = Join-Path $ClaudeDir $name
    if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir $name))) { Copy-Item -Path (Join-Path $ScriptDir $name) -Destination $dest -Force }
    else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri "$RawUrl/$name" -OutFile $dest
    }
}

Write-Host "Installing Claude Code statusline into $ClaudeDir ..."
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
Install-File "statusline-command.ps1"
foreach ($f in "water.ps1", "water-facts.txt", "water-prices.txt") {
    if ($WaterSession -or $WaterLifetime -or $WaterEquivalents) { Install-File $f }
    else { Remove-Item -Path (Join-Path $ClaudeDir $f) -ErrorAction SilentlyContinue }
}
if (-not ($WaterSession -or $WaterLifetime -or $WaterEquivalents)) { Remove-Item -Path (Join-Path $ClaudeDir "water-learned-prices.txt") -ErrorAction SilentlyContinue }

# Prefer PowerShell 7+ (pwsh) if present for better Unicode/emoji handling,
# otherwise fall back to the Windows PowerShell that ships with every Windows install.
$PwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$ShellExe = if ($PwshCmd) { $PwshCmd.Source } else { (Get-Command powershell.exe).Source }

$Command = "`"$ShellExe`" -NoProfile -ExecutionPolicy Bypass -File `"$StatuslineDest`""
if ($WaterSession) { $Command += " -WaterSession" }
if ($WaterLifetime) { $Command += " -WaterLifetime" }
if ($WaterEquivalents) { $Command += " -WaterEquivalents" }

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
