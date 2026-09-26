#!/usr/bin/env bash
# Claude Code status line
# Docs: https://code.claude.com/docs/en/statusline
#
# Design conventions:
# - Every segment must earn its place: model, effort, context, and the usage
#   limits. The terminal multiplexer's pane shows directory and Git branch; no
#   cost, duration, or host segments.
# - Consistent "label: pct% (remaining)" pattern: ctx: 42% (116k),
#   sess: 38% (2h:11m), week: 24%/63% (5d:6h:38m). The dim bracket holds
#   what remains: context tokens, or the countdown to the window reset as
#   colon-joined unit fields from the largest nonzero unit down to minutes.
# - week lists the all-models figure, then the Fable, Opus and Sonnet weekly
#   limits the account has, in that order, unlabelled and joined by a dim
#   slash, while each resets within a minute of the all-models week. Any other
#   model window, or one on its own reset, is a labelled segment with its own
#   countdown.
# - Labels are lowercase: sess and week are /usage's "Current session" and
#   "Current week"; a model window's own segment uses its lowercased name.
# - Three-space separators between segments; single spaces bind label, value,
#   and bracket within a segment.
# - Colors pin the Omarchy gruvbox palette as truecolor so rendering does not
#   depend on the terminal's ANSI palette; re-pin when the theme changes.
# - Color roles: dim = model, effort, labels and brackets; green/yellow/red =
#   severity thresholds.
# - Limits match Claude Code's /usage: 5h, 7d, the Sonnet-only week and each
#   model-scoped week come from the usage endpoint /usage reads, and
#   percentages round down as /usage does. The rate_limits payload lags that
#   endpoint and omits model windows, so it is only the 5h and 7d fallback
#   while no fetched window is open.
# - The endpoint needs the login's access token. It is read only to make that
#   request and reaches curl on stdin, with curl's own config files skipped;
#   never argv, output, or cache. Each login file path has its own cache of
#   labels, percentages and reset times. A detached process refreshes it at
#   most once per USAGE_TTL, or later when the endpoint asks, so rendering
#   never waits on the network. The cache records the login file's inode,
#   size and mtime, which cannot tell a token refresh from /login to another
#   account: after any rewrite its windows are hidden (5h and 7d fall back to
#   the payload) until the next scheduled fetch replaces them, and a failed
#   fetch drops them. Without a login file nothing is fetched or written.
# - Intentionally no Bash strict mode, and [ ] guards throughout: parse failures
#   degrade to blank segments instead of killing the status line.

now=$(date +%s)

# --- Usage endpoint (account level) ---
USAGE_TTL=60
RETRY_MAX=3600
USAGE_URL=https://api.anthropic.com/api/oauth/usage
claude_login="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
usage_dir="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/eyragents"
usage_cache="$usage_dir/claude-usage-$(printf '%s' "$claude_login" | cksum | cut -d' ' -f1).json"

