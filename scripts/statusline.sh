#!/bin/sh
input=$(cat)

# ── Model name ──────────────────────────────────────────────
# e.g. "Gemini 3.7 Flash (Medium)" -> "3.7 Flash", "Claude 3.7 Sonnet" -> "3.7 Sonnet"
raw_model=$(echo "$input" | jq -r '.model.display_name // .model.id // empty')
model=$(echo "$raw_model" | sed -E 's/^Gemini //i; s/^Claude //i; s/ *\([^)]*\)//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# ── Context: remaining % ──────────────────────────────────────────
ctx_remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
if [ -n "$ctx_remaining" ]; then
  ctx=$(echo "$ctx_remaining" | awk '{printf "%.0f", $1}')
  ctx_part="ctx ${ctx}%"
else
  ctx_part="ctx --"
fi

# ── 5-hour rate limit / quota ─────────────────────────────────────
five_fraction=$(echo "$input" | jq -r '(.quota["gemini-5h"] // .quota["3p-5h"]).remaining_fraction // empty')
five_reset_secs=$(echo "$input" | jq -r '(.quota["gemini-5h"] // .quota["3p-5h"]).reset_in_seconds // empty')

# Also handle CC-style rate_limits if present
five_used=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

five_part=""
if [ -n "$five_fraction" ]; then
  five_remaining=$(echo "$five_fraction" | awk '{printf "%.0f", $1 * 100}')
  if [ -n "$five_reset_secs" ] && [ "$five_reset_secs" -gt 0 ]; then
    now=$(date +%s)
    reset_epoch=$(( now + five_reset_secs ))
    five_reset_time=$(date -r "$reset_epoch" "+%H:%M" 2>/dev/null || date -d "@$reset_epoch" "+%H:%M" 2>/dev/null)
    if [ -n "$five_reset_time" ]; then
      five_part="5h ${five_remaining}% ~${five_reset_time}"
    else
      five_part="5h ${five_remaining}%"
    fi
  elif [ "$five_remaining" -ge 100 ] 2>/dev/null; then
    five_part="5h ready"
  else
    five_part="5h ${five_remaining}%"
  fi
elif [ -n "$five_used" ] && [ -n "$five_resets" ]; then
  five_remaining=$(echo "$five_used" | awk '{printf "%.0f", 100 - $1}')
  now=$(date +%s)
  secs=$(( five_resets - now ))
  if [ "$secs" -le 0 ]; then
    five_part="5h ready"
  else
    five_reset_time=$(date -r "$five_resets" "+%H:%M" 2>/dev/null || date -d "@$five_resets" "+%H:%M" 2>/dev/null)
    five_part="5h ${five_remaining}% ~${five_reset_time}"
  fi
fi

# ── 7-day rate limit / quota ──────────────────────────────────────
week_fraction=$(echo "$input" | jq -r '(.quota["gemini-weekly"] // .quota["3p-weekly"]).remaining_fraction // empty')
week_used=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

week_part=""
if [ -n "$week_fraction" ]; then
  week_remaining=$(echo "$week_fraction" | awk '{printf "%.0f", $1 * 100}')
  week_part="7d ${week_remaining}%"
elif [ -n "$week_used" ]; then
  week_remaining=$(echo "$week_used" | awk '{printf "%.0f", 100 - $1}')
  week_part="7d ${week_remaining}%"
fi

# ── Current working directory & Git branch ────────────────────────
cwd_full=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
if [ -z "$cwd_full" ]; then
  cwd_full="$PWD"
fi
cwd_base=$(basename "$(dirname "$cwd_full")")/$(basename "$cwd_full")

git_branch=""
if [ -n "$cwd_full" ]; then
  git_branch=$(git -C "$cwd_full" rev-parse --abbrev-ref HEAD 2>/dev/null)
else
  git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

SEP=" · "

# Machine name (mkp / work …)
host=$(scutil --get LocalHostName 2>/dev/null || hostname -s)

# ── Line 1: location (host · dir/branch) ──────────────────────────
# Dedup worktrees: dir leaf and branch leaf often say the same thing.
dir_leaf=$(basename "$cwd_full")
branch_leaf=$(echo "$git_branch" | sed 's#^worktree[-/]##; s#^task[-/]##')

loc=""
if [ -n "$git_branch" ] && [ "$branch_leaf" = "$dir_leaf" ] && [ "$git_branch" != "$dir_leaf" ]; then
  loc=$(printf "\033[33mwt %s\033[0m" "$dir_leaf")
elif [ -n "$git_branch" ] && [ "$git_branch" != "main" ] && [ "$git_branch" != "master" ]; then
  loc=$(printf "\033[33m%s\033[0m \033[32m(%s)\033[0m" "$cwd_base" "$git_branch")
elif [ -n "$cwd_base" ]; then
  loc=$(printf "\033[33m%s\033[0m" "$cwd_base")
fi

line1=""
if [ -n "$host" ]; then
  line1=$(printf "\033[36m%s\033[0m" "$host")
fi
[ -n "$loc" ] && { [ -n "$line1" ] && line1="${line1}${SEP}${loc}" || line1="$loc"; }

# ── Execution mode, Permissions & Effort (clean, no symbols) ──────
mode_raw=$(echo "$input" | jq -r '.mode // .agent_mode // .execution_mode // empty')
case "$mode_raw" in
  plan) mode_clean="plan" ;;
  accept-edits|accept_edits) mode_clean="accept" ;;
  *) mode_clean="exec" ;;
