# Optional water-usage segment, dot-sourced by statusline-command.ps1.
# Uses the caller's $data, $ESC, $RESET, $PIPE, -Water* switches and $env:COLUMNS, and appends to $line2.
# ~40 Wh per list-price $ (Couch 2026, via Epoch AI) x ~4.2 mL/Wh (Li et al., US on-site + off-site)
$WATER_ML_PER_USD = 170
$inv = [Globalization.CultureInfo]::InvariantCulture

# awk's printf "%.1f" for $x >= 0: rounds the exact binary value half-to-even (.NET's "0.0" rounds the
# 15-digit decimal away from zero, so 0.15 and 6.25 differ)
function Format-1([double]$x) {
    $bits = [BitConverter]::DoubleToInt64Bits($x)
    $exp = [int](($bits -shr 52) -band 0x7FF); $man = $bits -band 0xFFFFFFFFFFFFF
    if ($exp -eq 0) { $exp = 1 } else { $man = $man -bor 0x10000000000000 }
    $e = $exp - 1075
    if ($e -ge 0) { $tenths = [Numerics.BigInteger]$man * [Numerics.BigInteger]::Pow(2, $e) * 10 }
    else {
        $den = [Numerics.BigInteger]::Pow(2, -$e); $rem = [Numerics.BigInteger]::Zero
        $tenths = [Numerics.BigInteger]::DivRem([Numerics.BigInteger]$man * 10, $den, [ref]$rem)
        $c = ($rem * 2).CompareTo($den)
        if ($c -gt 0 -or ($c -eq 0 -and -not $tenths.IsEven)) { $tenths += 1 }
    }
    $s = $tenths.ToString().PadLeft(2, '0')
    return $s.Substring(0, $s.Length - 1) + "." + $s.Substring($s.Length - 1)
}

function Format-Water([double]$m) {
    if ($m -lt 1000) { return "$([math]::Floor($m + 0.5)) mL" }
    elseif ($m -lt 100000) { return (Format-1 ($m / 1000)) + " L" }
    else { return "$([math]::Floor($m / 1000 + 0.5)) L" }
}

function Format-Count([double]$x) {
    if ($x -lt 10) { return ((Format-1 $x) -replace '\.0$', '') }
    if ($x -lt 1e6) { return ([math]::Floor($x + 0.5)).ToString("#,0", $inv) }
    if ($x -lt 1e9) { return ((Format-1 ($x / 1e6)) -replace '\.0$', '') + " million" }
    if ($x -lt 1e12) { return ((Format-1 ($x / 1e9)) -replace '\.0$', '') + " billion" }
    return ((Format-1 ($x / 1e12)) -replace '\.0$', '') + " trillion"
}

function Format-Duration([double]$sec) {
    if ($sec -lt 1) { $v = $sec * 1000; $u = "millisecond" }
    elseif ($sec -lt 60) { $v = $sec; $u = "second" }
    elseif ($sec -lt 3600) { $v = $sec / 60; $u = "minute" }
    elseif ($sec -lt 172800) { $v = $sec / 3600; $u = "hour" }
    elseif ($sec -lt 5184000) { $v = $sec / 86400; $u = "day" }
    elseif ($sec -lt 63115200) { $v = $sec / 2629800; $u = "month" }
    else { $v = $sec / 31557600; $u = "year" }
    $s = Format-Count $v
    if ($s -eq "1") { return "$s $u" } else { return "$s ${u}s" }
}

# The fact phrase for $ml from one water-facts.txt row, or "" if it doesn't apply
function Get-FactPhrase([double]$ml, $f) {
    $r = $ml / [double]::Parse($f[1], $inv)
    if ($f[0] -eq "time") { if ($r -ge 0.001) { return $f[2] -replace '%s', (Format-Duration $r) } }
    elseif ($r -ge 2) { return $f[2] -replace '%s', (Format-Count $r) }
    elseif ($r -ge 1) { if ($f.Count -gt 3) { return $f[3] } }
    elseif ($r -ge 0.1 -and $f.Count -gt 4 -and $f[4]) {
        $pc = [math]::Min([math]::Floor($r * 100 + 0.5), 99)
        return $f[4] -replace '%s', "$pc%"
    }
    return ""
}

