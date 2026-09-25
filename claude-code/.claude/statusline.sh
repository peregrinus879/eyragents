#!/usr/bin/env bash
# Claude Code status line
# Docs: https://code.claude.com/docs/en/statusline
#
# Design conventions:
# - Every segment must earn its place: directory, Git branch, model, context,
#   and the two rate-limit windows. No cost, duration, or host segments.
#   The weekly Fable window is not in the rate_limits payload (only the usage
#   API, which needs the credential store, exposes it); add a segment after 7d
#   when a release adds it.
# - Consistent "label: pct% (remaining)" pattern: ctx: 42% (116k),
#   5h: 38% (2h:11m), 7d: 24% (5d:6h:38m). The dim bracket holds what remains:
#   context tokens, or the countdown to the window reset as colon-joined unit
#   fields from the largest nonzero unit down to minutes.
# - Three-space separators between segments; single spaces bind label, value,
#   and bracket within a segment.
# - Colors pin the Omarchy gruvbox palette as truecolor so rendering does not
#   depend on the terminal's ANSI palette; re-pin when the theme changes.
# - Color roles: dim = labels and brackets; bold = the directory; italic = the
#   Git branch; green/yellow/red = severity thresholds.
# - Stateless: nothing is cached or persisted between renders.
# - Intentionally no Bash strict mode, and [ ] guards throughout: parse failures
#   degrade to blank segments instead of killing the status line.

input=$(cat)