# The windows /usage lists: five_hour, seven_day and seven_day_sonnet, then the
# weekly_scoped entries of limits[] (its server-side allowlist is not
# readable). A window's id is its bucket key or full display name; model
# windows are labelled by display name without a "Claude " prefix or a
# parenthetical.
# shellcheck disable=SC2016  # jq program, not shell expansion.
usage_filter='
  def epoch:
    if type == "number" then (if . > 1e12 then . / 1000 else . end | floor)
    elif type == "string" then
      (try (sub("\\.[0-9]+"; "") | sub("(\\+00:00|Z)$"; "Z") | fromdateiso8601) catch null)
    else null end;
  def window($id; $label; $pct; $reset):
    { id: $id, label: $label, pct: (($pct | tonumber?) // null), resets_at: ($reset | epoch) }
    | select(.label != "" and .pct != null);
  { fetched_at: $now, retry_at: 0, login: $login,
    windows: [
      ({ "5h": .five_hour, "7d": .seven_day, "Sonnet": .seven_day_sonnet }
        | to_entries[] | select(.value | type == "object")
        | window(.key; .key; .value.utilization; .value.resets_at)),
      ((.limits | if type == "array" then .[] else empty end)
        | select(type == "object" and .kind == "weekly_scoped"
                 and (.scope.model.display_name | type) == "string")
        | .scope.model.display_name as $name
        | window($name; $name | ltrimstr("Claude ") | sub("\\s*\\(.*$"; "")
                   | gsub("[^A-Za-z0-9._ -]"; ""); .percent; .resets_at)) ] }'

# Identity of the login file, so a cache from another login is discarded.
login_id() { stat -c '%i:%s:%.9Y' "$claude_login" 2>/dev/null; }

# True when the cache is older than USAGE_TTL and past any retry-after.
# Args: fetched_at retry_at
usage_due() {
  local fetched=$1 retry=$2
  [[ $fetched =~ ^[0-9]+$ ]] || fetched=0
  [[ $retry =~ ^[0-9]+$ ]] || retry=0
  [ "$now" -ge "$((fetched + USAGE_TTL))" ] && [ "$now" -ge "$retry" ]
}

# Fetch the usage endpoint into the cache. Runs detached; the lock keeps
# concurrent sessions to one request, and every attempt, including one
# without a usable token, stamps fetched_at so a failure waits out USAGE_TTL
# (or the 429's Retry-After, capped at RETRY_MAX) before the next one.
refresh_usage() {
  local login fetched retry cached_login token expires_ms result status retry_after rc
  local done_at delay when retry_at windows body tmp
  umask 077
  mkdir -p "$usage_dir" || return
  exec 9>"${usage_cache%.json}.lock" || return
  flock -n 9 || return
  login=$(login_id)
  read -r fetched retry cached_login < <(jq -r \
    '"\(.fetched_at // 0) \(.retry_at // 0) \(.login // "")"' "$usage_cache" 2>/dev/null)
  usage_due "${fetched:-0}" "${retry:-0}" || return
  { read -r token; read -r expires_ms; } < <(jq -r '.claudeAiOauth
    | (.accessToken // "" | tostring), (.expiresAt // 0 | floor)' "$claude_login" 2>/dev/null)
  [[ $expires_ms =~ ^[0-9]+$ ]] || expires_ms=0
  body="$usage_cache.body.$$" tmp="$usage_cache.tmp.$$"
  if [[ $token =~ ^[A-Za-z0-9._~+/=-]+$ ]] && \
     { [ "$expires_ms" -eq 0 ] || [ "$expires_ms" -gt "$((now * 1000))" ]; }; then
    result=$(printf 'header = "Authorization: Bearer %s"\n' "$token" |
      curl -q -s --max-time 10 -K - -o "$body" -w '%{http_code}|%header{retry-after}' \
        -H 'anthropic-beta: oauth-2025-04-20' -H 'Accept: application/json' \
        "$USAGE_URL" 2>/dev/null; printf '|%s' "$?")
  fi
  token=""
  IFS='|' read -r status retry_after rc <<<"${result//$'\r'/}"
  done_at=$(date +%s)
  if ! { [ "$rc" = 0 ] && [ "$status" = 200 ] && \
         jq --argjson now "$done_at" --arg login "$login" "$usage_filter" "$body" >"$tmp" 2>/dev/null && \
         [ -s "$tmp" ]; }; then
    delay=0
    if [ "$status" = 429 ]; then
      # Delay seconds are decimal (RFC 9110), leading zeros allowed, or an
      # HTTP date; either is capped so one bad header cannot stop the fetch.
      if [[ $retry_after =~ ^0*([0-9]{1,9})$ ]]; then delay=$((10#${BASH_REMATCH[1]}))
      elif [[ $retry_after =~ ^[0-9]+$ ]]; then delay=$RETRY_MAX
      elif [ -n "$retry_after" ] && when=$(date -d "$retry_after" +%s 2>/dev/null) && \
           [[ $when =~ ^-?[0-9]+$ ]]; then delay=$((when - done_at))
      fi
      [ "$delay" -gt "$RETRY_MAX" ] && delay=$RETRY_MAX
      [ "$delay" -lt 0 ] && delay=0
    fi
    retry_at=$((done_at + delay))
    windows=""
    [ "$cached_login" = "$login" ] && windows=$(jq -c '.windows // []' "$usage_cache" 2>/dev/null)
    jq -n --argjson now "$done_at" --argjson retry "$retry_at" --arg login "$login" \
      --argjson windows "${windows:-[]}" \
      '{fetched_at: $now, retry_at: $retry, login: $login, windows: $windows}' >"$tmp" 2>/dev/null
  fi
  [ -s "$tmp" ] && mv -f "$tmp" "$usage_cache"
  rm -f "$body" "$tmp"
}

if [ "${1:-}" = "--refresh-usage" ]; then
  refresh_usage
  exit 0
fi

input=$(cat)

# --- Parse JSON input (single jq call); NUL-delimited so an embedded newline in
# a payload string cannot shift later fields ---
readarray -d '' -t _f < <(printf '%s' "$input" | jq -j '
  [ (.model.display_name // ""),
    (.effort.level // ""),
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
model="${_f[0]}" effort="${_f[1]}" used_pct="${_f[2]}" ctx_tokens="${_f[3]}" ctx_size="${_f[4]}"
rate_5h="${_f[5]}" rate_7d="${_f[6]}" reset_5h="${_f[7]}" reset_7d="${_f[8]}"

# --- Colors: Omarchy gruvbox palette (themes/gruvbox/colors.toml), truecolor.
# Real escape bytes, so the final printf can use %s and payload-derived text
# prints literally instead of having its backslash sequences interpreted. ---
dim=$'\033[38;2;124;111;100m'          # dark_foreground #7c6f64
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

# Render a colored percentage, rounded down as /usage shows it; nothing for a
# non-number.
# Args: pct
fmt_pct() {
  local pct=$1 pct_int
  [[ $pct =~ ^[0-9]+(\.[0-9]+)?$ ]] || return
  pct_int=${pct%%.*}
  printf '%s' "$(pct_color "$pct_int")${pct_int}%${reset}"
}

# Render the dim bracketed countdown to a reset epoch; nothing once it passed.
# Args: reset_epoch
fmt_reset() {
  local epoch=$1 detail=""
  [ "${epoch:-0}" -gt "$now" ] 2>/dev/null && detail=$(fmt_countdown "$((epoch - now))")
  printf '%s' "${detail:+ ${dim}(${detail})${reset}}"
}

# Render one limit segment on stdout: label: pct% (countdown)
# Args: label pct reset_epoch [inline figures placed before the countdown]
build_rate_seg() {
  local label=$1 pct=$2 epoch=$3 inline=${4:-} value
  value=$(fmt_pct "$pct")
  [ -n "$value" ] || return
  printf '%s' "${dim}${label}:${reset} ${value}${inline}$(fmt_reset "$epoch")"
}

# --- Segments ---

# Model (without a "Claude " prefix or a parenthetical such as the context
# size, which ctx shows) and reasoning effort, absent when the model does not
# support effort
short_model="${model#Claude }"
short_model="${short_model% (*}"
model_seg="${short_model:+${dim}${short_model}${reset}}"
effort_seg="${effort:+${dim}${effort}${reset}}"

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

# Limits: open windows from this login's cache, in the endpoint's order; a due
# refresh runs detached for the next render. 5h and 7d fall back to the payload.
declare -A cached_label=() cached_pct=() cached_reset=()
model_ids=()
if [ -r "$claude_login" ]; then
  usage_lines=()
  { read -r fetched retry cached_login; mapfile -t usage_lines; } < <(jq -r --argjson now "$now" '
    "\(.fetched_at // 0) \(.retry_at // 0) \(.login // "")",
    (.windows[]? | select(.resets_at == null or .resets_at > $now)
      | "\(.id // .label)\t\(.label)\t\(.pct)\t\(.resets_at // "")")' "$usage_cache" 2>/dev/null)
  [ "$cached_login" = "$(login_id)" ] || usage_lines=()
  usage_due "${fetched:-0}" "${retry:-0}" && \
    setsid -f "${BASH_SOURCE[0]}" --refresh-usage </dev/null >/dev/null 2>&1
  for w in "${usage_lines[@]}"; do
    IFS=$'\t' read -r id label pct epoch <<<"${w//[$'\001'-$'\010'$'\012'-$'\037']/}"
    [ -n "$id" ] && [ -z "${cached_pct[$id]+x}" ] || continue
    cached_label[$id]=$label cached_pct[$id]=$pct cached_reset[$id]=$epoch
    case $id in 5h|7d) ;; *) model_ids+=("$id") ;; esac
  done
fi
[ -n "${cached_pct[5h]+x}" ] && rate_5h=${cached_pct[5h]} reset_5h=${cached_reset[5h]}
[ -n "${cached_pct[7d]+x}" ] && rate_7d=${cached_pct[7d]} reset_7d=${cached_reset[7d]}

# Limit segments: sess, week with the Fable, Opus and Sonnet figures that
# reset with it, then any other model window (bracketed countdown to the reset)
session_seg=$(build_rate_seg "sess" "$rate_5h" "$reset_5h")
ordered=()
for family in Fable Opus Sonnet other; do
  for id in "${model_ids[@]}"; do
    case ${cached_label[$id]} in
      Fable*) [ "$family" = Fable ] ;; Opus*) [ "$family" = Opus ] ;;
      Sonnet*) [ "$family" = Sonnet ] ;; *) [ "$family" = other ] ;;
    esac && ordered+=("$id")
  done
done
week_inline="" model_segs=()
for id in "${ordered[@]}"; do
  label=${cached_label[$id]} pct=${cached_pct[$id]} epoch=${cached_reset[$id]}
  if [[ $label =~ ^(Fable|Opus|Sonnet) && $epoch =~ ^[0-9]+$ && $reset_7d =~ ^[0-9]+$ ]] && \
     [ "$(( epoch > reset_7d ? epoch - reset_7d : reset_7d - epoch ))" -lt 60 ]; then
    value=$(fmt_pct "$pct")
    [ -n "$value" ] && week_inline+="${dim}/${reset}${value}"
  else
    seg=$(build_rate_seg "${label,,}" "$pct" "$epoch")
    [ -n "$seg" ] && model_segs+=("$seg")
  fi
done
week_seg=$(build_rate_seg "week" "$rate_7d" "$reset_7d" "$week_inline")

# --- Output ---
line=""
for seg in "$model_seg" "$effort_seg" "$ctx_seg" "$session_seg" "$week_seg" "${model_segs[@]}"; do
  [ -n "$seg" ] && line+="${line:+   }${seg}"
done
printf '%s\n' "$line"
