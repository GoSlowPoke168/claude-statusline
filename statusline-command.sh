#!/bin/bash
# Claude Code status line: two-line truecolor design
# Line 1: model | effort | mode | context bar | cost | velocity | 5h rate limit | 7d rate limit
# Line 2: cwd | git worktree | worktree original branch

input=$(cat)

RESET='\033[0m'
SEP='\033[38;2;110;110;110m'   # dim gray pipe separator
PIPE="${SEP} | ${RESET}"

# color interpolation helper: green(0,200,80) -> yellow(220,200,0) -> red(220,40,20)
color_at() {
    # $1 = position percentage 0-100
    awk -v p="$1" 'BEGIN{
        if (p <= 50) {
            f = p/50.0
            r = 0   + (220-0)   * f
            g = 200 + (200-200) * f
            b = 80  + (0-80)    * f
        } else {
            f = (p-50)/50.0
            r = 220 + (220-220) * f
            g = 200 + (40-200)  * f
            b = 0   + (20-0)    * f
        }
        printf "%d %d %d", r, g, b
    }'
}

# --- Model name (Claude orange, no icon) with effort level in parens ---
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
C_MODEL='\033[1;38;2;217;119;87m'
C_EFFORT='\033[38;2;217;119;87m'
if [ -n "$effort" ]; then
    seg_model="${C_MODEL}${model}${RESET} ${C_EFFORT}(${effort})${RESET}"
else
    seg_model="${C_MODEL}${model}${RESET}"
fi

# --- Thinking on/off ---
thinking=$(echo "$input" | jq -r 'if .thinking.enabled == true then "on" elif .thinking.enabled == false then "off" else empty end')
seg_thinking=""
if [ -n "$thinking" ]; then
    if [ "$thinking" = "on" ]; then
        seg_thinking="\033[38;2;180;130;255mthinking: on${RESET}"
    else
        seg_thinking="\033[38;2;120;120;120mthinking: off${RESET}"
    fi
fi

# --- Mode (output style) ---
mode=$(echo "$input" | jq -r '.output_style.name // empty')
seg_mode=""
[ -n "$mode" ] && seg_mode="\033[38;2;180;220;180m${mode}${RESET}"

# --- Context usage ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
[ -z "$used_pct" ] && used_pct=0

blocks=20
filled=$(awk -v p="$used_pct" -v n="$blocks" 'BEGIN{v=int((p/100.0)*n+0.5); if(v>n)v=n; if(v<0)v=0; print v}')
bar=""
i=1
while [ "$i" -le "$blocks" ]; do
    if [ "$i" -le "$filled" ]; then
        pos=$(awk -v i="$i" -v n="$blocks" 'BEGIN{printf "%.2f", ((i-1)/(n-1))*100}')
        rgb=$(color_at "$pos")
        r=$(echo "$rgb" | cut -d' ' -f1)
        g=$(echo "$rgb" | cut -d' ' -f2)
        b=$(echo "$rgb" | cut -d' ' -f3)
        bar="${bar}\033[38;2;${r};${g};${b}m\xe2\x96\x88"
    else
        bar="${bar}\033[38;2;60;60;60m\xe2\x96\x88"
    fi
    i=$((i+1))
done
bar="${bar}${RESET}"

# --- Dynamic emoji based on usage level ---
usage_emoji=$(awk -v p="$used_pct" 'BEGIN{
    if (p < 20) print "\xf0\x9f\x9f\xa2";
    else if (p < 70) print "\xe2\x9a\xa1";
    else if (p < 90) print "\xf0\x9f\x94\xa5";
    else print "\xf0\x9f\x9a\xa8";
}')

# --- Percentage colored by usage level ---
pct_rgb=$(color_at "$used_pct")
pr=$(echo "$pct_rgb" | cut -d' ' -f1)
pg=$(echo "$pct_rgb" | cut -d' ' -f2)
pb=$(echo "$pct_rgb" | cut -d' ' -f3)
pct_str=$(awk -v p="$used_pct" 'BEGIN{printf "%.0f%%", p}')
seg_ctx="${bar} ${usage_emoji} \033[1;38;2;${pr};${pg};${pb}m${pct_str}${RESET}"

# --- Session cost (yellow) ---
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
seg_cost=""
if [ -n "$cost" ]; then
    cost_str=$(awk -v c="$cost" 'BEGIN{printf "$%.2f", c}')
    C_COST='\033[38;2;220;200;0m'
    seg_cost="${C_COST}${cost_str}${RESET}"
fi

