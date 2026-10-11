# Optional water-usage segment, sourced by statusline-command.sh with its args.
# Uses the caller's $input, $cost, $RESET, $PIPE and $COLUMNS, and appends to $line2.
WATER_SESSION=0; WATER_LIFETIME=0; WATER_EQUIVALENTS=0
for arg in "$@"; do
    case "$arg" in
        --water-session) WATER_SESSION=1 ;;
        --water-lifetime) WATER_LIFETIME=1 ;;
        --water-equivalents) WATER_EQUIVALENTS=1 ;;
    esac
done

# ~40 Wh per list-price $ (Couch 2026, via Epoch AI) x ~4.2 mL/Wh (Li et al., US on-site + off-site)
WATER_ML_PER_USD=170

fmt_water() {
    awk -v m="$1" 'BEGIN{
        if (m < 1000) printf "%d mL", m + 0.5
        else if (m < 100000) printf "%.1f L", m / 1000
        else printf "%d L", m / 1000 + 0.5
    }'
}

# "session<TAB>lifetime" facts for $1/$2 mL: any pair from different rows whose " (≈ ...)" suffixes fit
# in $4 columns (-1: no limit), chosen by seed $3; else one fitting fact
pick_facts() {
    awk -F'|' -v ws="$1" -v wl="$2" -v seed="$3" -v spare="$4" '
    function trim0(s) { sub(/\.0$/, "", s); return s }
    function grp(n,    s, out) {
        s = sprintf("%d", n); out = ""
        while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) }
        return s out
    }
    function cnt(x) {
        if (x < 10) return trim0(sprintf("%.1f", x))
        if (x < 1e6) return grp(int(x + 0.5))
        if (x < 1e9) return trim0(sprintf("%.1f", x / 1e6)) " million"
        if (x < 1e12) return trim0(sprintf("%.1f", x / 1e9)) " billion"
        return trim0(sprintf("%.1f", x / 1e12)) " trillion"
    }
    function dur(sec,    v, u, s) {
        if (sec < 1) { v = sec * 1000; u = "millisecond" }
        else if (sec < 60) { v = sec; u = "second" }
        else if (sec < 3600) { v = sec / 60; u = "minute" }
        else if (sec < 172800) { v = sec / 3600; u = "hour" }
        else if (sec < 5184000) { v = sec / 86400; u = "day" }
        else if (sec < 63115200) { v = sec / 2629800; u = "month" }
        else { v = sec / 31557600; u = "year" }
        s = cnt(v)
        return s " " u (s == "1" ? "" : "s")
    }
    function phrase(w,    r, p, pc) {
        r = w / $2; p = ""
        if ($1 == "time") { if (r >= 0.001) p = sprintf($3, dur(r)) }
        else if (r >= 2) p = sprintf($3, cnt(r))
        else if (r >= 1) p = $4
        else if (r >= 0.1 && $5 != "") { pc = int(r * 100 + 0.5); if (pc > 99) pc = 99; p = sprintf($5, pc "%") }
        return p
    }
    function fits(n) { return spare < 0 || n < spare }
    BEGIN { ns = 0; nl = 0 }
    { sub(/\r$/, "") }
    /^#/ || NF < 3 { next }
    {
        if (ws != "") { p = phrase(ws); if (p != "") { S[ns] = p; SR[ns++] = NR } }
        if (wl != "") { p = phrase(wl); if (p != "") { L[nl] = p; LR[nl++] = NR } }
    }
    END {
        n = 0
        if (ns && nl) {
            for (i = 0; i < ns; i++) for (j = 0; j < nl; j++)
                if (SR[i] != LR[j] && fits(length(S[i]) + length(L[j]) + 10)) { PI[n] = i; PJ[n++] = j }
            if (n) { k = seed % n; print S[PI[k]] "\t" L[PJ[k]]; exit }
        }
        if (nl) { for (j = 0; j < nl; j++) if (fits(length(L[j]) + 5)) C[n++] = j; if (n) print "\t" L[C[seed % n]] }
        else if (ns) { for (i = 0; i < ns; i++) if (fits(length(S[i]) + 5)) C[n++] = i; if (n) print S[C[seed % n]] "\t" }
    }' "$(dirname "${BASH_SOURCE[0]}")/water-facts.txt" 2>/dev/null
}

