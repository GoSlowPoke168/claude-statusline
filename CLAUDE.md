# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A custom two-line truecolor statusline for Claude Code, implemented as two independent,
functionally-identical scripts — one per platform family — plus their installers. There is no
build system, package manifest, or test suite; this is a pair of standalone shell/PowerShell
scripts consumed directly by Claude Code's `statusLine` settings hook.

- `statusline-command.sh` — Linux/macOS/WSL implementation (bash + `jq` + `awk`).
- `statusline-command.ps1` — Windows implementation, a native PowerShell port with **no
  dependency on bash, `jq`, or Git for Windows** (only `git.exe` on PATH, and only for the
  branch segment).
- `install.sh` / `install.ps1` — copy the matching script to `~/.claude/` (or
  `$CLAUDE_CONFIG_DIR`) and merge a `statusLine` key into `~/.claude/settings.json` without
  touching other settings.

## Critical constraint: the two scripts must stay in sync

**`statusline-command.sh` and `statusline-command.ps1` are two hand-maintained ports of the same
logic.** There is no shared source of truth and no automated check that they match. Whenever you
change one (new segment, color tweak, formatting change, bug fix), make the equivalent change in
the other, translating idioms as needed (e.g. `jq -r '.foo.bar // empty'` ↔
`$data.foo.bar`, ANSI escapes via `\033[...m` in bash vs `` `e[...m `` in PowerShell). Verify both
before considering a change complete.

## How data flows

Claude Code invokes the configured `statusLine` command once per render, piping a JSON payload on
stdin (session/model/cost/context/rate-limit/workspace state) and expecting two lines of text
(with ANSI truecolor escapes) on stdout. Both scripts follow the same shape:

1. Read all of stdin as one JSON blob (`input=$(cat)` in bash; `[Console]::In.ReadToEnd()` +
   `ConvertFrom-Json` in PowerShell).
2. Build a set of independent "segments" (model+effort, thinking mode, output style, context
   bar, cost, code velocity, rate limits, cwd, branch/worktree), each conditionally rendered only
   if its underlying JSON field is present — every field is optional and segments degrade
   gracefully to empty strings when absent.
3. Join non-empty segments with a shared dim-gray ` | ` separator (`$PIPE`/`$SEP`) into two output
   lines and print them.

Key derived-vs-raw distinctions worth knowing before editing:

- **Context bar**: a 20-block gradient bar (green → yellow → red) driven by
  `context_window.used_percentage`, built via a `color_at`/`Color-At` linear-interpolation helper.
  The percentage text is **not** colored independently from `used_percentage` — it deliberately
  reuses the RGB of the bar's *last filled block* (`last_pos`/`$lastPos`, derived from `filled`/
  `$filled`), so the two always match exactly even though 20 blocks quantize the percentage. Keep
  that indirection if you touch this segment; recomputing from the raw percentage will make the
  text and bar drift apart at some values.
- **Rate limits**: `rate_limits.five_hour` and `rate_limits.seven_day`, each rendered with a
  5-stage "moon phase" circle glyph (`○ ◔ ◑ ◕ ●`) keyed off `used_percentage` — but the two windows
  render their reset differently. `five_hour` shows a local-time clock (`resets_at` epoch → local
  `h:mm a`; bash tries GNU `date -d` first, falling back to BSD `date -r` for macOS; PowerShell
  uses `[DateTimeOffset]::FromUnixTimeSeconds(...)`). `seven_day` instead shows a countdown
  duration like `(9d2h)` via `epoch_to_countdown`/`Format-Countdown`, not a clock time.
- **Disabled token-count segment**: there's a commented-out `(used/max)` token-count sub-segment
  right after the context percentage in both scripts (search "Token count"). It's intentionally
  off by default — uncomment in both scripts together to re-enable, and note its color is wired
  to the same last-filled-block RGB as the percentage text, not a fixed color.
- **Worktree awareness**: when `workspace.git_worktree` is present (a Claude Code
  `EnterWorktree`-isolated session), line 2 shows the worktree name and its
  `worktree.original_branch` instead of the plain current branch. The plain-branch segment
  (`git rev-parse --abbrev-ref HEAD` against `workspace.current_dir`) is only computed/shown when
  *not* in such a session.
- **Numeric formatting/rounding parity**: PowerShell's default numeric formatting traps are easy
  to reach for and *look* equivalent to the bash side but aren't. Use `F`-format specifiers
  (`"{0:F2}"`), never `N`-format (`"{0:N2}"`) — `N` inserts thousands separators (`$1,234.56`)
  that bash's `printf "%.2f"` never produces. Round with `[math]::Round(x,
  [MidpointRounding]::AwayFromZero)`, not bare `[math]::Round` — its default is banker's rounding
  (round-half-to-even), which disagrees with awk's `int(v+0.5)` at exact `.5` boundaries (e.g. the
  context bar's fill count). And RGB channels in `Color-At` must use `[math]::Truncate`, not
  `Round` — the bash `color_at` truncates via awk's `%d`, so `Round` drifts the gradient by up to
  1 per channel versus bash.

## Testing changes

There's no automated test suite. To validate a change, pipe a representative JSON payload into
the script directly and inspect the rendered output, e.g.:

```sh
echo '{"model":{"display_name":"Claude"},"context_window":{"used_percentage":42},"cost":{"total_cost_usd":1.23,"total_lines_added":10,"total_lines_removed":2},"rate_limits":{"five_hour":{"used_percentage":30,"resets_at":1750000000}},"workspace":{"current_dir":"'"$PWD"'"}}' | bash statusline-command.sh
```

For PowerShell, pipe equivalent JSON through `pwsh -File statusline-command.ps1` (or
`powershell.exe` on Windows). After editing, re-run the relevant installer
(`./install.sh` or `install.ps1`) to redeploy the script to `~/.claude/` if you want to see it
live in a real Claude Code session — restart Claude Code (or start a new session) afterward, since
the statusline command is only re-read at session start.

## Editing colors/layout

Colors and segment order are hardcoded truecolor ANSI escapes (`\033[38;2;R;G;Bm` / RGB literals
near each segment) directly in the two scripts — there's no theme/config file. Change them in
place in both scripts per the sync requirement above.
