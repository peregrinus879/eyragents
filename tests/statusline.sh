#!/usr/bin/env bash
# Render the status line from representative payloads and check each segment.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STATUSLINE="$ROOT/claude-code/.claude/statusline.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
plain() { sed 's/\x1b\[[0-9;]*m//g'; }

render() { env -u CLAUDE_CONFIG_DIR -u XDG_CACHE_HOME XDG_RUNTIME_DIR="$TMP" HOME="$TMP" "$STATUSLINE" <<<"$1" | plain; }

now=$(date +%s)
future_hour=$(( now + 3600 ))
future_days=$(( now + 5 * 86400 + 6 * 3600 + 38 * 60 + 30 ))

# --- Payload only: no login file, so nothing is fetched or written ---
full=$(printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Claude Test (1M context)"},"effort":{"level":"xhigh"},"context_window":{"used_percentage":42,"total_input_tokens":84000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":%s},"seven_day":{"used_percentage":95,"resets_at":%s}}}\n' "$ROOT" "$future_hour" "$future_days")
output=$(render "$full")
re_full='^Test   xhigh   ctx: 42% \(116k\)   sess: 20% \((59m|1h:0m)\)   week: 95% \(5d:6h:38m\)$'
[[ $output =~ $re_full ]] || fail "payload segments did not render in order: $output"
[[ $output != *"${ROOT##*/}"* ]] || fail "directory segment rendered"

floor=$(printf '{"model":{"display_name":"Claude Test"},"rate_limits":{"seven_day":{"used_percentage":39.9,"resets_at":%s}}}\n' "$future_days")
output=$(render "$floor")
[[ $output == *'week: 39% '* ]] || fail "payload percentage did not round down as /usage does: $output"

sub_minute=$(printf '{"model":{"display_name":"Claude Test"},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":%s}}}\n' "$(( now + 30 ))")
output=$(render "$sub_minute")
[[ $output == *'sess: 5% (<1m)'* ]] || fail "sub-minute countdown did not render as <1m: $output"

minimal='{"model":{"display_name":"Claude Test"},"context_window":{"used_percentage":42}}'
output=$(render "$minimal")
[ "$output" = 'Test   ctx: 42%' ] || fail "missing fields did not degrade to bare segments: $output"

output=$(render 'not json')
[[ -z $output ]] || fail "malformed input did not degrade to an empty line"

[[ -z $(find "$TMP" -mindepth 1 -maxdepth 1) ]] || fail "status line wrote state without a login"

# --- Usage endpoint: a fake login and stub curl and setsid on PATH, so no test
# reads a real login or reaches the network. ---
U="$TMP/usage"
TOKEN=sk-ant-oat01-TESTTOKEN/+=_~.-x
mkdir -p "$U/home/.claude" "$U/run" "$U/bin"
login() { printf '{"claudeAiOauth":{"accessToken":"%s","expiresAt":%s}}\n' "${2:-$TOKEN}" "$1" >"$U/home/.claude/.credentials.json"; }
cat >"$U/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/argv"
out=""
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
cat >"$STUB_DIR/stdin"
sleep "$(cat "$STUB_DIR/delay")"
echo x >>"$STUB_DIR/calls"
cp "$STUB_DIR/body" "$out"
printf '%s|%s' "$(cat "$STUB_DIR/status")" "$(cat "$STUB_DIR/retry")"
exit "$(cat "$STUB_DIR/exit")"
STUB
cat >"$U/bin/setsid" <<STUB
#!/usr/bin/env bash
echo x >>"\$STUB_DIR/launches"
exec $(command -v setsid) "\$@"
STUB
chmod +x "$U/bin/curl" "$U/bin/setsid"
usage_env=(env -u CLAUDE_CONFIG_DIR -u XDG_CACHE_HOME HOME="$U/home" XDG_RUNTIME_DIR="$U/run" STUB_DIR="$U" PATH="$U/bin:$PATH")
refresh() { "${usage_env[@]}" "$STATUSLINE" --refresh-usage; }
render_usage() { "${usage_env[@]}" "$STATUSLINE" <<<"$1" | plain; }
count() { if [ -f "$U/$1" ]; then wc -l <"$U/$1"; else echo 0; fi; }
wait_for() { for _ in $(seq 50); do [ "$(count "$1")" -ge "$2" ] && return; sleep 0.1; done; }
cache="$U/run/eyragents/claude-usage-$(printf '%s' "$U/home/.claude/.credentials.json" | cksum | cut -d' ' -f1).json"
set_cache() { jq "$1" "$cache" >"$cache.new" && mv "$cache.new" "$cache"; }
stale() { set_cache '.fetched_at = 0 | .retry_at = 0'; }
respond() { printf '%s' "$1" >"$U/status"; printf '%s' "$2" >"$U/retry"; printf '%s' "$3" >"$U/body"; printf '%s' "${4:-0}" >"$U/exit"; printf '%s' "${5:-0}" >"$U/delay"; }
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.654652+00:00; }