# Prices stdin rows (model, input, output, cache write, cache read, searches): fixed table, then learned
# prices ($2), then a family guess. With $3 = unknown, prints the models missing from the fixed table.
price_tokens() {
    awk -F'\t' -v pf="$1" -v lf="$2" -v mode="$3" '
    function fixed(m,    k) {
        if (m in I) return m
        k = m; sub(/-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/, "", k)
        return (k in I) ? k : ""
    }
    BEGIN {
        while ((getline line < pf) > 0) {
            if (line ~ /^#/ || line == "") continue
            sub(/\r$/, "", line); split(line, f, "|")
            I[f[1]] = f[2]; W[f[1]] = f[3]; R[f[1]] = f[4]; O[f[1]] = f[5]
        }
        if (lf != "") while ((getline line < lf) > 0) { split(line, f, "|"); L[f[1]] = f[2] }
    }
    {
        m = $1; k = fixed(m)
        if (mode == "unknown") { if (k == "") print m; next }
        if (k != "") s += ($2 * I[k] + $3 * O[k] + $4 * W[k] + $5 * R[k]) / 1e6
        else {
            if (m in L) p = L[m]
            else if (index(m, "fable") || index(m, "mythos")) p = 10
            else if (index(m, "opus")) p = 4
            else if (index(m, "sonnet")) p = 2
            else if (index(m, "haiku")) p = 0.1
            else p = 5
            s += ($2 + 5 * $3 + 2 * $4 + 0.1 * $5) * p / 1e6
        }
        s += 0.01 * $6
    }
    END { if (mode != "unknown" && NR) printf "%.4f", s }'
}

# Learns each model's price per input-equivalent MTok from Claude Code's cost-state records in transcripts
learn_prices() {
    grep -h '"cost-state"' "$1"/projects/*/*.jsonl 2>/dev/null |
        jq -rR 'fromjson? | select(.type == "cost-state") | .sessionId as $s | (.modelUsage // {}) | to_entries[] | [$s, .key, (.value.inputTokens // 0), (.value.outputTokens // 0), (.value.cacheCreationInputTokens // 0), (.value.cacheReadInputTokens // 0), (.value.webSearchRequests // 0), (.value.costUSD // 0)] | @tsv' |
        awk -F'\t' '{ row[$1 SUBSEP $2] = $0 } END {
            for (k in row) { split(row[k], f, "\t"); c[f[2]] += f[8] - 0.01 * f[7]; w[f[2]] += f[3] + 5 * f[4] + 2 * f[5] + 0.1 * f[6] }
            for (m in w) if (w[m] > 0 && c[m] > 0) printf "%s|%.6f\n", m, c[m] * 1e6 / w[m]
        }'
}

# Display width of a %b string: ANSI stripped, 4-byte UTF-8 (emoji) counted as 2 columns
vis_width() {
    printf '%b' "$1" | LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" | od -An -tu1 | awk '{ for (i = 1; i <= NF; i++) { if ($i < 128 || $i >= 192) w++; if ($i >= 240) w++ } } END { print w + 0 }'
}

# One candidate segment: $1/$2 = session/lifetime fact suffixes, $3 = 1 drops the labels
water_compose() {
    out=""; s_label=" session"; l_label=" lifetime"
    [ "$3" = 1 ] && s_label="" && l_label=""
    [ -n "$s_amt" ] && out="${s_amt}${s_label}$1"
    if [ -n "$l_amt" ]; then
        [ -n "$out" ] && out="${out} \xc2\xb7 "
        out="${out}${l_amt}${l_label}$2"
    fi
    printf '%s' "\033[38;2;70;150;255m\xf0\x9f\x92\xa7 ${out}${RESET}"
}

seg_water=""
if [ "$WATER_SESSION" = 1 ] || [ "$WATER_LIFETIME" = 1 ]; then
    s_amt=""; l_amt=""; session_ml=""; lifetime_ml=""
    if [ "$WATER_SESSION" = 1 ]; then
        session_ml=$(awk -v c="${cost:-0}" -v k="$WATER_ML_PER_USD" 'BEGIN{printf "%.3f", c * k}')
        s_amt=$(fmt_water "$session_ml")
    fi
    if [ "$WATER_LIFETIME" = 1 ]; then
        # Lifetime tokens from /stats's cache; learned prices are refreshed daily, only if a model isn't in the table
        cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        prices_file="$(dirname "${BASH_SOURCE[0]}")/water-prices.txt"
        learned_file="$cfg/water-learned-prices.txt"
        lifetime_usd=""
        usage=$(jq -r '.modelUsage // {} | to_entries[] | [.key, (.value.inputTokens // 0), (.value.outputTokens // 0), (.value.cacheCreationInputTokens // 0), (.value.cacheReadInputTokens // 0), (.value.webSearchRequests // 0)] | @tsv' "$cfg/stats-cache.json" 2>/dev/null)
        if [ -n "$usage" ]; then
            if [ -n "$(printf '%s\n' "$usage" | price_tokens "$prices_file" "" unknown)" ] && [ -z "$(find "$learned_file" -mtime -1 2>/dev/null)" ]; then
                learn_prices "$cfg" > "$learned_file.tmp" 2>/dev/null && mv "$learned_file.tmp" "$learned_file"
            fi
            lifetime_usd=$(printf '%s\n' "$usage" | price_tokens "$prices_file" "$learned_file")
        fi
        if [ -n "$lifetime_usd" ]; then
            lifetime_ml=$(awk -v l="$lifetime_usd" -v c="${cost:-0}" -v k="$WATER_ML_PER_USD" 'BEGIN{printf "%.3f", (l + c) * k}')
            l_amt=$(fmt_water "$lifetime_ml")
        fi
    fi
    if [ -n "$s_amt$l_amt" ]; then
        # Labels if they fit $COLUMNS, then facts chosen to fill the space left; else the compact form
        labeled=$(water_compose "" "" 0)
        spare=-1  # columns left for facts; -1 = no width limit, 0 = labels don't fit
        case "${COLUMNS:-}" in
            ''|*[!0-9]*) ;;
            *)
                # Claude Code indents the statusline and truncates a few columns short of $COLUMNS
                room=$((COLUMNS - 6 - $(vis_width "$line2") - 3))
                spare=$((room - $(vis_width "$labeled")))
                if [ "$spare" -le 0 ]; then
                    spare=0
                    compact=$(water_compose "" "" 1)
                    [ "$(vis_width "$compact")" -lt "$room" ] && seg_water=$compact
                fi ;;
        esac
        if [ "$spare" -ne 0 ]; then
            seg_water=$labeled
            if [ "$WATER_EQUIVALENTS" = 1 ]; then
                session_id=$(echo "$input" | jq -r '.session_id // empty')
                water_seed=$(printf '%s' "$session_id" | od -An -tu1 | awk -v t="$(date +%s)" '{ for (i = 1; i <= NF; i++) s += $i } END { print s + int(t / 300) }')
                picked=$(pick_facts "$session_ml" "$lifetime_ml" "$water_seed" "$spare")
                tab=$(printf '\t'); s_f=${picked%%"$tab"*}; l_f=${picked#*"$tab"}
                # " (≈ fact)" in the dim fact color, then back to the water color
                s_fact=""; l_fact=""
                [ -n "$s_f" ] && s_fact=" \033[38;2;120;160;210m(\xe2\x89\x88 ${s_f})\033[38;2;70;150;255m"
                [ -n "$l_f" ] && l_fact=" \033[38;2;120;160;210m(\xe2\x89\x88 ${l_f})\033[38;2;70;150;255m"
                seg_water=$(water_compose "$s_fact" "$l_fact" 0)
            fi
        fi
    fi
fi
[ -n "$seg_water" ] && line2="${line2}${PIPE}${seg_water}"
