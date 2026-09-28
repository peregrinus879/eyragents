#!/usr/bin/env bash
# The spar bridges against fake claude and opencode clients: arguments, working
# directory (Git or ordinary), sparrer selection, verdicts, workspace-bound resume,
# process-group cleanup and every failure exit.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPTS="$ROOT/agents/.agents/skills/spar/scripts"
WORK=$(mktemp -d)
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null FAKE_TRACE="$WORK/trace"
mkdir -p "$WORK/bin" "$WORK/trace"
repo="$WORK/repo"
git init -q "$repo"
mkdir -p "$repo/sub"
plain="$WORK/plain workspace"
mkdir -p "$plain" "$WORK/other workspace"
ln -s "$plain" "$WORK/linked workspace"

cleanup() {
  local file
  for file in "$WORK/trace/pid" "$WORK/trace/child"; do
    [[ ! -s $file ]] || kill -KILL "$(<"$file")" 2>/dev/null || true
  done
  rm -rf -- "$WORK"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Shared fake behavior: record the reviewer's pid, optionally leave a descendant
# that ignores TERM, and answer as FAKE_MODE says.
cat >"$WORK/bin/fake-common" <<'FAKE'
printf '%s\n' "$$" >"$FAKE_TRACE/pid"
case $FAKE_MODE in
  orphan|hang)
    (trap '' TERM; exec sleep 300) &
    printf '%s\n' "$!" >"$FAKE_TRACE/child" ;;
  detached|detachedhang)
    # A descendant in its own session, as OpenCode's shell tool starts commands.
    setsid sleep 300 </dev/null >/dev/null 2>&1 &
    printf '%s\n' "$!" >"$FAKE_TRACE/child" ;;
esac
[[ $FAKE_MODE != hang && $FAKE_MODE != detachedhang ]] || exec sleep 300
FAKE
cat >"$WORK/bin/fake-claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\0' "$@" >"$FAKE_TRACE/argv"
pwd >"$FAKE_TRACE/pwd"
cat >"$FAKE_TRACE/stdin"
source "$(dirname -- "$0")/fake-common"
ok='{"type":"result","is_error":false,"result":"claude findings\nVERDICT: CLEAR","session_id":"c-123","modelUsage":{"claude-fable-5-1":{}}}'
case $FAKE_MODE in
  ok|orphan|detached) printf '%s\n' "$ok" ;;
  noisy) printf 'API error 529 overloaded; retrying\n' >&2; printf '%s\n' "$ok" ;;
  failverdict) printf '%s\n' "$ok"; exit 1 ;;
  error) printf '%s\n' '{"type":"result","is_error":true,"result":"review failed"}'; exit 1 ;;
  limit) printf "You've hit your session limit\n" >&2; exit 1 ;;
  quoted) printf '%s\n' '{"type":"result","is_error":false,"result":"LIMIT_RE covers 429 and usage limit wording\nVERDICT: CLEAR","session_id":"c-123"}'; exit 1 ;;
  blocked|incomplete) printf '%s\n' "${ok/CLEAR/${FAKE_MODE^^}}" ;;
  legacy) printf '%s\n' "${ok/CLEAR/CONVERGED}" ;;
  noid) printf '%s\n' '{"type":"result","is_error":false,"result":"findings\nVERDICT: CLEAR"}' ;;
  noverdict) printf '%s\n' '{"type":"result","is_error":false,"result":"I wrote a plan instead","session_id":"c-123"}' ;;
  empty) exit 0 ;;