# --- Parse JSON input (single jq call); NUL-delimited so an embedded newline in
# a payload string cannot shift later fields ---
readarray -d '' -t _f < <(printf '%s' "$input" | jq -j '
  [ (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    (.context_window.used_percentage // ""),
    (.context_window.total_input_tokens // 0),
    (.context_window.context_window_size // 0),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | map(tostring) | join([0] | implode)
' 2>/dev/null)
# Scrub C0 control bytes so payload text cannot break line integrity.
# shellcheck disable=SC2004  # Keep the indexed-array subscript explicit.
for i in "${!_f[@]}"; do _f[$i]="${_f[$i]//[$'\001'-$'\037']/}"; done
cwd="${_f[0]}" model="${_f[1]}" used_pct="${_f[2]}" ctx_tokens="${_f[3]}" ctx_size="${_f[4]}"
rate_5h="${_f[5]}" rate_7d="${_f[6]}" reset_5h="${_f[7]}" reset_7d="${_f[8]}"
now=$(date +%s)

# --- Colors: Omarchy gruvbox palette (themes/gruvbox/colors.toml), truecolor.
# Real escape bytes, so the final printf can use %s and payload-derived text
# prints literally instead of having its backslash sequences interpreted. ---
dim=$'\033[38;2;124;111;100m'          # dark_foreground #7c6f64
bold_cyan=$'\033[1;38;2;137;180;130m'  # cyan #89b482
italic_cyan=$'\033[3;38;2;137;180;130m'
yellow=$'\033[38;2;216;166;87m'        # yellow #d8a657
green=$'\033[38;2;169;182;101m'        # green #a9b665
red=$'\033[38;2;234;105;98m'           # red #ea6962
reset=$'\033[0m'

# --- Helpers ---

# Color by percentage threshold
pct_color() {
  local pct=${1:-0}
  if [ "$pct" -ge 90 ] 2>/dev/null; then echo "$red"
  elif [ "$pct" -ge 70 ] 2>/dev/null; then echo "$yellow"
  else echo "$green"
  fi
}

# Format tokens: 200000 -> 200k
fmt_k() {
  local n=${1:-0}
  [ "$n" -gt 0 ] 2>/dev/null || { echo ""; return; }
  echo "$((n / 1000))k"
}

# Format seconds remaining as colon-joined unit fields from the largest nonzero
# unit down to minutes: 5d:6h:38m, 6h:38m, 59m; under one minute prints <1m
# Args: seconds
fmt_countdown() {
  local remaining=${1:-0} d h m
  if [ "$remaining" -le 0 ] 2>/dev/null; then echo ""; return; fi
  d=$((remaining / 86400))
  h=$(( (remaining % 86400) / 3600 ))
  m=$(( (remaining % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then printf '%dd:%dh:%dm\n' "$d" "$h" "$m"
  elif [ "$h" -gt 0 ]; then printf '%dh:%dm\n' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm\n' "$m"
  else echo "<1m"
  fi
}

# Render one rate-limit segment on stdout: label: pct% (countdown); the dim
# bracket holds the time remaining until the window resets.
# Args: label pct reset_epoch
build_rate_seg() {
  local label=$1 pct=$2 epoch=$3
  local pct_int detail=""

  [ -z "$pct" ] && return
  pct_int=$(printf '%.0f' "$pct" 2>/dev/null) || return
  [ "${epoch:-0}" -gt "$now" ] 2>/dev/null && detail=$(fmt_countdown "$((epoch - now))")

  printf '%s' "${dim}${label}:${reset} $(pct_color "$pct_int")${pct_int}%${reset}${detail:+ ${dim}(${detail})${reset}}"
}

# --- Segments ---

# Directory and Git branch
branch=""
repo_root=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
           || GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  repo_root=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
fi

# Directory: repo root + relative path inside git repos, last 2 components
# outside; either way a deep tail collapses to …/ plus its last 2 components
if [ -n "$repo_root" ]; then
  repo_name="${repo_root##*/}"
  rel_path="${cwd#"$repo_root"}"
  rel_path="${rel_path#/}"
  if [ -n "$rel_path" ]; then
    IFS='/' read -ra parts <<< "$rel_path"
    n=${#parts[@]}
    if [ "$n" -gt 2 ]; then
      rel_path="…/${parts[$((n-2))]}/${parts[$((n-1))]}"
    fi
    short_cwd="${repo_name}/${rel_path}"
  else
    short_cwd="$repo_name"
  fi
else
  short_cwd="${cwd/#$HOME/\~}"
  IFS='/' read -ra parts <<< "$short_cwd"
  n=${#parts[@]}
  if [ "$n" -gt 2 ]; then
    short_cwd="…/${parts[$((n-2))]}/${parts[$((n-1))]}"
  fi
fi
[ "${#branch}" -gt 24 ] && branch="${branch:0:23}…"
dir_seg="${short_cwd:+${bold_cyan}${short_cwd}${reset}}"
branch_seg="${branch:+${italic_cyan}${branch}${reset}}"

# Model (strip "Claude " prefix if present)
short_model="${model#Claude }"
model_seg="${short_model:+${dim}${short_model}${reset}}"

# Context window: "ctx: pct% (remaining tokens)"
# used_percentage can be null early in session before first API call.
ctx_seg=""
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct" 2>/dev/null)
  ctx_left=""
  [ "$ctx_size" -gt 0 ] 2>/dev/null && [ "$ctx_tokens" -gt 0 ] 2>/dev/null && \
    ctx_left=$(fmt_k "$((ctx_size - ctx_tokens))")
  ctx_seg="${dim}ctx:${reset} $(pct_color "$used_int")${used_int}%${reset}${ctx_left:+ ${dim}(${ctx_left})${reset}}"
fi

# Rate limits: 5h and 7d (bracketed countdown to the window reset)
rate5_seg=$(build_rate_seg "5h" "$rate_5h" "$reset_5h")
rate7_seg=$(build_rate_seg "7d" "$rate_7d" "$reset_7d")

# --- Output ---
line=""
for seg in "$dir_seg" "$branch_seg" "$model_seg" "$ctx_seg" "$rate5_seg" "$rate7_seg"; do
  [ -n "$seg" ] && line+="${line:+   }${seg}"
done
printf '%s\n' "$line"
