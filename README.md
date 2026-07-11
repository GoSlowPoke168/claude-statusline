# claude-statusline

A custom two-line truecolor statusline for [Claude Code](https://claude.com/claude-code), plus
one-command installers for Linux, macOS, and Windows.

**Line 1:** model + effort · thinking mode · output style · context-usage bar · session cost ·
code velocity (+added/-removed) · 5-hour and 7-day rate limits (with local reset time)
**Line 2:** current directory · git worktree · worktree's original branch

## Install

Clone this repo on the target machine, then:

**Linux / macOS**
```sh
git clone <this-repo-url> claude-statusline
cd claude-statusline
./install.sh
```

**Windows**
```powershell
git clone <this-repo-url> claude-statusline
cd claude-statusline
powershell -ExecutionPolicy Bypass -File install.ps1
```

Restart Claude Code (or start a new session) afterward.

## What the installer does

1. Copies `statusline-command.sh` to `~/.claude/statusline-command.sh` (or
   `$CLAUDE_CONFIG_DIR` if you've set that env var).
2. Makes sure `jq` is installed, installing it via your platform's package
   manager if it's missing (`apt`/`dnf`/`yum`/`pacman`/`zypper`/`brew` on
   Linux/macOS, `winget`/`choco` on Windows).
3. Merges a `statusLine` key into `~/.claude/settings.json` — it only touches
   that one key, so any other settings you already have are left alone.

Safe to re-run any time (e.g. after editing `statusline-command.sh`) — it's idempotent.

## Requirements

- **Linux/macOS:** bash, jq (auto-installed if missing).
- **Windows:** [Git for Windows](https://git-scm.com/download/win) (for `bash.exe`), jq
  (auto-installed via winget/choco if missing). Claude Code on Windows shells out to
  `bash.exe` directly to run the script — no WSL required.
  If you're running Claude Code inside WSL instead, just use the Linux instructions above.

## Notes

- The script uses GNU `date -d`, with a fallback to BSD `date -r` for macOS, to render local
  rate-limit reset times.
- To customize colors or layout, edit `statusline-command.sh` directly, then re-run the
  installer to redeploy it (or just `cp` it over `~/.claude/statusline-command.sh` yourself).