opus_reset=$(( now + 21 * 3600 + 5 * 60 + 30 ))
body=$(jq -nc --arg h "$(iso "$future_hour")" --argjson d "$future_days" --arg f "$(iso $(( future_days + 30 )))" \
  --argjson o "$opus_reset" --argjson g "$(( now - 60 ))" '{
  five_hour: {utilization: 4.0, resets_at: $h}, seven_day: {utilization: 40.2, resets_at: $d},
  seven_day_sonnet: {utilization: 12.7, resets_at: $d},
  limits: [
    {kind: "weekly", percent: 33},
    {kind: "five_hour_scoped", scope: {model: {display_name: "Session"}}, percent: 7},
    {kind: "weekly_scoped", scope: {model: {display_name: "Fable"}}, percent: 51.4, resets_at: $f},
    {kind: "weekly_scoped", scope: {model: {display_name: "Claude Opus 5 (1M context)"}}, percent: 9, resets_at: $o},
    {kind: "weekly_scoped", scope: {model: {display_name: "Claude Opus 5 (200k context)"}}, percent: 3, resets_at: $o},
    {kind: "weekly_scoped", scope: {model: {display_name: "Haiku"}}, percent: 2, resets_at: null},
    {kind: "weekly_scoped", scope: {model: {display_name: "Gone"}}, percent: 9, resets_at: $g}]}')
payload=$(printf '{"model":{"display_name":"Claude Test"},"rate_limits":{"seven_day":{"used_percentage":33,"resets_at":%s}}}\n' "$future_days")
payload_only='Test   week: 33% (5d:6h:38m)'