# @(session fact, lifetime fact): any pair from different rows whose " (≈ ...)" suffixes fit in $spare
# columns ($spare < 0: no limit), chosen by $seed; else one fitting fact
function Select-FunFacts($sMl, $lMl, [long]$seed, [int]$spare) {
    $path = Join-Path $PSScriptRoot "water-facts.txt"
    if (-not (Test-Path $path)) { return @("", "") }
    $S = @(); $SR = @(); $L = @(); $LR = @(); $row = 0
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $row++
        $line = $line.TrimEnd("`r")
        if ($line.StartsWith("#")) { continue }
        $f = $line -split '\|'
        if ($f.Count -lt 3) { continue }
        if ($null -ne $sMl) { $p = Get-FactPhrase $sMl $f; if ($p) { $S += $p; $SR += $row } }
        if ($null -ne $lMl) { $p = Get-FactPhrase $lMl $f; if ($p) { $L += $p; $LR += $row } }
    }
    $limit = if ($spare -lt 0) { [int]::MaxValue } else { $spare }
    if ($S.Count -and $L.Count) {
        $pairs = [Collections.Generic.List[int[]]]::new()
        for ($i = 0; $i -lt $S.Count; $i++) {
            for ($j = 0; $j -lt $L.Count; $j++) {
                if ($SR[$i] -ne $LR[$j] -and $S[$i].Length + $L[$j].Length + 10 -lt $limit) { $pairs.Add(@($i, $j)) }
            }
        }
        if ($pairs.Count) { $p = $pairs[$seed % $pairs.Count]; return @($S[$p[0]], $L[$p[1]]) }
    }
    $one = if ($L.Count) { $L } else { $S }
    $fit = @($one | Where-Object { $_.Length + 5 -lt $limit })
    if ($fit.Count) { $f = $fit[$seed % $fit.Count]; if ($L.Count) { return @("", $f) } else { return @($f, "") } }
    return @("", "")
}

# model id -> @(input, cache write, cache read, output) $/MTok from water-prices.txt
function Get-FixedPrices([string]$path) {
    $t = @{}
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $line = $line.TrimEnd("`r")
        if ($line -eq "" -or $line.StartsWith("#")) { continue }
        $f = $line -split '\|'
        $t[$f[0]] = @([double]::Parse($f[1], $inv), [double]::Parse($f[2], $inv), [double]::Parse($f[3], $inv), [double]::Parse($f[4], $inv))
    }
    return $t
}

# Table key for a model id, allowing a -YYYYMMDD date suffix; $null if not listed
function Get-FixedKey([string]$m, $prices) {
    if ($prices.ContainsKey($m)) { return $m }
    $k = $m -replace '-\d{8}$', ''
    if ($prices.ContainsKey($k)) { return $k } else { return $null }
}

# Fixed table, then learned price, then a family guess; plus $0.01 per web search
function Get-TokenCost([string]$m, $u, $prices, $learned) {
    $in = [double]$u.inputTokens; $out = [double]$u.outputTokens
    $cw = [double]$u.cacheCreationInputTokens; $cr = [double]$u.cacheReadInputTokens
    $k = Get-FixedKey $m $prices
    if ($k) { $p = $prices[$k]; $c = ($in * $p[0] + $cw * $p[1] + $cr * $p[2] + $out * $p[3]) / 1e6 }
    else {
        if ($learned.ContainsKey($m)) { $p = $learned[$m] }
        elseif ($m.Contains("fable") -or $m.Contains("mythos")) { $p = 10 }
        elseif ($m.Contains("opus")) { $p = 4 }
        elseif ($m.Contains("sonnet")) { $p = 2 }
        elseif ($m.Contains("haiku")) { $p = 0.1 }
        else { $p = 5 }
        $c = ($in + 5 * $out + 2 * $cw + 0.1 * $cr) * $p / 1e6
    }
    return $c + 0.01 * [double]$u.webSearchRequests
}

# Learns each model's price per input-equivalent MTok from Claude Code's cost-state records in transcripts
function Get-LearnedPrices([string]$configDir) {
    $rows = @{}
    foreach ($file in Get-ChildItem -Path (Join-Path $configDir "projects/*/*.jsonl") -ErrorAction SilentlyContinue) {
        foreach ($line in [IO.File]::ReadLines($file.FullName)) {
            if (-not $line.Contains('"cost-state"')) { continue }
            try { $d = $line | ConvertFrom-Json } catch { continue }
            if ($d.type -ne "cost-state") { continue }
            foreach ($p in $d.modelUsage.PSObject.Properties) { $rows["$($d.sessionId)|$($p.Name)"] = $p }
        }
    }
    $c = @{}; $w = @{}
    foreach ($p in $rows.Values) {
        $u = $p.Value
        $c[$p.Name] += [double]$u.costUSD - 0.01 * [double]$u.webSearchRequests
        $w[$p.Name] += [double]$u.inputTokens + 5 * [double]$u.outputTokens + 2 * [double]$u.cacheCreationInputTokens + 0.1 * [double]$u.cacheReadInputTokens
    }
    foreach ($m in $w.Keys) { if ($w[$m] -gt 0 -and $c[$m] -gt 0) { "$m|" + ($c[$m] * 1e6 / $w[$m]).ToString("0.000000", $inv) } }
}