esac
FAKE
cat >"$WORK/bin/fake-opencode" <<'FAKE'
#!/usr/bin/env bash
if [[ "$*" == 'agent list' ]]; then
  pwd >"$FAKE_TRACE/agent-pwd"
  case ${FAKE_AGENT:-ok} in
    ok) printf '%s\n' 'build (primary)' '  [' '  {"permission":"edit","pattern":"*","action":"allow"}' ']' \
      'sparrer (all)' '  [' '  {"permission":"edit","pattern":"*","action":"allow"},' \
      '  {"permission":"edit","pattern":"*","action":"deny"}' ']' 'plan (primary)' '  []' ;;
    missing) printf '%s\n' 'build (primary)' '  []' ;;
    subagent) printf '%s\n' 'sparrer (subagent)' '  [{"permission":"edit","pattern":"*","action":"deny"}]' ;;
    edits) printf '%s\n' 'sparrer (all)' '  [{"permission":"edit","pattern":"*","action":"deny"},' \
      '  {"permission":"edit","pattern":"*","action":"allow"}]' ;;
    hang) FAKE_MODE=hang source "$(dirname -- "$0")/fake-common" ;;
  esac
  exit 0
fi
printf '%s\0' "$@" >"$FAKE_TRACE/argv"
pwd >"$FAKE_TRACE/pwd"
source "$(dirname -- "$0")/fake-common"
ok() {
  printf '%s\n' '{"type":"step_start","sessionID":"ses_1","part":{}}' \
    '{"type":"text","sessionID":"ses_1","part":{"text":"checking the diff"}}' \
    '{"type":"tool_use","sessionID":"ses_1","part":{"state":{"output":"Falling back to default agent; rate limit"}}}' \
    '{"type":"text","sessionID":"ses_1","part":{"text":"opencode findings\nVERDICT: CLEAR"}}'
}
case $FAKE_MODE in
  ok|orphan|detached) ok ;;
  noisy) printf 'API error 429; retrying\n' >&2; ok ;;
  failverdict) ok; exit 1 ;;
  fallback) printf '! agent "sparrer" is a subagent, not a primary agent. Falling back to default agent\n' >&2; ok ;;
  error) printf '%s\n' '{"type":"error","sessionID":"ses_1","error":{"name":"APIError"}}'; exit 1 ;;
  limit) printf '%s\n' '{"type":"error","sessionID":"ses_1","error":{"name":"APIError","data":{"message":"rate limit exceeded"}}}' ;;
  quoted) ok; exit 1 ;;
  blocked|incomplete) printf '{"type":"text","sessionID":"ses_1","part":{"text":"findings\\nVERDICT: %s"}}\n' "${FAKE_MODE^^}" ;;
  legacy) printf '%s\n' '{"type":"text","sessionID":"ses_1","part":{"text":"findings\nVERDICT: CONVERGED"}}' ;;
  noid) printf '%s\n' '{"type":"text","part":{"text":"findings\nVERDICT: CLEAR"}}' ;;
  noverdict) printf '%s\n' '{"type":"text","sessionID":"ses_1","part":{"text":"no verdict here"}}' ;;
  empty) exit 0 ;;
esac
FAKE
cat >"$WORK/bin/fake-entry.py" <<'FAKE'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Observe the fixture's inherited PWD before Bash can repair it. No other environment is recorded.
trace = Path(os.environ["FAKE_TRACE"])
(trace / "entry-pwd").write_text(os.environ.get("PWD", ""))
client = Path(sys.argv[0])
os.execv("/bin/bash", ["bash", str(client.with_name("fake-" + client.name)), *sys.argv[1:]])
FAKE
chmod 755 "$WORK/bin/fake-entry.py"
ln -s fake-entry.py "$WORK/bin/claude"
ln -s fake-entry.py "$WORK/bin/opencode"
export PATH="$WORK/bin:$PATH"