esac

effort_raw=$(echo "$input" | jq -r '.model.effort // .effort // .reasoning_effort // empty')
if [ -z "$effort_raw" ]; then
  effort_raw=$(echo "$raw_model" | sed -n 's/.*(\(Low\|Medium\|High\)).*/\1/ip' | tr '[:upper:]' '[:lower:]')
fi
case "$effort_raw" in
  medium|med) effort_clean="med" ;;
  high) effort_clean="high" ;;
  low) effort_clean="low" ;;
  *) effort_clean="$effort_raw" ;;
esac

sandbox_val=$(echo "$input" | jq -r '.sandbox.enabled // false')
perm_clean="skip"
if [ "$sandbox_val" = "true" ]; then
  perm_clean="sandbox"
fi

state_part="${mode_clean}${effort_clean:+ $effort_clean}${perm_clean:+ $perm_clean}"

# ── Line 2: session (model · state · ctx · 5h · 7d) ───────────────
line2=""
[ -n "$model" ] && line2="$model"

if [ -n "$state_part" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}${state_part}" || line2="$state_part"
fi

if [ -n "$ctx_part" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}${ctx_part}" || line2="$ctx_part"
fi

if [ -n "$five_part" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}${five_part}" || line2="$five_part"
fi

if [ -n "$week_part" ]; then
  [ -n "$line2" ] && line2="${line2}${SEP}${week_part}" || line2="$week_part"
fi

# ── Line 3: 会话标题 ──────────────────────────────────────────────
sid=$(echo "$input" | jq -r '.session_id // .conversation_id // empty')
override=""
if [ -n "$sid" ] && [ -r "$HOME/.claude/session-title/$sid" ]; then
  override=$(head -1 "$HOME/.claude/session-title/$sid")
fi

title=$(echo "$input" | jq --arg ov "$override" -r '
  .session_name = (if $ov != "" then $ov else (.session_name // .title // empty) end) |
  def cw: if . >= 4352 and (. <= 4447
      or (. >= 11904 and . <= 42191)
      or (. >= 44032 and . <= 55203)
      or (. >= 63744 and . <= 64255)
      or (. >= 65072 and . <= 65135)
      or (. >= 65280 and . <= 65376)
      or (. >= 65504 and . <= 65510)) then 2 else 1 end;
  (.session_name // "") as $t
  | if $t == "" then empty else
      ($t | explode
       | reduce .[] as $c ({w:0, out:[], over:false};
           if .over then .
           elif .w + ($c|cw) > 48 then .over = true
           else {w: (.w + ($c|cw)), out: (.out + [$c]), over:false} end)
       | if .over then (.out|implode) + "…" else (.out|implode) end)
    end')
line3=""
if [ -n "$title" ]; then
  line3=$(printf "\033[2;37m%s\033[0m" "$title")
fi

[ -n "$line2" ] && line2=$(printf "\033[38;5;248m%s\033[0m" "$line2")

printf "%s\n%s\n" "$line1" "$line2"
[ -n "$line3" ] && printf "%s\n" "$line3"
exit 0