# Display width: ANSI stripped, surrogate pairs (emoji) counted as 2 columns
function Get-VisibleWidth([string]$s) {
    $w = 0
    foreach ($c in ($s -replace "$ESC\[[0-9;]*m", "").ToCharArray()) {
        if ([char]::IsHighSurrogate($c)) { $w += 2 } elseif (-not [char]::IsLowSurrogate($c)) { $w += 1 }
    }
    return $w
}

# One candidate segment: session/lifetime fact suffixes, $noLabels drops "session"/"lifetime"
function Join-WaterParts([string]$sF, [string]$lF, [bool]$noLabels) {
    $sLabel = if ($noLabels) { "" } else { " session" }
    $lLabel = if ($noLabels) { "" } else { " lifetime" }
    $out = ""
    if ($sAmt) { $out = "$sAmt$sLabel$sF" }
    if ($lAmt) {
        if ($out) { $out += " $([char]0x00B7) " }
        $out += "$lAmt$lLabel$lF"
    }
    return "$ESC[38;2;70;150;255m$([char]0xD83D)$([char]0xDCA7) $out$RESET"  # 💧
}

$segWater = ""
if ($WaterSession -or $WaterLifetime) {
    $sessionUsd = if ($null -ne $data.cost.total_cost_usd) { [double]$data.cost.total_cost_usd } else { 0 }
    $sAmt = ""; $lAmt = ""; $sessionMl = $null; $lifetimeMl = $null
    if ($WaterSession) {
        $sessionMl = $sessionUsd * $WATER_ML_PER_USD
        $sAmt = Format-Water $sessionMl
    }
    if ($WaterLifetime) {
        # Lifetime tokens from /stats's cache; learned prices are refreshed daily, only if a model isn't in the table
        $configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
        $lifetimeUsd = $null
        try {
            $stats = Get-Content (Join-Path $configDir "stats-cache.json") -Raw -ErrorAction Stop | ConvertFrom-Json
            $prices = Get-FixedPrices (Join-Path $PSScriptRoot "water-prices.txt")
            $usage = @($stats.modelUsage.PSObject.Properties)
            $learnedPath = Join-Path $configDir "water-learned-prices.txt"
            $unknown = @($usage | Where-Object { -not (Get-FixedKey $_.Name $prices) })
            $fresh = (Test-Path $learnedPath) -and ((Get-Item $learnedPath).LastWriteTime -gt (Get-Date).AddDays(-1))
            if ($unknown.Count -gt 0 -and -not $fresh) {
                [IO.File]::WriteAllLines($learnedPath, [string[]]@(Get-LearnedPrices $configDir))
            }
            $learned = @{}
            if (Test-Path $learnedPath) {
                foreach ($line in [IO.File]::ReadAllLines($learnedPath)) { $f = $line -split '\|'; if ($f.Count -eq 2) { $learned[$f[0]] = [double]::Parse($f[1], $inv) } }
            }
            foreach ($prop in $usage) { $lifetimeUsd += Get-TokenCost $prop.Name $prop.Value $prices $learned }
        } catch { }
        if ($null -ne $lifetimeUsd) {
            $lifetimeMl = ($lifetimeUsd + $sessionUsd) * $WATER_ML_PER_USD
            $lAmt = Format-Water $lifetimeMl
        }
    }
    if ($sAmt -or $lAmt) {
        # Labels if they fit $env:COLUMNS, then facts chosen to fill the space left; else the compact form
        $labeled = Join-WaterParts "" "" $false
        $spare = -1  # columns left for facts; -1 = no width limit, 0 = labels don't fit
        $cols = 0
        if ([int]::TryParse([string]$env:COLUMNS, [ref]$cols)) {
            # Claude Code indents the statusline and truncates a few columns short of $env:COLUMNS
            $room = $cols - 6 - (Get-VisibleWidth $line2) - 3
            $spare = $room - (Get-VisibleWidth $labeled)
            if ($spare -le 0) {
                $spare = 0
                $compact = Join-WaterParts "" "" $true
                if ((Get-VisibleWidth $compact) -lt $room) { $segWater = $compact }
            }
        }
        if ($spare -ne 0) {
            $segWater = $labeled
            if ($WaterEquivalents) {
                $seed = [long][math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 300)
                if ($data.session_id) { foreach ($b in [Text.Encoding]::UTF8.GetBytes([string]$data.session_id)) { $seed += $b } }
                $picked = Select-FunFacts $sessionMl $lifetimeMl $seed $spare
                # " (≈ fact)" in the dim fact color, then back to the water color
                $sF = if ($picked[0]) { " $ESC[38;2;120;160;210m($([char]0x2248) $($picked[0]))$ESC[38;2;70;150;255m" } else { "" }
                $lF = if ($picked[1]) { " $ESC[38;2;120;160;210m($([char]0x2248) $($picked[1]))$ESC[38;2;70;150;255m" } else { "" }
                $segWater = Join-WaterParts $sF $lF $false
            }
        }
    }
}
if ($segWater) { $line2 += "$PIPE$segWater" }