run() { # mode bridge args... ; sets RC, leaves out/err in $WORK
  local mode=$1 bridge=$2
  shift 2
  rm -f -- "$WORK/trace/"*
  RC=0
  (cd "${RUN_DIR:-$repo/sub}" && FAKE_MODE=$mode "$SCRIPTS/$bridge" "$@") >"$WORK/out" 2>"$WORK/err" || RC=$?
}
argv() { tr '\0' '\n' <"$WORK/trace/argv"; }
handle() { awk '/^SPAR-BRIDGE ID:/ { print $3 }' "$WORK/err"; }
interrupt() { # label command... : start a hanging bridge, TERM it, require exit 130 within 5 s
  local label=$1 i bridge_pid
  shift
  rm -f -- "$WORK/trace/"*
  (cd "$repo" && exec "$@") >/dev/null 2>&1 &
  bridge_pid=$!
  for ((i = 0; i < 50; i++)); do [[ -s $WORK/trace/child ]] && break; sleep 0.1; done
  [[ -s $WORK/trace/child ]] || fail "$label: the reviewer never started"
  kill -TERM "$bridge_pid"
  for ((i = 0; i < 50; i++)); do kill -0 "$bridge_pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$bridge_pid" 2>/dev/null; then kill -KILL "$bridge_pid"; fail "$label: the bridge ignored an interrupt"; fi
  RC=0
  wait "$bridge_pid" || RC=$?
  [[ $RC == 130 ]] || fail "$label: exited $RC on interrupt, expected 130"
  gone "$WORK/trace/pid" "$label: the reviewer survived an interrupt"
  gone "$WORK/trace/child" "$label: a descendant survived an interrupt"
}
gone() { # file label: the recorded process must be gone
  local i
  [[ -s $1 ]] || fail "$2: no process was recorded"
  for ((i = 0; i < 50; i++)); do kill -0 "$(<"$1")" 2>/dev/null || return 0; sleep 0.1; done
  fail "$2: process $(<"$1") still running"
}

