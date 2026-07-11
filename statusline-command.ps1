# Claude Code status line: native PowerShell port (no bash, no jq, no Git for Windows required).
# Only git.exe on PATH is used, and only for the "current branch" segment.

$inputJson = [Console]::In.ReadToEnd()
$data = $inputJson | ConvertFrom-Json

$RESET = "`e[0m"
$SEP = "`e[38;2;110;110;110m"
$PIPE = "$SEP | $RESET"

function Color-At([double]$p) {
    if ($p -le 50) {
        $f = $p / 50.0
        $r = [math]::Round(0 + (220 - 0) * $f)
        $g = [math]::Round(200 + (200 - 200) * $f)
        $b = [math]::Round(80 + (0 - 80) * $f)
    } else {
        $f = ($p - 50) / 50.0
        $r = [math]::Round(220 + (220 - 220) * $f)
        $g = [math]::Round(200 + (40 - 200) * $f)
        $b = [math]::Round(0 + (20 - 0) * $f)
    }
    return @($r, $g, $b)
}

# --- model + effort ---
$model = $data.model.display_name
if (-not $model) { $model = "unknown" }
$effort = $data.effort.level
$C_MODEL = "`e[1;38;2;217;119;87m"
$C_EFFORT = "`e[38;2;217;119;87m"
if ($effort) {
    $segModel = "$C_MODEL$model$RESET $C_EFFORT($effort)$RESET"
} else {
    $segModel = "$C_MODEL$model$RESET"
}

# --- thinking on/off ---
$segThinking = ""
if ($null -ne $data.thinking.enabled) {
    if ($data.thinking.enabled) {
        $segThinking = "`e[38;2;180;130;255mthinking: on$RESET"
    } else {
        $segThinking = "`e[38;2;120;120;120mthinking: off$RESET"
    }
}

# --- mode ---
$segMode = ""
if ($data.output_style.name) { $segMode = "`e[38;2;180;220;180m$($data.output_style.name)$RESET" }

# --- context usage bar ---
$usedPct = $data.context_window.used_percentage
if (-not $usedPct) { $usedPct = 0 }
$blocks = 20
$filled = [int][math]::Round(($usedPct / 100.0) * $blocks)
if ($filled -gt $blocks) { $filled = $blocks }
if ($filled -lt 0) { $filled = 0 }
$bar = ""
for ($i = 1; $i -le $blocks; $i++) {
    if ($i -le $filled) {
        $pos = (($i - 1) / ($blocks - 1)) * 100
        $rgb = Color-At $pos
        $bar += "`e[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$([char]0x2588)"
    } else {
        $bar += "`e[38;2;60;60;60m$([char]0x2588)"
    }
}
$bar += $RESET

if ($usedPct -lt 20) { $usageEmoji = "$([char]0xD83D)$([char]0xDFE2)" }        # 🟢
elseif ($usedPct -lt 70) { $usageEmoji = "$([char]0x26A1)" }                  # ⚡
elseif ($usedPct -lt 90) { $usageEmoji = "$([char]0xD83D)$([char]0xDD25)" }   # 🔥
else { $usageEmoji = "$([char]0xD83D)$([char]0xDEA8)" }                       # 🚨

$pctRgb = Color-At $usedPct
$pctStr = "{0:N0}%" -f $usedPct
$segCtx = "$bar $usageEmoji `e[1;38;2;$($pctRgb[0]);$($pctRgb[1]);$($pctRgb[2])m$pctStr$RESET"

# --- session cost ---
$segCost = ""
if ($null -ne $data.cost.total_cost_usd) {
    $costStr = '$' + ("{0:N2}" -f $data.cost.total_cost_usd)
    $segCost = "`e[38;2;220;200;0m$costStr$RESET"
}

# --- code velocity ---
$added = $data.cost.total_lines_added
$removed = $data.cost.total_lines_removed
$segVelocity = ""
if (($null -ne $added) -or ($null -ne $removed)) {
    if ($null -eq $added) { $added = 0 }
    if ($null -eq $removed) { $removed = 0 }
    $segVelocity = "`e[38;2;0;200;80m+$added$RESET `e[38;2;220;40;20m-$removed$RESET"
}