login "$(( (now + 3600) * 1000 ))"
respond 200 "" "$body"
out=$(refresh 2>&1)
[ -z "$out" ] || fail "refresh printed output"
[ "$(count calls)" -eq 1 ] || fail "refresh did not call the usage endpoint"
[[ $(head -1 "$U/argv") == '-q '* ]] || fail "curl did not skip its config files with a leading -q"
[[ $(cat "$U/stdin") == *"Bearer $TOKEN"* ]] || fail "token did not reach curl on stdin"
! grep -qF -e "$TOKEN" "$U/argv" "$cache" || fail "token leaked into argv or cache"
[ "$(stat -c %a "$cache")" = 600 ] && [ "$(stat -c %a "${cache%/*}")" = 700 ] || fail "usage cache is not private"
output=$(render_usage "$payload")
re_usage='^Test   sess: 4% \((59m|1h:0m)\)   week: 40%/51%/12% \(5d:6h:38m\)   opus 5: 9% \((21h:5m|21h:4m)\)   opus 5: 3% \((21h:5m|21h:4m)\)   haiku: 2%$'
[[ $output =~ $re_usage ]] || fail "fetched windows did not render in order, rounded down: $output"
[[ $output != *"$TOKEN"* ]] || fail "token reached the rendered line"
[ "$(count launches)" -eq 0 ] || fail "fresh cache launched a refresh"
opus='(.windows[] | select(.id == "Claude Opus 5 (1M context)") | .resets_at)'
haiku='(.windows[] | select(.id == "Haiku") | .resets_at)'
set_cache "$opus = $future_days | $haiku = $future_days"
output=$(render_usage "$payload")
re_opus='   week: 40%/51%/9%/12% \(5d:6h:38m\)   opus 5: 3% \((21h:5m|21h:4m)\)   haiku: 2% \(5d:6h:38m\)$'
[[ $output =~ $re_opus ]] || fail "only Fable, Opus and Sonnet windows resetting with the week join it, in that order: $output"
set_cache "$opus = $opus_reset | $haiku = null"

stale
output=$(render_usage "$payload")
[[ $output =~ $re_usage ]] || fail "stale cache did not keep rendering"
wait_for calls 2
[ "$(count launches)" -eq 1 ] && [ "$(count calls)" -eq 2 ] || fail "stale cache did not launch one detached refresh"
for _ in $(seq 50); do [ "$(jq .fetched_at "$cache")" -gt 0 ] 2>/dev/null && break; sleep 0.1; done

stale
respond 429 300 '{"error":"rate_limited"}'
refresh
[ "$(jq .retry_at "$cache")" -ge $(( now + 300 )) ] || fail "429 did not honor a Retry-After delay"
jq -e 'any(.windows[]; .label == "Fable")' "$cache" >/dev/null || fail "failed refresh dropped the last windows"
set_cache '.fetched_at = 0'
refresh
[ "$(count calls)" -eq 3 ] || fail "refresh ran before Retry-After elapsed"

stale
respond 429 "$(date -u -d "@$(( now + 600 ))" '+%a, %d %b %Y %H:%M:%S GMT')" ''
refresh
[ "$(jq .retry_at "$cache")" -ge $(( now + 600 )) ] || fail "429 did not honor a Retry-After date"

for delay in 0100 0008; do
  stale
  respond 429 "$delay" ''
  out=$(refresh 2>&1)
  [ -z "$out" ] || fail "Retry-After $delay broke the refresh: $out"
  stamped=$(jq '.retry_at - .fetched_at' "$cache")
  [ "$stamped" -eq $(( 10#$delay )) ] || fail "Retry-After $delay was not read as decimal ($stamped)"
done

for delay in 1234567890 'Sat, 01 Jan 2050 00:00:00 GMT'; do
  stale
  respond 429 "$delay" ''
  refresh
  [ "$(jq '.retry_at - .fetched_at' "$cache")" -eq 3600 ] || fail "Retry-After $delay was not capped at an hour"
done

stale
start=$(date +%s)
respond 429 300 '' 0 2
refresh
[ "$(jq .retry_at "$cache")" -ge $(( start + 302 )) ] || fail "Retry-After was not measured from the response"

for case in "200||0" "200|not json|0" "000||7"; do
  IFS='|' read -r status reply code <<<"$case"
  stale
  respond "$status" "" "$reply" "$code"
  before=$(count calls)
  refresh
  refresh
  [ "$(count calls)" -eq $(( before + 1 )) ] || fail "failed fetch ($case) was not throttled"
  jq -e 'any(.windows[]; .label == "Fable")' "$cache" >/dev/null || fail "failed fetch ($case) dropped the last windows"
done
stale
respond 200 "" "$(jq -c '.limits[2].percent = 99' <<<"$body")" 28
refresh
[ "$(jq '.windows[] | select(.label == "Fable") | .pct' "$cache")" = 51.4 ] || fail "a failed transfer applied its body"
[[ -z $(find "$U/run/eyragents" -name '*.body.*' -o -name '*.tmp.*') ]] || fail "refresh left temporary files"

set_cache '.windows |= map(select(.label != "7d"))'
output=$(render_usage "$payload")
[[ $output == *'week: 33%/51%/12% (5d:6h:38m)   '* ]] || fail "7d did not fall back to the payload: $output"
output=$(render_usage '{"model":{"display_name":"Claude Test"}}')
re_alone='^Test   sess: 4% \((59m|1h:0m)\)   fable: 51% \(5d:6h:3[89]m\)   opus 5: 9% \((21h:5m|21h:4m)\)   opus 5: 3% \((21h:5m|21h:4m)\)   sonnet: 12% \(5d:6h:38m\)   haiku: 2%$'
[[ $output =~ $re_alone ]] || fail "model windows did not stand alone without a week figure: $output"

respond 200 "" "$body"
for bad in "$(( (now - 60) * 1000 ))" nologin; do
  stale
  if [ "$bad" = nologin ]; then echo '{"other":1}' >"$U/home/.claude/.credentials.json"; else login "$bad"; fi
  before=$(count calls) launched=$(count launches)
  refresh
  render_usage "$payload" >/dev/null
  [ "$(count calls)" -eq "$before" ] || fail "unusable login ($bad) called the endpoint"
  [ "$(count launches)" -eq "$launched" ] || fail "unusable login ($bad) was not throttled"
done

login_matches() { for _ in $(seq 50); do [ "$(jq -r .login "$cache")" = "$(stat -c '%i:%s:%.9Y' "$U/home/.claude/.credentials.json")" ] && return; sleep 0.1; done; }
stale
login "$(( (now + 3600) * 1000 ))"
respond 200 "" "$body"
refresh
[[ $(render_usage "$payload") =~ $re_usage ]] || fail "a fresh fetch did not render"
before=$(count calls) launched=$(count launches)
login "$(( (now + 3600) * 1000 ))" sk-ant-oat01-REFRESHEDTOKEN
output=$(render_usage "$payload")
[ "$output" = "$payload_only" ] || fail "a login rewrite kept showing windows of an unverified login: $output"
refresh
[ "$(count calls)" -eq "$before" ] && [ "$(count launches)" -eq "$launched" ] || \
  fail "a login rewrite bypassed the fetch interval"
stale
render_usage "$payload" >/dev/null
wait_for calls $(( before + 1 ))
login_matches
[[ $(render_usage "$payload") =~ $re_usage ]] || fail "the next scheduled fetch did not restore the windows"

set_cache ".retry_at = $(( now + 3600 )) | .fetched_at = 0"
login "$(( (now + 3600) * 1000 ))" sk-ant-oat01-OTHERACCOUNT
before=$(count calls) launched=$(count launches)
output=$(render_usage "$payload")
[ "$output" = "$payload_only" ] || fail "another login's windows showed during Retry-After: $output"
refresh
[ "$(count calls)" -eq "$before" ] && [ "$(count launches)" -eq "$launched" ] || \
  fail "a login rewrite discarded the Retry-After wait"

set_cache '.retry_at = 0 | .fetched_at = 0'
respond 500 "" ''
refresh
jq -e '.windows == []' "$cache" >/dev/null || fail "a failed fetch after a login change kept the previous login's windows"
output=$(render_usage "$payload")
[ "$output" = "$payload_only" ] || fail "a failed fetch after a login change showed windows: $output"
login_before=$(jq -r .login "$cache")

mkdir -p "$U/other"
printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat01-OTHER","expiresAt":0}}\n' >"$U/other/.credentials.json"
env -u XDG_CACHE_HOME CLAUDE_CONFIG_DIR="$U/other" HOME="$U/home" XDG_RUNTIME_DIR="$U/run" STUB_DIR="$U" PATH="$U/bin:$PATH" "$STATUSLINE" --refresh-usage
[ "$(find "$U/run/eyragents" -name 'claude-usage-*.json' | wc -l)" -eq 2 ] && [ "$(jq -r .login "$cache")" = "$login_before" ] || \
  fail "another CLAUDE_CONFIG_DIR did not get its own cache"

env -u CLAUDE_CONFIG_DIR -u XDG_CACHE_HOME -u XDG_RUNTIME_DIR HOME="$U/home" STUB_DIR="$U" PATH="$U/bin:$PATH" "$STATUSLINE" --refresh-usage
[ "$(stat -c %a "$U/home/.cache/eyragents")" = 700 ] || fail "the ~/.cache fallback is not private"
compgen -G "$U/home/.cache/eyragents/claude-usage-*.json" >/dev/null || fail "without XDG_RUNTIME_DIR the cache did not fall back to ~/.cache"

printf 'ok: statusline renders its segments; limits match /usage from a private, per-login, throttled fetch\n'