for bridge in spar-claude spar-opencode; do
  for args in "" "review" "review ''" "review a b" "review --resume" "other x"; do
    eval "set -- $args"
    run ok "$bridge" "$@"
    [[ $RC == 64 ]] || fail "$bridge accepted usage: $args"
  done
  RUN_DIR=$plain run ok "$bridge" review 'Review the report.'
  [[ $RC == 0 && $(<"$FAKE_TRACE/pwd") == "$plain" ]] || fail "$bridge cannot review an ordinary folder"
  ordinary_handle=$(handle)
  RUN_DIR="$WORK/linked workspace" run ok "$bridge" review --resume "$ordinary_handle" 'Check the revised report.'
  [[ $RC == 0 && $(<"$FAKE_TRACE/pwd") == "$plain" ]] || fail "$bridge does not resolve a workspace alias on resume"
  [[ $(<"$FAKE_TRACE/entry-pwd") == "$plain" ]] || fail "$bridge passed a logical alias as PWD"
  RUN_DIR="$WORK/other workspace" run ok "$bridge" review --resume "$ordinary_handle" 'Wrong folder.'
  [[ $RC == 5 && ! -e $FAKE_TRACE/argv ]] || fail "$bridge resumed a review in another workspace"
  for invalid in c-123 '@bad' 'session@bad'; do
    run ok "$bridge" review --resume "$invalid" 'Invalid handle.'
    [[ $RC == 5 && ! -e $FAKE_TRACE/argv ]] || fail "$bridge accepted an unbound resume handle"
  done
  for mode in error limit empty noverdict failverdict quoted legacy noid; do
    run "$mode" "$bridge" review 'Review.'
    expected=5
    [[ $mode != limit ]] || expected=3
    [[ $RC == "$expected" && ! -s $WORK/out ]] || fail "$bridge $mode exited $RC, expected $expected"
  done
  run ok "$bridge" review 'Review.'
  [[ $RC == 0 && $(<"$WORK/trace/pwd") == "$repo" ]] || fail "$bridge did not run from the repository root"
  [[ $(<"$FAKE_TRACE/entry-pwd") == "$repo" ]] || fail "$bridge retained the launch subdirectory as PWD"
  for mode in blocked incomplete; do
    run "$mode" "$bridge" review 'Review.'
    [[ $RC == 0 && $(tail -n 1 "$WORK/out") == "VERDICT: ${mode^^}" ]] || fail "$bridge rejected a valid $mode review"
  done

  # Bad Git metadata must not silently turn a failed repository into a plain workspace.
  broken="$WORK/broken"
  mkdir -p "$broken/.git"
  RUN_DIR=$broken run ok "$bridge" review 'Review.'
  [[ $RC == 5 && ! -e $FAKE_TRACE/argv ]] || fail "$bridge accepted a broken .git directory"
  rm -rf -- "$broken/.git"
  printf 'invalid gitfile\n' >"$broken/.git"
  RUN_DIR=$broken run ok "$bridge" review 'Review.'
  [[ $RC == 5 && ! -e $FAKE_TRACE/argv ]] || fail "$bridge accepted a broken .git file"
  rm -- "$broken/.git"
  git init -q --bare "$WORK/bare"
  RUN_DIR="$WORK/bare" run ok "$bridge" review 'Review.'
  [[ $RC == 5 && ! -e $FAKE_TRACE/argv ]] || fail "$bridge accepted a bare repository as an ordinary folder"
  GIT_DIR="$WORK/no-such-git-directory" RUN_DIR=$plain run ok "$bridge" review 'Review.'
  [[ $RC == 5 && ! -e $FAKE_TRACE/entry-pwd ]] || fail "$bridge ignored invalid explicit Git configuration"

  # The reviewer's process group is gone after completion, timeout and interrupt,
  # including a descendant that ignores TERM.
  run orphan "$bridge" review 'Review.'
  [[ $RC == 0 ]] || fail "$bridge orphan case exited $RC"
  gone "$WORK/trace/child" "$bridge left a descendant after completing"
  SPAR_BRIDGE_TIMEOUT=1 run hang "$bridge" review 'Review.'
  [[ $RC == 124 ]] || fail "$bridge did not time out"
  gone "$WORK/trace/child" "$bridge left a descendant after a timeout"
  FAKE_MODE=hang interrupt "$bridge review" "$SCRIPTS/$bridge" review 'Review.'
  # Descendants that start their own session escape a process-group kill; the supervisor adopts them.
  run detached "$bridge" review 'Review.'
  [[ $RC == 0 ]] || fail "$bridge detached case exited $RC"
  gone "$WORK/trace/child" "$bridge left a detached descendant after completing"
  SPAR_BRIDGE_TIMEOUT=1 run detachedhang "$bridge" review 'Review.'
  [[ $RC == 124 ]] || fail "$bridge did not time out with a detached descendant"
  gone "$WORK/trace/child" "$bridge left a detached descendant after a timeout"
  FAKE_MODE=detachedhang interrupt "$bridge detached review" "$SCRIPTS/$bridge" review 'Review.'
  # A retried 429 or 529 on stderr before a good reply is not a usage limit.
  run noisy "$bridge" review 'Review.'
  [[ $RC == 0 && -s $WORK/out ]] || fail "$bridge reported a limit for a successful review (exit $RC)"
done

run ok spar-claude review 'Review the diff. Already ran make check.'
[[ $(<"$WORK/out") == $'claude findings\nVERDICT: CLEAR' ]] || fail 'spar-claude did not relay the reply'
[[ $(<"$WORK/trace/stdin") == 'Review the diff. Already ran make check.' ]] || fail 'spar-claude did not send the request'
claude_handle=$(handle)
{ [[ $claude_handle == c-123@* ]] && grep -qx 'SPAR-BRIDGE MODEL: claude-fable-5-1' "$WORK/err"; } ||
  fail 'spar-claude did not report session and model'
expected=$(printf '%s\n' -p --permission-mode auto --agent sparrer --disallowedTools 'mcp__*' --strict-mcp-config \
  --output-format json)