# --- rate limits ---
function Circle-Glyph([double]$p) {
    if ($p -lt 20) { return [char]0x25CB }       # ○
    elseif ($p -lt 40) { return [char]0x25D4 }   # ◔
    elseif ($p -lt 60) { return [char]0x25D1 }   # ◑
    elseif ($p -lt 80) { return [char]0x25D5 }   # ◕
    else { return [char]0x25CF }                 # ●
}

$C_RL = "`e[38;2;120;200;255m"
$segRatelimit = ""
$fiveHPct = $data.rate_limits.five_hour.used_percentage
if ($null -ne $fiveHPct) {
    $fiveHStr = "{0:N0}%" -f $fiveHPct
    $fiveHGlyph = Circle-Glyph $fiveHPct
    $resetStr = ""
    $fiveHReset = $data.rate_limits.five_hour.resets_at
    if ($fiveHReset) {
        try {
            $localTime = [DateTimeOffset]::FromUnixTimeSeconds([int64]$fiveHReset).ToLocalTime().ToString("h:mm tt")
            $resetStr = " (resets $localTime)"
        } catch { }
    }
    $segRatelimit = "${C_RL}5h: $fiveHGlyph $fiveHStr$resetStr$RESET"
}
$sevenDPct = $data.rate_limits.seven_day.used_percentage
if ($null -ne $sevenDPct) {
    $sevenDStr = "{0:N0}%" -f $sevenDPct
    $sevenDGlyph = Circle-Glyph $sevenDPct
    if ($segRatelimit) { $segRatelimit += $PIPE }
    $segRatelimit += "${C_RL}7d: $sevenDGlyph $sevenDStr$RESET"
}

# --- assemble line 1 ---
$line1 = $segModel
if ($segThinking) { $line1 += "$PIPE$segThinking" }
if ($segMode) { $line1 += "$PIPE$segMode" }
$line1 += "$PIPE$segCtx"
if ($segCost) { $line1 += "$PIPE$segCost" }
if ($segVelocity) { $line1 += "$PIPE$segVelocity" }
if ($segRatelimit) { $line1 += "$PIPE$segRatelimit" }

# --- line 2: cwd | branch | git worktree | worktree original branch ---
$cwd = $data.workspace.current_dir
if (-not $cwd) { $cwd = (Get-Location).Path }
$C_DIR = "`e[38;2;150;200;255m"
$segDir = "${C_DIR}$([char]0xD83D)$([char]0xDCC1) $cwd$RESET"   # 📁

$gitWorktree = $data.workspace.git_worktree
$segGitWorktree = ""
if ($gitWorktree) { $segGitWorktree = "`e[38;2;0;220;220m$([char]0xD83C)$([char]0xDF3F) $gitWorktree$RESET" }  # 🌿

$origBranch = $data.worktree.original_branch
$segOrigBranch = ""
if ($origBranch) { $segOrigBranch = "`e[38;2;220;180;0m$([char]0x2190) $origBranch$RESET" }  # ←

# plain current git branch — only shown when NOT in a Claude Code worktree-isolated session.
# Needs git.exe on PATH; everything else in this script has no external dependency at all.
$segBranch = ""
if (-not $gitWorktree) {
    $branch = $null
    try { $branch = (git -C $cwd rev-parse --abbrev-ref HEAD 2>$null) } catch { }
    if ($branch -and $branch -ne "HEAD") {
        $segBranch = "`e[38;2;120;200;120m$([char]0xD83C)$([char]0xDF3F) $branch$RESET"  # 🌿
    }
}

$line2 = $segDir
if ($segBranch) { $line2 += "$PIPE$segBranch" }
if ($segGitWorktree) { $line2 += "$PIPE$segGitWorktree" }
if ($segOrigBranch) { $line2 += "$PIPE$segOrigBranch" }

Write-Output "$line1`n$line2"
