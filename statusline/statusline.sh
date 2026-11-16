#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# ANSI color codes (ANSI-C quoting so escapes are interpreted)
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
WHITE=$'\033[37m'
RED=$'\033[31m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# Light pink plate behind the model name, Fable only (24-bit, needs truecolor).
# Foreground is a deep plum — themed ANSI magenta washes out against the pink.
BG_MODEL=$'\033[48;2;245;192;207m'
FG_MODEL=$'\033[38;2;58;32;44m'

# Extract values
model=$(echo "$input" | jq -r '.model.display_name')
folder=$(basename "$(echo "$input" | jq -r '.workspace.current_dir')")
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Git branch
git_branch=""
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
if [ -d "$current_dir/.git" ] || git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$current_dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# Tokens
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Cache info from current_usage
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
cache_creation=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')

# Cost
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Rate limits
# Max has a 5-hour window; Ultra has none, so fall back to the weekly window.
# Picked by which data is present, so switching plans needs no config change.
rl_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_label="5h"
if [ -z "$rl_pct" ]; then
    rl_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
    rl_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
    rl_label="wk"
fi

# Format tokens with k/M suffix
fmt() {
    local t=$1
    if [ "$t" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" $(echo "scale=1; $t / 1000000" | bc)
    elif [ "$t" -ge 1000 ] 2>/dev/null; then
        printf "%.1fk" $(echo "scale=1; $t / 1000" | bc)
    else
        echo "${t}"
    fi
}

# Format cost
fmt_cost() {
    local c=$1
    if echo "$c" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        printf "$%.2f" "$c"
    else
        printf "$0.00"
    fi
}

# Gradient color: green (0%) -> yellow (50%) -> red (100%).
# Uses the standard ANSI \033[32m/33m/31m at tier anchors (matching the
# branch-name green and other statusline colors) and 24-bit RGB only for
# the in-between blends, kept at the same muted intensity.
gradient_color() {
    local pct=$1
    local max=128
    if [ "$(echo "$pct <= 1" | bc)" -eq 1 ]; then
        printf '\033[32m'
        return
    fi
    if [ "$(echo "$pct >= 99" | bc)" -eq 1 ]; then
        printf '\033[31m'
        return
    fi
    if [ "$(echo "$pct >= 49 && $pct <= 51" | bc)" -eq 1 ]; then
        printf '\033[33m'
        return
    fi
    local r g
    if [ "$(echo "$pct < 50" | bc)" -eq 1 ]; then
        r=$(printf "%.0f" "$(echo "scale=4; $pct * $max / 50" | bc)")
        g=$max
    else
        r=$max
        g=$(printf "%.0f" "$(echo "scale=4; (100 - $pct) * $max / 50" | bc)")
    fi
    [ "$r" -gt "$max" ] && r=$max
    [ "$r" -lt 0 ] && r=0
    [ "$g" -gt "$max" ] && g=$max
    [ "$g" -lt 0 ] && g=0
    printf '\033[38;2;%d;%d;0m' "$r" "$g"
}

# Build an 8-char bar: filled █ and empty ░
make_bar() {
    local pct=$1
    local color=$2
    local bar_length=6
    local filled=$(printf "%.0f" $(echo "scale=4; $pct * $bar_length / 100" | bc))
    local empty=$((bar_length - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
    printf "[${color}%s${RESET}]" "$bar"
}

# --- Build sections ---

# 1. Context bar
sec_context=""
if [ -n "$used_pct" ]; then
    bar=$(make_bar "$used_pct" "$CYAN")
    sec_context=$(printf "ctx %s %.0f%%" "$bar" "$used_pct")
fi

# 2. Model — shortened (e.g. "Claude Opus 4.6 (1M context)" -> "Opus 4.6 1M")
short_model=$(echo "$model" | sed -E 's/^Claude //; s/\(//; s/ context\)//; s/\)$//')
if [[ "$model" == *[Ff]able* ]]; then
    sec_model="${BG_MODEL}${FG_MODEL} ${short_model} ${RESET}"
elif [[ "$model" == *[Hh]aiku* ]]; then
    # Bold red warning plate: Haiku in the main session is almost always an accident.
    sec_model=$'\033[48;2;200;30;30m\033[38;2;255;255;255m'"${BOLD} ⚠ ${short_model} ${RESET}"
else
    sec_model="${MAGENTA}${short_model}${RESET}"
fi

# 4. Location
if [ -n "$git_branch" ]; then
    sec_location=$(printf "${BLUE}%s${RESET} ${GREEN}(%s)${RESET}" "$folder" "$git_branch")
else
    sec_location=$(printf "${BLUE}%s${RESET}" "$folder")
fi

# 5. Usage line (second line): usg {5h bar} {pct}% | tokens ~cost
total_cache=$((cache_read + cache_creation))
total_tokens=$((total_input + total_output + total_cache))
if [ -n "$rl_pct" ]; then
    usg_color=$(gradient_color "$rl_pct")
    usg_bar=$(make_bar "$rl_pct" "$usg_color")
    usg_time=""
    if [ -n "$rl_resets" ]; then
        remaining=$((rl_resets - $(date +%s)))
        if [ "$remaining" -gt 0 ]; then
            days=$((remaining / 86400))
            hrs=$(( (remaining % 86400) / 3600 ))
            mins=$(( (remaining % 3600) / 60 ))
            if [ "$days" -gt 0 ]; then t="${days}d${hrs}h"
            elif [ "$hrs" -gt 0 ]; then t="${hrs}h${mins}m"
            else t="${mins}m"; fi
            usg_time=" ${DIM}(${t})${RESET}"
        fi
    fi
    sec_stats=$(printf "%s %s %.0f%%%s ${DIM}| %s tokens ~%s${RESET}" "$rl_label" "$usg_bar" "$rl_pct" "$usg_time" "$(fmt $total_tokens)" "$(fmt_cost $total_cost)")
else
    sec_stats=$(printf "${DIM}usg %s tokens ~%s${RESET}" "$(fmt $total_tokens)" "$(fmt_cost $total_cost)")
fi

# --- Assemble ---
# Line 1: Context | Model | Location | Venv | 5h
# Line 2: usg tokens ~cost
parts=()
[ -n "$sec_context" ] && parts+=("$sec_context")
parts+=("$sec_model")
parts+=("$sec_location")

# Join line 1 with " | "
line1=""
for i in "${!parts[@]}"; do
    [ $i -gt 0 ] && line1="${line1} | "
    line1="${line1}${parts[$i]}"
done

printf "%s\n%s\n" "$line1" "$sec_stats"