[[ $(argv) == "$expected" ]] || fail "spar-claude flags drifted: $(argv)"
# A project agent named sparrer would take precedence over the user sparrer: refused before any call.
mkdir -p "$repo/.claude/agents/nested"
for name in '"sparrer"' "sparrer # project reviewer" "'sparrer'"; do
  printf -- '---\nname: %s\ntools: Read, Edit\n---\nShadow.\n' "$name" >"$repo/.claude/agents/nested/shadow.md"
  run ok spar-claude review 'Review.'
  [[ $RC == 5 && ! -e $WORK/trace/argv ]] || fail "spar-claude ran with a project-defined sparrer (name: $name)"
done
rm -rf -- "$repo/.claude"
run ok spar-claude review --resume "$claude_handle" 'Round two.'
[[ $(argv | tail -n 2) == $'--resume\nc-123' ]] || fail 'spar-claude did not resume the named session'

# Plain-folder discovery includes ancestors, but the user agent directory is not a project override.
mkdir -p "$WORK/fake-home/reports/sub" "$WORK/fake-home/.claude/agents"
printf -- '---\nname: sparrer\ndescription: user reviewer\n---\n' >"$WORK/fake-home/.claude/agents/sparrer.md"
HOME="$WORK/fake-home" RUN_DIR="$WORK/fake-home/reports/sub" run ok spar-claude review 'Review.'
[[ $RC == 0 ]] || fail 'spar-claude refused the intended user agent'
mkdir -p "$WORK/fake-home/reports/.claude/agents"
printf -- '---\nname: sparrer\ndescription: override\n---\n' >"$WORK/fake-home/reports/.claude/agents/override.md"
HOME="$WORK/fake-home" RUN_DIR="$WORK/fake-home/reports/sub" run ok spar-claude review 'Review.'
[[ $RC == 5 && ! -e $FAKE_TRACE/argv ]] || fail 'spar-claude missed an ancestor override outside Git'

run ok spar-opencode review 'Review the plan.'
[[ $RC == 0 && $(<"$WORK/out") == $'opencode findings\nVERDICT: CLEAR' ]] || fail 'spar-opencode did not relay the final text'
opencode_handle=$(handle)
[[ $opencode_handle == ses_1@* ]] || fail 'spar-opencode did not report the session handle'
[[ $(<"$WORK/trace/agent-pwd") == "$repo" ]] || fail 'spar-opencode listed agents outside the repository root'
[[ $(argv) == $'run\n--agent\nsparrer\n--format\njson\n--\nReview the plan.' ]] || fail "spar-opencode flags drifted: $(argv)"
run ok spar-opencode review --resume "$opencode_handle" 'Round two.'
[[ $(argv) == $'run\n--agent\nsparrer\n--format\njson\n--session\nses_1\n--\nRound two.' ]] || fail 'spar-opencode did not resume'
run ok spar-opencode review --resume "$claude_handle" 'Wrong tool.'
[[ $RC == 5 && ! -e $FAKE_TRACE/argv ]] || fail 'spar-opencode accepted a Claude resume handle'
run ok spar-claude review --resume "$opencode_handle" 'Wrong tool.'
[[ $RC == 5 && ! -e $FAKE_TRACE/argv ]] || fail 'spar-claude accepted an OpenCode resume handle'
run fallback spar-opencode review 'Review.'
[[ $RC == 5 && ! -s $WORK/out ]] || fail 'spar-opencode relayed a default-agent fallback'
# An interrupt during the agent preflight stops it and its descendants; no review is sent.
FAKE_AGENT=hang FAKE_MODE=ok interrupt 'spar-opencode preflight' "$SCRIPTS/spar-opencode" review 'Review.'
[[ ! -e $WORK/trace/argv ]] || fail 'spar-opencode sent the review after an interrupted preflight'
for agent in missing subagent edits; do
  FAKE_AGENT=$agent run ok spar-opencode review 'Review.'
  [[ $RC == 5 && ! -e $WORK/trace/argv ]] || fail "spar-opencode sent a review to an unsafe sparrer ($agent)"
done

printf 'ok: spar bridges select Git/plain workspaces, bind resumes, relay verdicts and fail closed\n'