# --- Code velocity (+added green / -removed red) ---
added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
seg_velocity=""
if [ -n "$added" ] || [ -n "$removed" ]; then
    [ -z "$added" ] && added=0
    [ -z "$removed" ] && removed=0
    C_ADD='\033[38;2;0;200;80m'
    C_DEL='\033[38;2;220;40;20m'
    seg_velocity="${C_ADD}+${added}${RESET} ${C_DEL}-${removed}${RESET}"
fi

# --- Rate limits: 5-hour and 7-day, each with a circle glyph, used %, and local reset time ---
five_h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

circle_glyph() {
    # $1 = used percentage 0-100
    awk -v p="$1" 'BEGIN{
        if (p < 20) print "\xe2\x97\x8b";       # ○
        else if (p < 40) print "\xe2\x97\x94";  # ◔
        else if (p < 60) print "\xe2\x97\x91";  # ◑
        else if (p < 80) print "\xe2\x97\x95";  # ◕
        else print "\xe2\x97\x8f";               # ●
    }'
}

# epoch -> local "%-I:%M %p", trying GNU date first then BSD date (macOS)
epoch_to_time() {
    date -d "@${1}" +"%-I:%M %p" 2>/dev/null || date -r "${1}" +"%-I:%M %p" 2>/dev/null
}

C_RL='\033[38;2;120;200;255m'
seg_ratelimit=""
if [ -n "$five_h_pct" ]; then
    five_h_str=$(awk -v p="$five_h_pct" 'BEGIN{printf "%.0f%%", p}')
    five_h_glyph=$(circle_glyph "$five_h_pct")
    reset_str=""
    if [ -n "$five_h_reset" ]; then
        five_h_time=$(epoch_to_time "$five_h_reset")
        [ -n "$five_h_time" ] && reset_str=" (resets ${five_h_time})"
    fi
    seg_ratelimit="${C_RL}5h: ${five_h_glyph} ${five_h_str}${reset_str}${RESET}"
fi
if [ -n "$seven_d_pct" ]; then
    seven_d_str=$(awk -v p="$seven_d_pct" 'BEGIN{printf "%.0f%%", p}')
    seven_d_glyph=$(circle_glyph "$seven_d_pct")
    [ -n "$seg_ratelimit" ] && seg_ratelimit="${seg_ratelimit}${PIPE}"
    seg_ratelimit="${seg_ratelimit}${C_RL}7d: ${seven_d_glyph} ${seven_d_str}${RESET}"
fi

# --- Assemble line 1 ---
line1="${seg_model}"
[ -n "$seg_thinking" ] && line1="${line1}${PIPE}${seg_thinking}"
[ -n "$seg_mode" ] && line1="${line1}${PIPE}${seg_mode}"
line1="${line1}${PIPE}${seg_ctx}"
[ -n "$seg_cost" ] && line1="${line1}${PIPE}${seg_cost}"
[ -n "$seg_velocity" ] && line1="${line1}${PIPE}${seg_velocity}"
[ -n "$seg_ratelimit" ] && line1="${line1}${PIPE}${seg_ratelimit}"

# --- Line 2: cwd | git worktree | worktree original branch ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
[ -z "$cwd" ] && cwd="$PWD"
C_DIR='\033[38;2;150;200;255m'
seg_dir="${C_DIR}\xf0\x9f\x93\x81 ${cwd}${RESET}"

git_worktree=$(echo "$input" | jq -r '.workspace.git_worktree // empty')
seg_git_worktree=""
[ -n "$git_worktree" ] && seg_git_worktree="\033[38;2;0;220;220m\xf0\x9f\x8c\xbf ${git_worktree}${RESET}"

orig_branch=$(echo "$input" | jq -r '.worktree.original_branch // empty')
seg_orig_branch=""
[ -n "$orig_branch" ] && seg_orig_branch="\033[38;2;220;180;0m\xe2\x86\x90 ${orig_branch}${RESET}"

# --- Plain current git branch (only when not in a Claude Code worktree-isolated session) ---
seg_branch=""
if [ -z "$git_worktree" ]; then
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
        C_BRANCH='\033[38;2;120;200;120m'
        seg_branch="${C_BRANCH}\xf0\x9f\x8c\xbf ${branch}${RESET}"
    fi
fi

line2="${seg_dir}"
[ -n "$seg_branch" ] && line2="${line2}${PIPE}${seg_branch}"
[ -n "$seg_git_worktree" ] && line2="${line2}${PIPE}${seg_git_worktree}"
[ -n "$seg_orig_branch" ] && line2="${line2}${PIPE}${seg_orig_branch}"

printf '%b\n%b' "${line1}" "${line2}"
