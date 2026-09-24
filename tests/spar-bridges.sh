#!/usr/bin/env bash
# Behavioral checks for the spar reviewer bridges and payload scanner. Reviewer
# CLIs and fake HOME stay under one private scratch directory. Fixture copies
# of the bridges admit only the exact fixture paths and use the fake account
# home; the unchanged production runtime rejection is tested separately.
# Fixtures that must look like
# credentials are assembled at runtime so the repository itself stays scannable.
set -euo pipefail

FIXTURES_ONLY=false
case ${1:-} in
  '') [[ $# == 0 ]] || exit 64 ;;
  --fixtures-only) [[ $# == 1 ]] || exit 64; FIXTURES_ONLY=true ;;
  *) printf 'usage: spar-bridges.sh [--fixtures-only]\n' >&2; exit 64 ;;
esac
# Focused verification omits repository/index contracts and review-brief setup
# (including its synthetic commit). All scanner and fake-client checks still run.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLAUDE_BRIDGE="$ROOT/agents/.agents/skills/spar/scripts/spar-claude"
SCANNER="$ROOT/agents/.agents/skills/spar/scripts/spar-payload-scan"
WORK=$(mktemp -d)
TMP="$WORK/session"
HOMEBOX="$WORK/home"
export HOME="$HOMEBOX" TMPDIR="$TMP"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
SHIMS="$HOMEBOX/bin"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$SHIMS" "$TMP/art" "$WORK/bridges"
chmod 700 "$TMP"
chmod 755 "$TMP/art"
SCAN_OUT=("$SCANNER" outbound --scratch-root "$TMP" --)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_child_stopped() {
  local file=$1 label=$2 child i
  [[ -s $file ]] || return 0
  child=$(<"$file")
  # A group signal is asynchronous; allow bounded scheduling/reaping latency.
  for ((i = 0; i < 40; i++)); do
    kill -0 "$child" 2>/dev/null || return 0
    sleep 0.05
  done
  fail "$label left a descendant after cleanup"
}

# Dependency injection lives only in these disposable copies, never in a
# production environment flag or a writable runtime exemption.
python3 - "$WORK/bridges" "$SHIMS" "$HOMEBOX" "$CLAUDE_BRIDGE" <<'PY'
import pathlib, shlex, sys
for source in sys.argv[4:]:
    text = pathlib.Path(source).read_text()
    needle = '  local root\n'
    assert text.count(needle) == 1
    shims = pathlib.Path(sys.argv[2])
    text = text.replace(needle, needle + '  case $1 in ' + '|'.join(shlex.quote(str(shims / name)) for name in ('claude', 'git')) + ') return 0 ;; esac\n')
    needle = 'account_home=$(getent passwd "$(id -u)" | cut -d: -f6)'
    assert text.count(needle) == 1
    text = text.replace(needle, 'account_home=' + shlex.quote(sys.argv[3]))
    target = pathlib.Path(sys.argv[1]) / pathlib.Path(source).name
    target.write_text(text)
    target.chmod(0o755)
PY
cp -- "$SCANNER" "$WORK/bridges/spar-payload-scan"
PRODUCTION_CLAUDE=$CLAUDE_BRIDGE
CLAUDE_BRIDGE="$WORK/bridges/spar-claude"
PRODUCTION_BRIDGES=("$PRODUCTION_CLAUDE")
BRIDGES=("$CLAUDE_BRIDGE")

cat >"$SHIMS/git" <<'SHIM'
#!/usr/bin/env bash
if [[ ${1:-} == config && ${2:-} == --get && -e $(dirname -- "$0")/consent-error ]]; then exit 5; fi
exec /usr/bin/git "$@"
SHIM
chmod 755 "$SHIMS/git"

cat >"$SHIMS/claude" <<'SHIM'
#!/usr/bin/env bash
source "$(dirname -- "$0")/shim.env"
if [[ ${1:-} == --version ]]; then
  if [[ $SPAR_TEST_MODE == bad-version ]]; then printf '%s\n' "$SPAR_TEST_REPLY"; else printf '2.1.261 (Claude Code)\n'; fi
  exit
fi
[[ -z ${CLAUDE_CODE_EFFORT_LEVEL:-} ]] || exit 89
[[ ${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-} == 1 && ${DISABLE_AUTOUPDATER:-} == 1 ]] || exit 88
if [[ " $* " == *' auth status '* ]]; then
  printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty"}'
  exit
fi
printf '%s\n' "$*" >>"$SPAR_TEST_CALLS"
printf '%s\0' "$@" >"$SPAR_TEST_CALLS.argv"
printf '%s\n' "$PWD" >>"$SPAR_TEST_CALLS.pwd"
env >"$SPAR_TEST_CALLS.env"
cat >"$SPAR_TEST_CALLS.stdin"
session="33333333-3333-4333-8333-333333333333"
case ${SPAR_TEST_MODE:-ok} in
  ok|bad-version) jq -cn --arg s "$session" '{type:"result",is_error:false,result:"review ok",session_id:$s}' ;;
  metadata) jq -cn --arg s "$session" --arg m "$SPAR_TEST_REPLY" '{type:"result",is_error:false,result:"review ok",session_id:$s,modelUsage:{($m):{}},usage:{service_tier:"standard"},model:"configured-not-effective",effort:"configured-not-effective"}' ;;
  metadata-tier) jq -cn --arg s "$session" --arg t "$SPAR_TEST_REPLY" '{type:"result",is_error:false,result:"review ok",session_id:$s,modelUsage:{"claude-observed-fixture":{}},usage:{service_tier:$t}}' ;;
  malformed-metadata) jq -cn --arg s "$session" --arg m "$SPAR_TEST_REPLY" '{type:"result",is_error:false,result:"review ok",session_id:$s,modelUsage:$m}' ;;
  reply) jq -cn --arg s "$session" --arg t "$SPAR_TEST_REPLY" '{type:"result",is_error:false,result:$t,session_id:$s}' ;;
  failure) printf 'reviewer failed while reading .env policy\n' >&2; exit 1 ;;
  error-result) jq -cn '{type:"result",is_error:true,result:"review failed"}' ;;
  limit) jq -cn '{type:"result",is_error:true,result:"usage limit reached"}' ;;
  hang)
    trap '' TERM
    (trap '' TERM; while :; do sleep 1; done) &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    while :; do sleep 1; done ;;
esac
SHIM

chmod 755 "$SHIMS/claude"

configure_shims() { # mode calls-file [reply-text] [child-pid-file]
  printf 'SPAR_TEST_MODE=%q\nSPAR_TEST_CALLS=%q\nSPAR_TEST_REPLY=%q\nSPAR_TEST_CHILD_PID=%q\n' \
    "$1" "$2" "${3:-}" "${4:-}" >"$SHIMS/shim.env"
}

# Credential-shaped fixtures are assembled here so no literal exists on disk.
token=$(printf '%s%s' 'sk-' 'UNKNOWNFIXTURE0123456789ABCDEF')
key_name=$(printf '%s_%s' 'OPENAI_API' 'KEY')
envelope=$(printf '%s %s' '-----BEGIN TEST PRIVATE' 'KEY-----')
github_token=$(printf '%s%s' 'ghp_' 'PUBLICFIXTURE0123456789AB')

# --- Scanner ---
printf 'Review ordinary material.' | "$SCANNER" outbound >"$TMP/out" || fail "scanner rejected a safe request"
[[ $(<"$TMP/out") == 'Review ordinary material.' ]] || fail "scanner did not preserve a safe request"

printf 'plan body\n' >"$TMP/art/spar-plan.md"
printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/spar-plan.md" >"$TMP/out" || fail "scanner rejected a safe artifact"
[[ $(<"$TMP/out") == *'===== artifact: spar-plan.md ====='*'plan body'*'===== end artifact: spar-plan.md ====='* ]] ||
  fail "scanner did not inline the artifact with delimiters"
if printf 'Review.' | "$SCANNER" outbound "$TMP/art/spar-plan.md" >/dev/null 2>&1; then fail "artifact accepted without a root"; fi
printf 'operand, not an option\n' >"$TMP/art/--root"
printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/--root" >/dev/null || fail "scanner treated an operand as an option"
if [[ $TMP == /tmp/opencode/* || $TMP == /tmp/claude-*/* || $TMP == /tmp/codex*/* ]]; then
  if printf 'Review.' | "$SCANNER" outbound --root "$TMP" -- "$TMP/art/spar-plan.md" >/dev/null 2>&1; then
    fail "scanner accepted another tool session through a broad root rather than caller scratch"
  fi
fi
for scratch in /tmp /var/tmp /tmp/opencode "$TMP/art"; do
  if printf 'Review.' | "$SCANNER" outbound --scratch-root "$scratch" -- >/dev/null 2>&1; then
    fail "scanner accepted a shared or non-private scratch root: $scratch"
  fi
done

if printf '' | "$SCANNER" outbound >/dev/null 2>&1; then fail "empty request passed scanner"; fi
printf 'binary\0content' >"$TMP/art/payload.bin"
if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/payload.bin" >/dev/null 2>&1; then fail "binary artifact passed scanner"; fi
printf '\377' >"$TMP/art/latin.md"
if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/latin.md" >/dev/null 2>&1; then fail "non-UTF-8 artifact passed scanner"; fi
printf 'outside\n' >"$HOMEBOX/outside.md"
ln -s -- "$TMP/art/spar-plan.md" "$TMP/art/linked-inside.md"
ln -s -- "$HOMEBOX/outside.md" "$TMP/art/linked-outside.md"
printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/linked-inside.md" >/dev/null 2>&1 || fail "symlink to a confined artifact was rejected"
if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/linked-outside.md" >/dev/null 2>&1; then fail "symlink to an outside file passed scanner"; fi
if printf 'Review.' | "${SCAN_OUT[@]}" "$HOMEBOX/outside.md" >/dev/null 2>&1; then fail "artifact outside every root passed scanner"; fi
mkdir -p "$TMP/art/secrets" "$TMP/art/.git"
printf 'harmless\n' >"$TMP/art/secrets/ordinary.md"
printf 'harmless\n' >"$TMP/art/.git/HEAD"
printf 'harmless\n' >"$TMP/art/.env"
for path in "$TMP/art/secrets/ordinary.md" "$TMP/art/.git/HEAD" "$TMP/art/.env"; do
  if printf 'Review.' | "${SCAN_OUT[@]}" "$path" >/dev/null 2>&1; then fail "artifact under a sensitive or Git-internal path passed scanner: $path"; fi
done
ln -- "$TMP/art/spar-plan.md" "$TMP/art/hard-linked.md"
if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/hard-linked.md" >/dev/null 2>&1; then fail "hard-linked artifact passed scanner"; fi
rm -- "$TMP/art/hard-linked.md"
mkfifo "$TMP/art/pipe.md"
if timeout 5 "${SCAN_OUT[@]}" "$TMP/art/pipe.md" <<<'Review.' >/dev/null 2>&1; then fail "FIFO artifact passed scanner"; fi
[[ $? != 124 ]] || fail "FIFO artifact hung the scanner"
if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/missing.md" >/dev/null 2>&1; then fail "missing artifact passed scanner"; fi
python3 -c 'import sys; sys.stdout.write("x" * (512 * 1024 + 1))' >"$TMP/art/oversized.md"
if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/oversized.md" >/dev/null 2>&1; then fail "oversized artifact passed scanner"; fi
for index in 1 2 3; do python3 -c 'import sys; sys.stdout.write("x" * 400000)' >"$TMP/art/big$index.md"; done
if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/big1.md" "$TMP/art/big2.md" "$TMP/art/big3.md" >/dev/null 2>&1; then
  fail "oversized aggregate payload passed scanner"
fi
if python3 -c 'import sys; sys.stdout.write("x" * (256 * 1024 + 1))' | "$SCANNER" outbound >/dev/null 2>&1; then
  fail "oversized request passed scanner"
fi

printf '%s=%s\n' "$key_name" "$token" >"$TMP/art/leak.md"
rc=0
diagnostic=$(printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/leak.md" 2>&1 >/dev/null) || rc=$?
[[ $rc == 2 && $diagnostic != *"$token"* ]] || fail "credential assignment passed scanner or leaked into diagnostics"
for content in "$envelope" "$github_token" "$(printf 'AKIA%s' 'PUBLICFIXTURE123')" \
  "$(printf '//registry.example.invalid/:_%s=%s' 'authToken' 'PUBLICPACKAGEAUTH123')" \
  "$(printf 'machine example.invalid\n%s %s' 'password' 'PUBLICNETRC123')"; do
  printf '%s\n' "$content" >"$TMP/art/vector.md"
  if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/vector.md" >/dev/null 2>&1; then
    fail "credential-shaped fixture passed scanner"
  fi
done
printf '%s=placeholder-token\n//registry.example.invalid/:_%s=example-token\n%s=%s\n' \
  "$key_name" 'authToken' 'PASSWORD' "\${PASSWORD}" >"$TMP/art/placeholders.md"
printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/placeholders.md" >/dev/null 2>&1 ||
  fail "scanner rejected documented placeholder values"
# Secrets in shapes the assignment rule used to miss are rejected.
for content in "$(printf 'AWS_SECRET_ACCESS_%s=%s' 'KEY' 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYRUNTIMEVALUE1')" \
  "$(printf 'DATABASE_URL=postgres:%s//app:%s@db.internal/app' '' 'Hunter2Runtime')" \
  "$(printf 'GITHUB_%s: %s' 'TOKEN' 'literal-runtime-value-9f8e7d')" \
  "$(printf '%s = "%s"' 'passphrase' 'literal runtime words')" \
  "$(printf 'API_%s=SecretStr("%s")' 'TOKEN' 'literal-runtime-value-9f8e7d')" \
  "$(printf 'API_%s=os.getenv("API_TOKEN", "%s")' 'TOKEN' 'literal-runtime-value-9f8e7d')"; do
  printf '%s\n' "$content" >"$TMP/art/shape.md"
  if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/shape.md" >/dev/null 2>&1; then
    fail "credential shape passed scanner: ${content%%[=:]*}"
  fi
done
# Code that handles credentials without containing one is accepted.
{
  printf '%s = get_password()\n' 'password'
  printf '%s: os.environ["CLIENT_SECRET"]\n' 'client_secret'
  printf 'export %s="%s"\n' 'CLIENT_SECRET' "\$SECRET"
  printf '%s=%s\n' 'token' "\$(vault read -field=token secret/app)"
  printf '%s: process.env.API_KEY\n' 'api_key'
  printf 'DATABASE_URL=postgres:%s//app:%s@db.internal/app\n' '' "\${DB_PASSWORD}"
  printf '%s: null\n' 'passphrase'
  printf '%s: {{ secrets.aws }}\n' 'AWS_SECRET_ACCESS_KEY'
  printf '%s = vault.read("secret/data/app")\n' 'password'
  printf '%s = SecretStr(os.environ["DB_PASSWORD"])\n' 'password'
} >"$TMP/art/code.md"
printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/code.md" >/dev/null 2>&1 ||
  fail "scanner rejected credential-handling code without a literal secret"
# Generate scanner fixtures from label/value pairs rather than embedding
# credential assignments as literals in this test's own source.
python3 - "$SCANNER" "$TMP" <<'PY'
from pathlib import Path
import runpy
import subprocess
import sys

scanner = sys.argv[1]
policy = runpy.run_path(scanner)
count = 0

def declaration(name, value):
    return name + " = " + value + "\n"

def check(source, accepted, mode="reply"):
    global count
    result = subprocess.run([scanner, mode], input=source.encode('utf-8'), capture_output=True)
    assert result.returncode == (0 if accepted else 2), (mode, accepted, result.stderr)
    assert b"opaque-material-49a8" not in result.stderr, "scanner disclosed rejected fixture bytes"
    if not accepted:
        assert not result.stdout, "scanner emitted rejected fixture bytes"
    elif mode == "outbound":
        assert result.stdout == source.encode('utf-8'), "scanner changed accepted payload bytes"
    count += 1

# Equality operators are code, but ambiguous values keep the normal safeguards.
# Build the expressions so this fixture source contains no credential assignments.
for operator in ("==", "==="):
    for spacing in ("", " "):
        for operand in ('"page"', '"true"', "null", "false", "process.env.REVIEW_STATE"):
            source = "token" + spacing + operator + spacing + operand + "\n"
            check(source, True)
            check(source, True, "outbound")
            # Keep the original expression unchanged. A complete semicolonless
            # return supplies visible closing evidence, not an inserted `;`.
            complete = "export function isPage(token: string) {\n  return (\n    " + source + "  )\n}\n"
            patch = "diff --git a/view.ts b/view.ts\n" + "\n".join("+" + line for line in complete.split("\n"))
            check(patch, True, "diff")

for source in (
    declaration("TOKEN", repr("opaque-material-49a8")),
    declaration("TOKEN", repr("==page")),
    declaration("TOKEN", "=opaque-material-49a8"),
    "TOKEN" + ": =1234567890\n",
    "https://app:" + "=1234567890@example.invalid/\n",
    "token" + " === " + repr("opaque-material-49a8") + "\n",
    "token" + ' === "page" && ' + declaration("TOKEN", repr("opaque-material-49a8")),
    "token" + " === process.env.REVIEW_STATE; " + declaration("TOKEN", "`opaque-material-49a8`"),
    "token" + ' === get_state("page"); ' + declaration("TOKEN", "`opaque-material-49a8`"),
    "token" + " === " + repr("sk-" + "a" * 24) + "\n",
):
    check(source, False)
    check(source, False, "outbound")
    check("diff --git a/view.ts b/view.ts\n+" + source, False, "diff")

print(f"ok: bounded equality comparisons ({count} acceptance/refusal cases)")
count = 0

def check_comparison_source(source, accepted, patch_accepted=None):
    check(source, accepted)
    check(source, accepted, "outbound")
    if patch_accepted is None:
        patch_accepted = accepted
    # Keep physical LF boundaries, including CR/Unicode-control refusal cases.
    patch = "diff --git a/view.ts b/view.ts\n" + "\n".join("+" + line for line in source.split("\n"))
    for mode in ("reply", "outbound", "diff"):
        check(patch, patch_accepted, mode)

comparison = "token" + ' === "page"'
for ending in ("", "\n", "\r\n", "\n\n// ordinary comment\n"):
    check_comparison_source(comparison + ending, True, False)
for source in (
    comparison + ";", comparison + ";\n", comparison + "\n;\n",
    comparison + "; // ordinary comment\n",
    "token" + ' ===\n    "page";\n',
    "token" + ' ===\n    // ordinary comment\n    "page";\n',
    comparison + "\nconst label = renderPage();\n",
    comparison + "\n// ordinary comment\nnext = renderPage();\n",
    "function render() {\n  " + comparison + "\n  return label;\n}\n",
    "if (\n  " + comparison + "\n) {\n  renderPage();\n}\n",
    "if (\n  " + comparison + ") { // ordinary comment\n  renderPage();\n}\n",
    "if (\n  " + comparison + "\n)\n{\n  renderPage();\n}\n",
    "function isPage() {\n  return ((\n    " + comparison + "\n  ));\n}\n",
):
    check_comparison_source(source, True)

# A physical line end, blank/comment, or bare closer cannot hide a continued
# operand/expression. Exercise both quoted literals and environment operands.
for operand in ('"page"', "process.env.REVIEW_STATE"):
    for separator in ("\n", "\n\n// ordinary comment\n", "\r\n"):
        for trailer in ('+ "opaque-material-49a8"', '?? "opaque-material-49a8"',
                        '&& "opaque-material-49a8"', '("opaque-material-49a8")',
                        '.concat("opaque-material-49a8")', '["opaque-material-49a8"]'):
            check_comparison_source("token" + " === " + operand + separator + trailer, False)
for trailer in ('+ "opaque-material-49a8"', '? "ordinary" : "opaque-material-49a8"',
                "as SomeType", "satisfies SomeType", ", other", '"opaque-material-49a8"'):
    check_comparison_source(comparison + "\n" + trailer, False)
    check_comparison_source("const result = (\n  " + comparison + "\n)\n" + trailer, False)
for trailer in ('; ' + declaration("TOKEN", repr("opaque-material-49a8")),
                '); ' + declaration("TOKEN", repr("opaque-material-49a8")),
                ') { ' + declaration("TOKEN", repr("opaque-material-49a8")),
                '/* ordinary comment */\n+ "opaque-material-49a8"'):
    check_comparison_source(comparison + trailer, False)
for source in (
    "token" + " ===\n", "token" + ' =\n== "page";',
    comparison + "\n" * 130 + '+ "opaque-material-49a8"',
    comparison + " " * 16400 + ";", comparison + "\r",
):
    check_comparison_source(source, False)
for separator in ("\r", "\v", "\f", "\x85", "\u2028", "\u2029"):
    check_comparison_source(comparison + "\n// ordinary comment" + separator + '+ "opaque-material-49a8"', False)

# Terminating one comparison never exempts later assignments or the independent
# provider/private-key detectors, including data after a conditional header.
for terminator in (";\n", "\n", ") {\n"):
    for source in (
        declaration("TOKEN", repr("opaque-material-49a8")),
        "TOKEN" + ": =1234567890\n",
        "https://app:" + "=1234567890@example.invalid/\n",
        "sk-" + "a" * 24 + "\n",
        "-----BEGIN TEST PRIVATE " + "KEY-----\n",
    ):
        check_comparison_source(comparison + terminator + source, False)

patch_head = "diff --git a/view.ts b/view.ts\n+" + comparison + "\n"
for boundary in ("@@ -20,1 +20,1 @@", "diff --git a/other.ts b/other.ts",
                 "#", " unchanged context", "-removed line", r"\ No newline at end of file"):
    for mode in ("reply", "outbound", "diff"):
        check(patch_head + boundary + "\n+;\n", False, mode)
        # A visible terminator before an omission already proves completion.
        check(patch_head.replace(comparison, comparison + ";") + boundary + "\n+ordinary\n", True, mode)
for mode in ("reply", "outbound", "diff"):
    check(patch_head + '+\n+// ordinary comment\n++ "opaque-material-49a8"\n', False, mode)
    check(patch_head + '+)\n++ "opaque-material-49a8"\n', False, mode)
    check(patch_head + "+) {\n+  renderPage();\n+}\n", True, mode)
    # Visible context is evidence for comparison termination in every mode;
    # it is not newly published content for the diff mode's other detectors.
    check(patch_head + " ) {\n+  renderPage();\n+}\n", True, mode)
for header in ("diff --git a/view.ts b/view.ts\n", "--- a/view.ts\n+++ b/view.ts\n",
               "@@ -1,1 +1,1 @@\n"):
    for mode in ("reply", "outbound"):
        check(header + " " + comparison + "\n", False, mode)
        # A one-sided terminator leaves the other image unproved at patch EOF.
        check(header + " " + comparison + "\n+;\n", False, mode)

print(f"ok: bounded multiline comparison termination ({count} acceptance/refusal cases)")
count = 0

# Keep H's supplied whole-source reproducer byte-for-byte, including its lack
# of semicolons/final newline. The original website regression is below.
semicolonless_ts = (
    'export function isPage(token: string) {\n'
    '  return (\n'
    '    token === "page"\n'
    '  )\n'
    '}'
)
check_comparison_source(semicolonless_ts, True)
check_comparison_source(semicolonless_ts.replace("\n", "\r\n"), True)
for expression in (
    comparison,
    comparison + ' ? "current" : "other"',
    comparison + '\n      ? "current"\n      : "other"',
    comparison + '\n      ? // ordinary comment\n        "current"\n      : false',
    comparison + '\n      ? process.env.PAGE_LABEL\n      : process.env.TEXT_LABEL',
):
    source = semicolonless_ts.replace(comparison, expression)
    check_comparison_source(source, True)
    # Realistic edited-line patch: the function and return closers are context,
    # not additions. Earlier unequal-length rows must not skew source matching.
    patch = ('diff --git a/view.ts b/view.ts\n@@ -1,6 +1,6 @@\n'
             '-// an old, much longer explanatory comment\n+// updated\n'
             ' export function isPage(token: string) {\n   return (\n'
             + '\n'.join('+    ' + line for line in expression.split('\n'))
             + '\n   )\n }\n')
    for mode in ("reply", "outbound", "diff"):
        check(patch, True, mode)

# No terminator/comment may be recognized through an escaped quote. Keep both
# quote styles, benign-but-unsupported escapes and escapes in ternary branches.
for expression in (
    "token" + r' === "page\"; //opaque-material-49a8";',
    "token" + r" === 'page\'; //opaque-material-49a8';",
    "token" + r' === "page\\";',
    "token" + r' === "pa\u0067e";',
    "token" + ' === "page\\\nopaque-material-49a8";',
    comparison + r' ? "on\"; //opaque-material-49a8" : "off";',
    comparison + r' ? "on" : "off\"; //opaque-material-49a8";',
):
    check_comparison_source(expression, False)
    check_comparison_source(semicolonless_ts.replace(comparison, expression), False)

quoted_punctuation = "token" + ' === "page; // label"'
check_comparison_source(quoted_punctuation, True, False)
check_comparison_source(quoted_punctuation + '\n+ "opaque-material-49a8"', False)
for expression in (
    comparison + ' ? "current" : "opaque-material-49a8"',
    comparison + ' ? "opaque-material-49a8" : "other"',
    comparison + ' ? "current" : "other" + "opaque-material-49a8"',
    comparison + ' ? "current" : "other"\n+ "opaque-material-49a8"',
    comparison + ' ? renderPage() : renderText()',
    comparison + ' ? "current" : "other" ? "nested" : "conditional"',
    comparison + ' ? "current"', comparison + ' ? "current" :',
    comparison + ' ? "current" : "other"; ' + declaration("TOKEN", repr("opaque-material-49a8")),
):
    check_comparison_source(semicolonless_ts.replace(comparison, expression), False)

for mode in ("reply", "outbound", "diff"):
    for continuation in (' + "opaque-material-49a8"', ' ) + "opaque-material-49a8"',
                         ' // ordinary comment\n + "opaque-material-49a8"',
                         ' )\n@@ -30,1 +30,1 @@\n }', ' )\n-removed context\n }'):
        check(patch_head + continuation + '\n }\n', False, mode)
    check(patch_head + ' // ordinary comment\n )\n }\n', True, mode)
    check(patch_head + ' ? "current"\n : "other"\n )\n }\n', True, mode)
    check(patch_head + ' ? "current"\n@@ -30,1 +30,1 @@\n : "other"\n )\n }\n', False, mode)

# Context-assisted comparison validation does not expose removed/context
# payloads to addition-only detectors, or exempt newly added credential bytes.
context_assignment = declaration("TOKEN", repr("opaque-material-49a8"))
check('diff --git a/view.ts b/view.ts\n ' + context_assignment + '+' + comparison + '\n )\n }\n', True, 'diff')
for added in (context_assignment, "TOKEN" + ": =1234567890\n",
              "https://app:" + "=1234567890@example.invalid/\n",
              "sk-" + "a" * 24 + "\n", "-----BEGIN TEST PRIVATE " + "KEY-----\n"):
    check(patch_head + ' )\n }\n+' + added, False, 'diff')

print(f"ok: escape-safe literals and unchanged semicolonless/ternary use ({count} acceptance/refusal cases)")
count = 0

# Original Header.tsx:40-47, read-only verified on 2026-09-14. Preserve the
# complete eight lines exactly, including quotes, indentation and semicolons.
# Tests have no dependency on that external checkout; production has no path
# or source-string whitelist. This fixture is the actual reported use case.
original_website_tsx = (
    'type CurrentToken = "page" | "true" | undefined;\n'
    '\n'
    'const currentAttribute = (token: CurrentToken) =>\n'
    '  token === "page"\n'
    '    ? \' aria-current="page"\'\n'
    '    : token === "true"\n'
    '      ? \' aria-current="true"\'\n'
    '      : "";\n'
)
check_comparison_source(original_website_tsx, True)
check_comparison_source(original_website_tsx.replace("\n", "\r\n"), True)
addition_patch = ('diff --git a/Header.tsx b/Header.tsx\nnew file mode 100644\n'
                  '--- /dev/null\n+++ b/Header.tsx\n@@ -0,0 +1,8 @@\n'
                  + ''.join('+' + line for line in original_website_tsx.splitlines(keepends=True)))
context_rows = []
for index, line in enumerate(original_website_tsx.splitlines(keepends=True)):
    if index == 3:
        context_rows += ['-  Boolean(token)\n', '+' + line]
    else:
        context_rows.append(' ' + line)
assert ''.join(line[1:] for line in context_rows if line[0] in ('+', ' ')) == original_website_tsx
context_patch = ('diff --git a/Header.tsx b/Header.tsx\n--- a/Header.tsx\n+++ b/Header.tsx\n'
                 '@@ -40,8 +40,8 @@\n' + ''.join(context_rows))
for mode in ('reply', 'outbound', 'diff'):
    check(addition_patch, True, mode)
    check(context_patch, True, mode)

# Generic comparisons and either branch can nest. Names resembling constants
# must remain whole identifiers, not accidentally become a `true`/`null` prefix.
def conditional(name, yes='"on"', no='"off"'):
    return name + ' === "kind" ? ' + yes + ' : ' + no

for expression in (
    comparison + ' ? ' + conditional('kind') + ' : "";',
    comparison + ' ? "" : ' + conditional('kind') + ';',
    comparison + ' ? ' + conditional('trueFlag', conditional('other')) + ' : ' + conditional('nullFlag') + ';',
    comparison + ' ? "" : kind\n ===\n "other"\n ? "on"\n : "off";',
):
    check_comparison_source(expression, True)
check_comparison_source(original_website_tsx.replace('token === "true"', 'kind == "active"'), True)
check_comparison_source(original_website_tsx.replace('"page"', '"section"'), True)

# A complete nested expression can use raw-input EOF; a patch fragment cannot
# invent source EOF or hide a continuation beyond the visible image.
without_final_semicolon = original_website_tsx[:-2] + '\n'
check_comparison_source(without_final_semicolon, True, False)
check_comparison_source(without_final_semicolon + '+ "opaque-material-49a8"\n', False)
for condition in (
    'readToken() === "true"', 'token.kind === "true"', 'token["kind"] === "true"',
    '(token = "true")', 'token' + ' = "true"', 'token' + ': "true"',
    'token' + ' === readKind()', 'token' + ' === ["true"]', 'token' + ' === "opaque-material-49a8"',
    'token' + ' === "true" + "opaque-material-49a8"',
    'token' + ' === "true"; ' + declaration('TOKEN', repr('opaque-material-49a8')).strip(),
    'token' + ' === trueValue', 'token' + ' === "true" as Kind',
):
    check_comparison_source(original_website_tsx.replace('token === "true"', condition), False)
for branch in (
    '"opaque-material-49a8"', 'readLabel()', 'label.value', 'label["value"]', 'label',
    '"on" + "opaque-material-49a8"', '"on"\n+ "opaque-material-49a8"',
    r'"on\"; //opaque-material-49a8"', r"'on\'; //opaque-material-49a8'",
    declaration('TOKEN', repr('opaque-material-49a8')).strip(),
):
    for yes, no in ((branch, '"off"'), ('"on"', branch)):
        check_comparison_source(comparison + ' ? "" : ' + conditional('kind', yes, no) + ';', False)
for malformed in (
    comparison + ' ? kind === "other" ? "on" : "off";',  # missing outer else
    comparison + ' ? "" : kind === "other" ? "on";',      # missing inner else
    comparison + ' ? "" : kind === "other" ? : "off";',  # missing true branch
    comparison + ' ? "" : kind === "other";',             # incomplete nested condition
    comparison + ' ? "" : kind === "other" ? "on" : ;',
    comparison + ' ? "" : kind === "other" ? "on" : "off" : "extra";',
    comparison + ' ? "" : kind === "other" ? "on"; : "off";',
    comparison + ' ? "" : kind === "other" ? "on" : "off"; ' + declaration('TOKEN', repr('opaque-material-49a8')),
):
    check_comparison_source(malformed, False)
for boundary in ('@@ -60,1 +60,1 @@', '-removed image', '#', 'diff --git a/other.ts b/other.ts'):
    for marker in ('+', ' '):
        patch = (patch_head + marker + '? "" : kind === "other"\n' + boundary
                 + '\n' + marker + '? "on" : "off";\n')
        for mode in ('reply', 'outbound', 'diff'):
            check(patch, False, mode)
for separator in ('\r', '\v', '\x85', '\u2028', '\u2029'):
    check_comparison_source(comparison + ' ? "" : kind === "other"\n// comment' + separator + '? "on" : "off";', False)

# Independent resource witnesses: a linear chain reaches the depth limit;
# a shallow branching tree exhausts tokens while staying below depth/size/line
# limits. Existing multiline/character-bound witnesses continue running above.
for depth, accepted in ((8, True), (9, False)):
    branch = '"off"'
    for _ in range(depth - 1):
        branch = conditional('kind', '"on"', branch)
    check_comparison_source(comparison + ' ? "on" : ' + branch + ';', accepted)
def tree(depth):
    return '"off"' if not depth else conditional('kind', tree(depth - 1), tree(depth - 1))
for depth, accepted in ((5, True), (6, False)):
    check_comparison_source(comparison + ' ? ' + tree(depth - 1) + ' : ' + tree(depth - 1) + ';', accepted)
for reference, accepted in (('k' * 128, True), ('k' * 129, False)):
    check_comparison_source(comparison + ' ? "" : ' + conditional(reference) + ';', accepted)

print(f"ok: exact original TSX and bounded nested conditionals ({count} acceptance/refusal cases)")
count = 0

inventories = (
    ("SECRET_DIRS", [".ssh", ".aws", ".gnupg", ".kube", ".mozilla", "secrets"], "{}"),
    ("SECRET_FILES", [".env", ".envrc", ".netrc", ".npmrc", ".pypirc", "auth.json", "credentials",
                      ".credentials.json", ".bash_history", ".zsh_history", "id_rsa", "id_dsa",
                      "id_ecdsa", "id_ed25519"], "{}"),
    ("SECRET_GLOBS", [".env.*", "credentials.*", "*.key", "*.pem", "*.p12", "*.pfx", "*.keytab", "ssh_host_*_key"], "()"),
    ("SECRET_SUFFIXES", [".config/gh/hosts.yml", ".docker/config.json", ".hermes/config.yaml", ".codex/config.toml"], "()"),
    ("SECRET_TREES", [".config/BraveSoftware", ".config/chromium", ".local/share/keyrings"], "()"),
)
for name, values, brackets in inventories:
    for multiline in (False, True):
        body = (",\n    " if multiline else ", ").join(map(repr, values)) + ","
        value = brackets[0] + ("\n    " if multiline else "") + body + ("\n" if multiline else "") + brackets[1]
        source = declaration(name, value)
        check(source, True)
        check("diff --git a/policy.py b/policy.py\n" + "\n".join("+" + line for line in source.splitlines()), True, "diff")
        assert not policy["content_findings"]("fixture", source, True)

for value in ("[]", "()", "{}", "['.ssh']", "{\n\n    '.env',\n}"):
    check(declaration("OTHER_SECRET_PATHS", value), True)
    check("\n".join("+" + line for line in declaration("OTHER_SECRET_PATHS", value).splitlines()), True, "diff")

for value in (
    "{'opaque-material-49a8'}", "['.ssh', 'opaque-material-49a8']",
    "{'api_key': 'opaque-material-49a8'}", "[['.ssh']]", "{'.env': '.ssh'}",
    "[None]", "[1]", "[b'.ssh']", "[name]", "[str('.ssh')]", "[p for p in ['.ssh']]",
    "['.ssh'] + ['opaque-material-49a8']", "['.ssh']; other = 'opaque-material-49a8'",
    "['.ssh'] # opaque-material-49a8", "{\n    '.ssh', # comment\n}",
    "{", "['.ssh'", "['.ssh',", "('.ssh')", "['line\\nbreak.pem']",
    r"['.ssh/\qopaque-material-49a8']",
    "['https://example.invalid/private.pem']", "['a' * 200]",
    "[" + ",".join(["'.ssh'"] * 257) + "]",
    "(\n" + "\n" * 128 + "'.ssh',\n)",
    "['.ssh']" + " " * 17000 + "+ ['opaque-material-49a8']",
):
    check(declaration("SECRET_FILES", value), False)
    check("\n".join("+" + line for line in declaration("SECRET_FILES", value).splitlines()), False, "diff")

# Metadata names do not exempt scalar values or generic value collections.
# The two earlier code-value watch cases remain conservative refusals.
for name, value in (("API_KEY", repr("opaque-material-49a8")), ("SECRET", "['.ssh']"),
                    ("TOKEN", 'payload["item"]'), ("TOKEN", '"$1"')):
    check(declaration(name, value), False)

provider_value = "sk-" + "a" * 24
check(declaration("SECRET_FILES", repr([".ssh/" + provider_value])), False)
check(declaration("SECRET_FILES", "['.ssh/\\x73k-" + "a" * 24 + "']"), False)
check(declaration("SECRET_FILES", "['.ssh']") + declaration("API_KEY", repr(provider_value)), False)
for separator in ("\r", "\v", "\f", "\x85", "\u2028"):
    check(declaration("SECRET_FILES", "['.ssh']" + separator + declaration("API_KEY", repr("opaque-material-49a8")).rstrip("\n")), False)

# An enclosing mapping/call permits implicit continuation after a literal that
# parses by itself. Check the complete RHS, not just its first physical line.
for suffix in ("+ ['opaque-material-49a8']", "or ['opaque-material-49a8']",
               "if condition else ['opaque-material-49a8']", "[0]", ".copy()", "()"):
    for lead, middle, end in (("settings = {\n", '    "SECRET_FILES": ', "\n}\n"),
                             ("settings = build(\n", "    SECRET_FILES = ", "\n)\n")):
        source = lead + middle + "['.ssh']\n        " + suffix + end
        check(source, False)
        check("diff --git a/policy.py b/policy.py\n" + "\n".join("+" + line for line in source.splitlines()), False, "diff")
check('settings = {\n    "SECRET_FILES": [".ssh"]\n}\n', True)
check('settings = build(\n    SECRET_FILES = [".ssh"]\n)\n', True)
for separator in ("\r", "\v", "\f", "\x00", "\x85", "\u2028", "\u2029"):
    source = ('settings = {\n    "SECRET_FILES": [".ssh"]\n    # note' + separator
              + '    + ["opaque-material-49a8"]\n}\n')
    check(source, False)
    # Preserve embedded separators instead of normalizing them via splitlines.
    check("diff --git a/policy.py b/policy.py\n" + "\n".join("+" + line for line in source.rstrip("\n").split("\n")), False, "diff")
check(declaration("SECRET_FILES", "['.ssh']") + "\n" * 130 + "+ ['opaque-material-49a8']", False)
check("+" + declaration("SECRET_FILES", "['.ssh']") + " unchanged context", False, "diff")

# Omitted context/hunk boundaries must not become a false complete collection.
# Actual added blank lines, tested above, remain supported.
for boundary in ("    '.ssh',", "@@ -20,1 +20,1 @@", "-    '.ssh',"):
    source = "diff --git a/policy.py b/policy.py\n+" + declaration("SECRET_FILES", "{").rstrip("\n")
    check(source + "\n" + boundary + "\n+}\n", False, "diff")

print(f"ok: bounded path-metadata collections ({count} acceptance/refusal cases)")
count = 0

# Exact complete Hermes hunk from the refused Safety preflight patch, including
# old declarations, unchanged inventories and the replacement's wrapped rows.
# Keep this fixture independent of the worktree, Git/index and temporary audit
# artifact. Quoted rows keep this test source reviewable by the same scanner.
preflight_header = (
    'diff --git c/hermes/.hermes/plugins/eyragents/__init__.py w/hermes/.hermes/plugins/eyragents/__init__.py\n'
    '--- c/hermes/.hermes/plugins/eyragents/__init__.py\n'
    '+++ w/hermes/.hermes/plugins/eyragents/__init__.py\n'
    '@@ -23,24 +25,56 @@ import re\n'
)
preflight_rows = (
    ' import stat\n'
    ' import subprocess\n'
    ' \n'
    '-SECRET_DIRS = {".ssh", ".aws", ".gnupg", ".kube", ".mozilla", "secrets"}\n'
    '+SECRET_DIRS = {".ssh", ".aws", ".gnupg", ".kube", ".mozilla", ".password-store", "secrets"}\n'
    ' SECRET_FILES = {\n'
    '     ".env", ".envrc", ".netrc", ".npmrc", ".pypirc", "auth.json",\n'
    '     "credentials", ".credentials.json", ".bash_history", ".zsh_history",\n'
    '     "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",\n'
    ' }\n'
    '-SECRET_GLOBS = (".env.*", "credentials.*", "*.key", "*.pem", "*.p12", "*.pfx")\n'
    '+SECRET_GLOBS = (".env.*", "credentials.*", "*.key", "*.pem", "*.p12", "*.pfx",\n'
    '+                "*.keytab", "ssh_host_*_key")\n'
    ' SECRET_SUFFIXES = (\n'
    '     ".config/gh/hosts.yml", ".docker/config.json", ".hermes/config.yaml",\n'
    '     ".codex/config.toml",\n'
    ' )\n'
    '-SECRET_TREES = (".config/BraveSoftware", ".config/chromium", ".local/share/keyrings")\n'
    '+SECRET_TREES = (".config/BraveSoftware", ".config/chromium", ".config/google-chrome",\n'
    '+                ".config/1Password", ".config/Bitwarden", ".local/share/keyrings")\n'
    '+# Component suffixes also cover recognisable copies. This finite inventory\n'
    '+# cannot identify arbitrary renamed copies or every hardlink alias.\n'
    '+SYSTEM_FILES = (\n'
    '+    "etc/shadow", "etc/shadow-", "etc/gshadow", "etc/gshadow-",\n'
    '+    "etc/security/opasswd", "etc/security/opasswd.old", "etc/krb5.keytab",\n'
    '+    "etc/ipsec.secrets", "var/lib/NetworkManager/secret_key", "var/lib/systemd/credential.secret",\n'
    '+)\n'
    '+SYSTEM_TREES = (\n'
    '+    "etc/ssl/private", "etc/credstore", "etc/credstore.encrypted",\n'
    '+    "usr/lib/credstore", "usr/lib/credstore.encrypted", "etc/cryptsetup-keys.d",\n'
    '+    "etc/NetworkManager/system-connections", "usr/lib/NetworkManager/system-connections",\n'
    '+    "var/lib/iwd", "etc/wireguard", "etc/openvpn", "etc/ipsec.d/private",\n'
    '+    "etc/samba/private", "var/lib/samba/private", "etc/pacman.d/gnupg", "etc/letsencrypt",\n'
    '+)\n'
    '+RAW_FILES = ("proc/kcore", "proc/vmcore", "dev/mem", "dev/port")\n'
    '+RAW_TREES = ("var/lib/systemd/coredump", "var/crash", "sys/kernel/debug", "sys/kernel/tracing")\n'
    '+SESSION_FILES = (".claude.json", ".claude/history.jsonl", ".codex/history.jsonl",\n'
    '+                 ".codex/session_index.jsonl", ".local/share/fish/fish_history",\n'
    '+                 ".local/state/fish/fish_history")\n'
    '+SESSION_TREES = (\n'
    '+    ".claude/projects", ".claude/sessions", ".claude/session-env", ".claude/tasks", ".claude/debug",\n'
    '+    ".codex/sessions", ".codex/archived_sessions", ".codex/log",\n'
    '+    ".local/share/opencode", ".local/state/opencode", ".cache/opencode",\n'
    '+)\n'
    '+CONFIG_STORES = ("BraveSoftware", "chromium", "google-chrome", "1Password", "Bitwarden")\n'
    '+XDG_DEFAULTS = {"XDG_CONFIG_HOME": ".config", "XDG_DATA_HOME": ".local/share",\n'
    '+                "XDG_CACHE_HOME": ".cache", "XDG_STATE_HOME": ".local/state"}\n'
    '+BROWSE_EXCLUDED = tuple(Path(p) for p in ("/home", "/root", "/proc", "/dev", "/run", "/mnt", "/media", "/Volumes"))\n'
    '+LOCAL_FILESYSTEMS = {"ext2", "ext3", "ext4", "xfs", "btrfs", "f2fs", "zfs", "erofs", "squashfs", "overlay"}\n'
    ' FILE_TOOLS = {"read_file", "search_files", "write_file", "patch"}\n'
    ' HEADER = re.compile(r"^(\\*\\*\\*\\s*(?:Update|Add|Delete)\\s+File:\\s*)(.+)$")\n'
    ' MOVE = re.compile(r"^(\\*\\*\\*\\s*Move\\s*File:\\s*)(.+?)\\s*->\\s*(.+)$")\n'
    ' _ERROR = "_eyragents_refusal"\n'
    ' _ready = False\n'
    ' OTHER_SESSION_ROOT = Path("/tmp/opencode")\n'
    '+_ALLOW_MISSING = getattr(os.path, "ALLOW_MISSING", None)\n'
    ' \n'
    ' \n'
    ' def below(path: Path, root: Path) -> bool:\n'
)
assert sum(row.startswith(('-', ' ')) for row in preflight_rows.splitlines()) == 24
assert sum(row.startswith(('+', ' ')) for row in preflight_rows.splitlines()) == 56
preflight_patch = preflight_header + preflight_rows

def check_artifact(source, accepted, name='metadata-preflight.patch'):
    global count
    artifact = Path(sys.argv[2], 'art', name)
    artifact.write_bytes(source.encode('utf-8'))
    result = subprocess.run([scanner, 'outbound', '--scratch-root', sys.argv[2], '--', str(artifact)],
                            input=b'Review.', capture_output=True)
    assert result.returncode == (0 if accepted else 2), result.stderr
    if accepted:
        assert result.stdout == (f'Review.\n\n===== artifact: {name} =====\n' + source
                                 + f'\n===== end artifact: {name} =====').encode('utf-8')
    else:
        assert not result.stdout, 'rejected artifact bytes were emitted'
    assert b'opaque-material-49a8' not in result.stderr, 'scanner disclosed rejected fixture bytes'
    count += 1

for mode in ('reply', 'outbound'):
    check(preflight_patch, True, mode)
    # Qualification follows the content, never the producer's file name.
    check(preflight_patch.replace('hermes/.hermes/plugins/eyragents/__init__.py', 'policy.py'), True, mode)
check_artifact(preflight_patch, True)

header = 'diff --git a/policy.py b/policy.py\n--- a/policy.py\n+++ b/policy.py\n@@ -1,8 +1,8 @@\n'
literal = declaration('SECRET_FILES', "['.ssh']")
terminator = 'NEXT = True\n'

# Completed old/new collections can look past a replacement, but that
# replacement cannot close the other image. Context must qualify in BOTH.
for marker, opposite in (('-', '+'), ('+', '-')):
    for start in (marker, ' '):
        for ending in (' ' + terminator, marker + terminator + opposite + terminator):
            patch = header + start + literal + opposite + '# replacement comment\n' + ending
            for mode in ('reply', 'outbound'):
                check(patch, True, mode)
        for suffix in ("+ ['opaque-material-49a8']", "or ['opaque-material-49a8']",
                       "if condition else ['opaque-material-49a8']", '[0]', '.copy()', '()'):
            for intervening in ('# replacement comment\n', terminator):
                patch = (header + start + literal + opposite + intervening
                         + marker + '    ' + suffix + '\n ' + terminator)
                for mode in ('reply', 'outbound'):
                    check(patch, False, mode)
                check_artifact(patch, False)

# Every detector still sees both full-diff sides and context, including rows
# skipped as termination evidence. The diff mode retains its addition-only
# content contract; its omitted rows never become collection evidence.
unsafe_values = (
    declaration('TOKEN', repr('opaque-material-49a8')),
    declaration('SECRET_FILES', "['.ssh', 'opaque-material-49a8']"),
    declaration('SECRET_FILES', "['.ssh'] + ['opaque-material-49a8']"),
    declaration('SECRET_FILES', "[p for p in ['.ssh']]"),
    declaration('SECRET_FILES', "['.ssh/\\x73k-" + 'a' * 24 + "']"),
    provider_value + '\n', 'ghp_' + 'a' * 24 + '\n', 'github_pat_' + 'a' * 24 + '\n',
    'AKIA' + 'A' * 16 + '\n', '-----BEGIN TEST PRIVATE ' + 'KEY-----\n',
)
for marker in ('-', '+', ' '):
    for value in unsafe_values:
        patch = (header + ' ' + literal + marker + value + ' ' + terminator)
        for mode in ('reply', 'outbound'):
            check(patch, False, mode)
        check_artifact(patch, False)
        # Only the deliberately unsafe row is added/removed/context here.
        check(patch, marker != '+', 'diff')

# A context collection's changed/unfinished interior is deliberately not
# reconstructed by joining images. Nor can either side's literal prefix hide
# a computed continuation or a missing terminator in the other image.
for mode in ('reply', 'outbound'):
    for before, after in (("'.ssh',", "'opaque-material-49a8',"),
                          ("'opaque-material-49a8',", "'.ssh',"),
                          ("'.ssh',", "'.aws',")):
        check(header + ' ' + declaration('SECRET_FILES', '[') + '-' + before + '\n+'
              + after + '\n ]\n ' + terminator, False, mode)
    for marker in ('-', '+'):
        opposite = '+' if marker == '-' else '-'
        for barrier in ('@@ -20,1 +20,1 @@\n', 'diff --git a/other.py b/other.py\n',
                        'diff --cc other.py\n', '--- a/other.py\n', '+++ b/other.py\n',
                        '#\n', '\\ No newline at end of file\n'):
            for value in ("['.ssh']", '['):
                patch = (header + marker + declaration('SECRET_FILES', value)
                         + opposite + '# replacement\n' + barrier + marker + ']\n ' + terminator)
                check(patch, False, mode)
        for ending in ('', '\n', opposite + terminator, ' \n'):
            check(header + marker + literal + opposite + '# replacement\n' + ending, False, mode)
        # Every skipped physical row/byte consumes the original bound.
        check(header + marker + literal + (opposite + '# replacement\n') * 128 + ' ' + terminator, False, mode)
        check(header + marker + literal + opposite + '#' + 'x' * 16400 + '\n ' + terminator, False, mode)
    # No patch header means no authority to skip an apparent +/- continuation.
    check('-' + literal + '+[' + repr('opaque-material-49a8') + ']\n ' + terminator, False, mode)

# The metadata suffix must qualify the whole name, not a prefix/similar word.
for name in ('SECRET_FILES_EXTRA', 'SECRETFILES', 'SECRET_FILE', 'SECRET_FILES2', 'SECRET_DIRS_API_KEY'):
    for mode in ('reply', 'outbound', 'diff'):
        check(header + '+' + declaration(name, "['.ssh']") + '+' + terminator, False, mode)

# Addition-only mode does not stitch across its omission barriers, even after
# a completed collection. Ordinary all-added literal inventories still pass.
for mode in ('reply', 'outbound', 'diff'):
    check(header + '+' + literal + '+' + terminator, True, mode)
    for suffix in ("+ ['opaque-material-49a8']", '.copy()', '[0]'):
        check(header + '+' + literal + '+    ' + suffix + '\n+' + terminator, False, mode)
for barrier in (' ' + terminator, '-' + terminator, '@@ -20,1 +20,1 @@\n', '#\n',
                'diff --git a/other.py b/other.py\n', '--- a/other.py\n', '+++ b/other.py\n'):
    check(header + '+' + literal + barrier + '+' + terminator, False, 'diff')

print(f"ok: actual Safety hunk and old/new/context metadata preflight ({count} acceptance/refusal cases)")
count = 0

def check_image_patch(rows, accepted, diff_accepted=True, path='view.ts'):
    old_count = sum(row.startswith(('-', ' ')) for row in rows.split('\n'))
    new_count = sum(row.startswith(('+', ' ')) for row in rows.split('\n'))
    patch = (f'diff --git a/{path} b/{path}\n--- a/{path}\n+++ b/{path}\n'
             + f'@@ -1,{old_count} +1,{new_count} @@\n' + rows)
    for mode in ('reply', 'outbound'):
        check(patch, accepted, mode)
    check_artifact(patch, accepted, 'comparison-preflight.patch')
    check(patch, diff_accepted, 'diff')

# Exact auditor witness: the added semicolon finishes only the new image.
# The old comparison still has a computed operand in the following context.
auditor_rows = (' let result =\n   ' + comparison + '\n+  ;\n'
                '   + "opaque-material-49a8"\n next = true\n')
old_source = 'let result =\n  ' + comparison + '\n  + "opaque-material-49a8"\nnext = true\n'
new_source = 'let result =\n  ' + comparison + '\n  ;\n  + "opaque-material-49a8"\nnext = true\n'
assert ''.join(row[1:] for row in auditor_rows.splitlines(keepends=True) if row[0] in ('-', ' ')) == old_source
assert ''.join(row[1:] for row in auditor_rows.splitlines(keepends=True) if row[0] in ('+', ' ')) == new_source
for mode in ('reply', 'outbound'):
    check(old_source, False, mode)
    check(new_source, True, mode)
check_image_patch(auditor_rows, False)
check_image_patch(auditor_rows.replace('\n', '\r\n'), False)
check_image_patch(auditor_rows.replace('+  ;', '-  ;'), False)
for unary in ('+', '-'):
    check_image_patch(auditor_rows.replace(comparison, unary + comparison), False)

context_head = ' let result =\n   ' + comparison + '\n'
for marker, opposite in (('-', '+'), ('+', '-')):
    # No operator, property, cast, conditional or escaped quote in either
    # image may borrow the other image's earlier semicolon.
    for continuation in ('+ "opaque-material-49a8"', '?? "opaque-material-49a8"',
                         '&& "opaque-material-49a8"', '.concat("opaque-material-49a8")',
                         '["opaque-material-49a8"]', '("opaque-material-49a8")',
                         '? "on" : "opaque-material-49a8"', 'as SomeType', 'satisfies SomeType'):
        check_image_patch(context_head + marker + '  ;\n   ' + continuation + '\n next = true\n', False)
        # Adjacent replacements in either order, including a new-image-only
        # literal that the addition-only assignment matcher does not detect.
        check_image_patch(context_head + marker + '  ;\n' + opposite + '  ' + continuation
                          + '\n next = true\n', False)
        check_image_patch(context_head + opposite + '  ' + continuation + '\n'
                          + marker + '  ;\n next = true\n', False)
    for branch in ('"opaque-material-49a8"', 'renderLabel()', '"on" + "opaque-material-49a8"',
                   r'"on\"; //opaque-material-49a8"'):
        check_image_patch(context_head + marker + '  ? "on" : false;\n'
                          + opposite + '  ? ' + branch + ' : false;\n', False)

    for ending in ('', '\n', ' \n', ' // ordinary comment\n', ' )\n'):
        check_image_patch(context_head + marker + '  ;\n' + ending, False)
    for boundary in ('@@ -20,1 +20,1 @@\n', 'diff --git a/other.ts b/other.ts\n',
                     'diff --cc other.ts\n', 'diff --combined other.ts\n',
                     '--- a/other.ts\n', '+++ b/other.ts\n', '#\n',
                     '\\ No newline at end of file\n'):
        check_image_patch(context_head + marker + '  ;\n' + boundary + opposite + '  ;\n', False)
        # A boundary after termination was proved in BOTH images is harmless.
        check_image_patch(context_head + '-  ;\n+  ;\n' + boundary, True)

    # Skipped rows consume physical limits and cannot hide control separators.
    check_image_patch(context_head + (marker + '// ordinary comment\n') * 128 + ' ;\n', False)
    check_image_patch(context_head + marker + '//' + 'x' * 16400 + '\n ;\n', False)
    for separator in ('\r', '\v', '\f', '\x85', '\u2028', '\u2029'):
        check_image_patch(context_head + marker + '// comment' + separator + ';\n ;\n', False)

# Both images remain usable when each has visible completion, including
# adjacent terminator/operand/conditional replacements and common context.
for ending in (' ;\n', '- ;\n+ ; // revised\n', '+ ;\n next = true\n',
               '- ;\n next = true\n',
               '- ? "on" : false;\n+ ? "off" : true;\n'):
    check_image_patch(context_head + ending, True)
    check_image_patch((context_head + ending).replace('\n', '\r\n'), True)
check_image_patch(' let result =\n   token' + ' ===\n- "page";\n+ "true";\n', True)
check_image_patch('-' + comparison + '\n-;\n+' + comparison + '\n+;\n', True)
return_head = ' function choose(token) {\n   return (\n     ' + comparison + '\n'
check_image_patch(return_head + '- )\n+ )\n }\n', True)
check_image_patch(return_head + '- )\n+ )\n', False)

# The exact new-image Header.tsx bytes survive an adjacent nested-branch edit;
# its old branch is also a bounded literal with its own visible completion.
header_rows = ''.join(('-' + line.replace('"true"', '"other"') + '+' + line) if index == 6 else ' ' + line
                      for index, line in enumerate(original_website_tsx.splitlines(keepends=True)))
assert ''.join(row[1:] for row in header_rows.splitlines(keepends=True) if row[0] in ('+', ' ')) == original_website_tsx
check_image_patch(header_rows, True)
for depth, accepted in ((5, True), (6, False)):
    check_image_patch(context_head + '- ? "on" : false;\n+ ? ' + tree(depth - 1)
                      + ' : ' + tree(depth - 1) + ';\n', accepted)

# Separate credential assignments and provider/private-key values on every
# full-patch side remain independently scanned after the comparison terminates.
for marker in ('-', '+', ' '):
    for value in (declaration('TOKEN', repr('opaque-material-49a8')),
                  'sk-' + 'a' * 24 + '\n', '-----BEGIN TEST PRIVATE ' + 'KEY-----\n'):
        check_image_patch(context_head + '- ;\n+ ;\n' + marker + value, False, marker != '+')

print(f"ok: dual-image context comparisons and auditor witness ({count} acceptance/refusal cases)")
count = 0

# Markdown +/- bullets are payload bytes, not image markers. Cross both signs,
# nested/mixed signs and indentation with both continuation directions for
# BOTH bounded exceptions, so their classification cannot silently diverge.
for bullet in ('-', '+', '- +', '+ -'):
    for indent in ('', '  ', '\t'):
        prefix = indent + bullet + ' '
        for kind, body, continuation in (
            ('metadata', literal, "  + ['opaque-material-49a8']\n"),
            ('comparison', comparison + '\n', '  + "opaque-material-49a8"\n'),
        ):
            description = prefix + body
            safe_image = description + 'NEXT = True\n'
            unsafe_image = description + continuation + 'NEXT = True\n'
            for direction in ('+', '-'):
                # Includes the exact metadata witness: context '- SECRET_FILES',
                # an added computed continuation, and context NEXT = True.
                rows = ' ' + description + direction + continuation + ' NEXT = True\n'
                old_image = ''.join(row[1:] for row in rows.splitlines(keepends=True) if row[0] in ('-', ' '))
                new_image = ''.join(row[1:] for row in rows.splitlines(keepends=True) if row[0] in ('+', ' '))
                assert old_image == (unsafe_image if direction == '-' else safe_image)
                assert new_image == (unsafe_image if direction == '+' else safe_image)
                check_image_patch(rows, False, path='policy.md')
                # All-added views preserve the EXACT reconstructed Markdown
                # images and prove the safe/unsafe contrast independently.
                # They do not reinterpret raw Markdown as a complete patch.
                for image, accepted in ((old_image, direction != '-'), (new_image, direction != '+')):
                    image_rows = ''.join('+' + row for row in image.splitlines(keepends=True))
                    check_image_patch(image_rows, accepted, accepted, path='policy.md')

            # Visible termination in each image keeps the harmless bullet usable.
            check_image_patch(' ' + description + '-NEXT = False\n+NEXT = True\n', True, path='policy.md')
            check_image_patch(' ' + description + ' NEXT = True\n', True, path='policy.md')
            # Raw handling stays as it was, including indented bullets and
            # an unmarked computed trailer. Only the comparison needs a ';'.
            raw_safe = description if kind == 'metadata' else description.rstrip('\n') + ';\n'
            for mode in ('reply', 'outbound'):
                check(raw_safe, True, mode)
                check(description + continuation, False, mode)
            check_artifact(raw_safe, True, 'raw-bullet.md')
            check_artifact(description + continuation, False, 'raw-bullet.md')

# The physical +/- column is authoritative even when the payload bullet has
# the opposite sign. Neither a same-image continuation nor an incomplete
# collection may acquire an exception from the sign deeper in that row.
for marker, bullet in (('+', '-'), ('-', '+')):
    for body, continuation in ((literal, "  + ['opaque-material-49a8']\n"),
                               (comparison + '\n', '  + "opaque-material-49a8"\n')):
        description = marker + bullet + ' ' + body
        check_image_patch(description + marker + continuation + marker + 'NEXT = True\n',
                          False, marker != '+', path='policy.md')
        check_image_patch(description + marker + 'NEXT = True\n', True, path='policy.md')
    incomplete = marker + bullet + ' ' + declaration('SECRET_FILES', '[')
    opposite = '-' if marker == '+' else '+'
    check_image_patch(incomplete + opposite + " '.ssh',\n" + marker + ']\n' + marker + 'NEXT = True\n',
                      False, marker != '+', path='policy.md')

print(f"ok: shared physical markers and reconstructed Markdown images ({count} acceptance/refusal cases)")
PY

for _ in $(seq 1 10); do printf '%s=%s\n' "$key_name" "$token"; done >"$TMP/art/many.md"
rc=0
diagnostic=$(printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/many.md" 2>&1 >/dev/null) || rc=$?
[[ $rc == 2 && $(grep -c '^SPAR-PAYLOAD FINDING:' <<<"$diagnostic") == 9 && $diagnostic == *'2 additional findings omitted'* ]] ||
  fail "scanner finding report was not bounded"

sensitive_headers=(
  'diff --git a/.env.production b/.env.production'
  'diff --git a/a/.env-old/config b/a/.env-old/config'
  'diff --git a/private.pem/key.txt b/private.pem/key.txt'
  'diff --git "a/\056env" "b/\056env"'
  'diff --git a/public secrets/x b/public secrets/x'
  'diff --cc secrets/config'
  'diff --combined private.pem'
  '--- a/.netrc'
  '+++ b/auth.json'
  'rename from credentials.old'
  'rename to id_rsa/public.txt'
  'copy to .env_bak'
  'diff --git "a/.env"x" "b/public"'
  'diff --git a/pub\lic b/public'
)
for header in "${sensitive_headers[@]}"; do
  printf '%s\n' "$header" >"$TMP/art/header.md"
  if printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/header.md" >/dev/null 2>&1; then
    fail "sensitive or malformed diff header passed scanner: $header"
  fi
done
printf '%s\n' 'diff --git "a/public\040file" "b/public\040file"' 'diff --git a/public file b/public file' \
  'diff --git "a/caf\303\251.txt" b/public file.txt' '--- a/public' $'+++ b/public\tcomment' \
  '+  diff --git a/.env b/.env' 'diff --git a/credentials-policy.md b/credentials-policy.md' >"$TMP/art/safe-headers.md"
printf 'Review.' | "${SCAN_OUT[@]}" "$TMP/art/safe-headers.md" >/dev/null 2>&1 ||
  fail "safe diff headers were rejected"

printf 'The .env path is denied.\n' | "$SCANNER" reply >/dev/null || fail "reply scanner rejected sensitive-path prose"
if printf '%s=%s\n' "$key_name" "$token" | "$SCANNER" reply >/dev/null 2>&1; then fail "reply scanner accepted a credential value"; fi
# The diff mode used by the commit and publish skills checks content and paths.
printf '%s\n' 'diff --git a/notes.md b/notes.md' '+harmless' | "$SCANNER" diff >/dev/null || fail "diff scanner rejected a safe diff"
if printf '%s\n' 'diff --git a/.env b/.env' '+harmless' | "$SCANNER" diff >/dev/null 2>&1; then fail "diff scanner accepted a sensitive path"; fi
if printf '%s\n' 'diff --git a/app.py b/app.py' "+$(printf '%s=%s' "$key_name" "$token")" | "$SCANNER" diff >/dev/null 2>&1; then
  fail "diff scanner accepted a credential value"
fi
printf '%s\n' 'diff --git a/app.py b/app.py' "-$(printf '%s=%s' "$key_name" "$token")" '+replaced' | "$SCANNER" diff >/dev/null ||
  fail "diff scanner flagged a removed line that the base already publishes"
printf '%s\n' 'diff --git a/config.toml b/config.toml' '+"secrets" = "deny"' '+secrets: allow' | "$SCANNER" diff >/dev/null ||
  fail "diff scanner flagged a permission rule as a secret"

# The shared corpus is a test input only. Exercise the deployed scanner copy,
# which has no adjacent repository, policy module or safety-paths.json file.
python3 - "$WORK/bridges/spar-payload-scan" "$ROOT/tests/safety-paths.json" "$TMP" <<'PY'
import json
from pathlib import Path
import runpy
import subprocess
import sys

scanner, corpus_file, scratch = sys.argv[1:]
corpus = json.loads(Path(corpus_file).read_text())
policy = runpy.run_path(scanner)
root = Path(scratch) / "path-fixtures"
root.mkdir()
system_files = corpus["system_files"] + corpus["raw_files"]
system_files += [f"etc/ssh/ssh_host_{kind}_key" for kind in ("rsa", "dsa", "ecdsa", "ed25519")]
system_trees = corpus["system_trees"] + corpus["raw_trees"]
home_files = [
    ".claude/.credentials.json", ".claude/history.jsonl", ".codex/auth.json", ".codex/config.toml",
    ".codex/history.jsonl", ".config/gh/hosts.yml", ".docker/config.json",
    ".local/share/opencode/auth.json", ".local/share/opencode/opencode.db",
    ".local/share/opencode/opencode.db-wal", ".local/share/opencode/opencode.db-shm",
    ".env", ".envrc", ".netrc", ".npmrc", ".pypirc", ".bash_history", ".zsh_history",
]
home_trees = [
    ".aws", ".ssh", ".gnupg", ".kube", ".mozilla", ".password-store",
    ".config/BraveSoftware", ".config/chromium", ".config/google-chrome", ".config/1Password",
    ".config/Bitwarden", ".local/share/keyrings", ".claude/projects", ".claude/sessions",
    ".claude/session-env", ".claude/tasks", ".claude/debug", ".codex/sessions", ".codex/archived_sessions",
    ".local/share/opencode/storage", ".local/share/opencode/log",
]
shapes = ["service.keytab", "ssh_host_future_algorithm_key", "server.key", "server.pem", "client.p12",
          "client.pfx", "credentials", "credentials.json", "auth.json", ".credentials.json",
          "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".env.production"]
trees = system_trees + home_trees + ["secrets"]
denied = system_files + home_files + shapes + [tree + "/nested/opaque.txt" for tree in trees]
positive = corpus["positive_files"] + [
    "etc/ssh/ssh_host_rsa_key.pub", "etc/ssh/ssh_host_ecdsa_key.pub", "etc/ssh/ssh_host_ed25519_key.pub",
    "etc/ssh/ssh_host_future_algorithm_key.pub", "src/auth.py", "docs/keytab-policy.md",
    "etc/shadow-policy.md", "sys/kernel/debug-notes.md", "etc/credstore-notes.md",
    ".codex/config.toml.example", ".codex/sessions-policy.md", ".claude/settings.json",
    ".config/opencode/opencode.json",
]
cases = {"system_files": system_files, "system_trees": system_trees, "home_files": home_files,
         "home_trees": home_trees, "additional_shapes": corpus["additional_shapes"], "denied": [], "positive": []}
count = 0
for path in system_files + home_files + trees:
    assert policy["sensitive_path"]("/" + path), path
for path in (".config/gh/hosts.yml/nested/opaque.txt", ".docker/config.json/nested/opaque.txt"):
    assert policy["sensitive_path"]("legacy-provider-copy/" + path), path
for prefix in ("", "copied layout/"):
    for accepted, paths in ((False, denied), (True, positive)):
        for path in paths:
            relative = prefix + path
            assert policy["sensitive_path"](relative) is not accepted, relative
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("ordinary fixture bytes\n")
            result = subprocess.run([scanner, "outbound", "--scratch-root", scratch, "--", str(target)],
                                    input="Review.", text=True, capture_output=True)
            assert result.returncode == (0 if accepted else 2), (relative, result.stderr)
            assert accepted or not result.stdout, relative
            # Actual outbound/diff parsing, including spaces and Git C-quoted
            # octal paths. No host credential/dump tree is opened or scanned.
            header = "diff --git " + json.dumps("a/" + relative) + " " + json.dumps("b/" + relative) + "\n"
            for mode in ("outbound", "diff"):
                result = subprocess.run([scanner, mode], input=header + "+ordinary fixture bytes\n",
                                        text=True, capture_output=True)
                assert result.returncode == (0 if accepted else 2), (mode, relative, result.stderr)
                count += 1
            escaped = header.replace("/", r"\057")
            assert policy["diff_header_sensitive"](escaped.removeprefix("diff --git ").strip()) is not accepted, relative
            cases["positive" if accepted else "denied"].append(relative)
            count += 1

# New paths remain valid only as bounded metadata collections. All existing
# malformed/computed/nested/scalar/credential-bearing refusals above still run.
for name, values in (("SECRET_FILES", system_files + home_files), ("SECRET_TREES", trees),
                     ("SECRET_GLOBS", corpus["additional_shapes"])):
    source = name + " = " + repr(values) + "\n"
    result = subprocess.run([scanner, "reply"], input=source, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
Path(scratch, "path-cases.json").write_text(json.dumps(cases))
print(f"ok: standalone scanner system/copy/session inventory ({count} artifact/header cases)")
PY

# The repository must stay reviewable by its own scanner, file by file: the whole tree
# exceeds one review request, and the bound on a request is deliberate. The index is
# scanned, since that is what a commit exposes and a working-tree deletion is not.
if ! $FIXTURES_ONLY; then
  empty_tree=$(git -C "$ROOT" hash-object -t tree /dev/null)
  while IFS= read -r -d '' tracked; do
    git -C "$ROOT" --literal-pathspecs diff --binary --cached "$empty_tree" -- "$tracked" | "$SCANNER" outbound >/dev/null ||
      fail "the repository's own tracked content fails the outbound scan: $tracked"
  done < <(git -C "$ROOT" ls-files -z)
fi

# --- Bridges ---
repo="$TMP/repo"
git init -q "$repo"
for bridge in "${PRODUCTION_BRIDGES[@]}"; do
  rc=0
  PATH="$SHIMS:$PATH" /usr/bin/env -C "$repo" "$bridge" review 'Refuse planted runtime.' >"$TMP/out" 2>"$TMP/err" || rc=$?
  [[ $rc == 2 && $(<"$TMP/err") == *'resolves under a temp root'* ]] || fail "production bridge admitted a temp runtime"
done
printf 'harmless\n' >"$repo/README.md"
printf 'in-repo artifact\n' >"$repo/notes.md"
printf '/.eyr-plans/\n' >"$repo/.gitignore"
# Generator semantics live in review-brief.sh. Exercise the generated artifact's
# handoff to the mocked reviewer in the ordinary review below, without gates.
local_brief="$repo/.eyr-plans/bridge-fixture/spar/repo-brief.md"
(umask 077; mkdir -p "${local_brief%/*}")
if $FIXTURES_ONLY; then
  printf 'synthetic review brief\n' >"$TMP/art/brief.md"
  cp -- "$TMP/art/brief.md" "$local_brief"
else
  git -C "$repo" add README.md notes.md .gitignore
  git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'bridge fixture'
  printf 'Outcome: review bridge fixture\nNon-goals: deployment\nConstraints: offline\nAcceptance: intact brief\n' >"$TMP/art/intent.md"
  /usr/bin/env -C "$repo" "$ROOT/agents/.agents/skills/spar/scripts/review-brief" \
    --intent "$TMP/art/intent.md" --out "$TMP/art/brief.md" --plan >"$TMP/brief.out"
  /usr/bin/env -C "$repo" "$ROOT/agents/.agents/skills/spar/scripts/review-brief" \
    --intent "$TMP/art/intent.md" --out "$local_brief" --plan >"$TMP/local-brief.out"
fi
mkdir -p "$repo/secrets"
printf 'harmless\n' >"$repo/secrets/ordinary.md"
run_bridge() { # bridge mode calls-file [bridge args...]
  local bridge=$1 mode=$2 calls=$3
  shift 3
  BRIDGE_RC=0
  rm -f -- "$calls" "$calls.pwd" "$calls.stdin" "$calls.env" "$calls.argv"
  configure_shims "$mode" "$calls" "${SPAR_TEST_REPLY:-}"
  PATH="$SHIMS:$PATH" /usr/bin/env -C "$repo" "$bridge" review "$@" >"$calls.out" 2>"$calls.err" || BRIDGE_RC=$?
}

for bridge in "${BRIDGES[@]}"; do
  name=${bridge##*/}
  calls="$TMP/calls-$name"

  for value in false maybe True '' ' true' $'true\n'; do
    git -C "$repo" config spar.consent "$value"
    run_bridge "$bridge" ok "$calls" "Review after opt-out."
    [[ $BRIDGE_RC == 2 && ! -e $calls && $(<"$calls.err") == *'spar.consent'* ]] ||
      fail "$name ran with spar.consent=$value"
    git -C "$repo" config --unset spar.consent
  done
  git -C "$repo" config spar.consent false
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=spar.consent GIT_CONFIG_VALUE_0=true run_bridge "$bridge" ok "$calls" "Review with an environment override."
  [[ $BRIDGE_RC == 2 && ! -e $calls ]] || fail "$name let a Git environment variable override the opt-out"
  git -C "$repo" config --unset spar.consent
  touch "$SHIMS/consent-error"
  run_bridge "$bridge" ok "$calls" "Refuse a consent lookup error after successful repository discovery."
  [[ $BRIDGE_RC == 2 && ! -e $calls && $(<"$calls.err") == *'spar.consent'* ]] || fail "$name accepted a failed consent lookup"
  rm -- "$SHIMS/consent-error"
  git -C "$repo" config spar.consent true
  run_bridge "$bridge" ok "$calls" "Review with explicit consent."
  [[ $BRIDGE_RC == 0 ]] || fail "$name failed with explicit consent (rc=$BRIDGE_RC): $(<"$calls.err")"
  git -C "$repo" config --unset spar.consent

  GIT_EDITOR=true OPENAI_BASE_URL=sentinel ANTHROPIC_BASE_URL=sentinel SPAR_TEST_CANARY=leak \
    run_bridge "$bridge" ok "$calls" "Review ordinary material." "$TMP/art/spar-plan.md" "$repo/notes.md" "$TMP/art/brief.md" "$local_brief"
  [[ $BRIDGE_RC == 0 && $(<"$calls.out") == 'review ok' ]] || fail "$name failed an ordinary review: $(<"$calls.err")"
  [[ $(<"$calls.err") == *'SPAR-BRIDGE ID: '* ]] || fail "$name did not report the reviewer id"
  [[ $(<"$calls.err") == *'"model":"unknown","effort":"unknown","tier":"unknown","clientversion":"'* ]] ||
    fail "$name inferred effective metadata from configuration"
  [[ $(<"$calls.pwd") == "$repo" ]] || fail "$name did not launch from the repository root"
  [[ $(<"$calls.stdin") == *'Review ordinary material.'*'===== artifact: spar-plan.md ====='*'plan body'*'===== artifact: notes.md ====='* ]] ||
    fail "$name did not send the scanned prompt with the inlined artifacts on stdin"
  [[ $(<"$calls.stdin") == *'===== artifact: brief.md ====='*"$(<"$TMP/art/brief.md")"*'===== end artifact: brief.md ====='* ]] ||
    fail "$name did not relay the complete generated brief with artifact delimiters"
  [[ -f $local_brief && $(<"$calls.stdin") == *'===== artifact: repo-brief.md ====='*"$(<"$local_brief")"*'===== end artifact: repo-brief.md ====='* ]] ||
    fail "$name lost the retained repository spar brief or omitted it from delivery"
  ! grep -qE '^(OPENAI_BASE_URL|ANTHROPIC_BASE_URL|SPAR_TEST_CANARY|GIT_EDITOR|TMPDIR)=' "$calls.env" ||
    fail "$name passed caller environment to the reviewer"
  grep -qE '^HOME=' "$calls.env" || fail "$name scrubbed HOME from the reviewer"
  args=$(<"$calls")
  cp -- "$calls.argv" "$TMP/$name.argv"
  mapfile -d '' argv <"$calls.argv"
  if [[ $name == spar-claude ]]; then
    for flag in '--tools Read,Glob,Grep' '--permission-mode dontAsk' '--safe-mode' '--setting-sources=' \
      '--strict-mcp-config' '--model fable' '--effort xhigh' '--output-format json' 'ANTHROPIC_DEFAULT_FABLE_MODEL' \
      "Read(/$repo/**)" "Read(/$repo/.git/**)" 'Read(./**/.env)' 'Read(./**/*.pem)' "Read(/$HOME/.ssh/**)"; do
      [[ $args == *"$flag"* ]] || fail "$name isolation missing: $flag"
    done
    # The model is the fable alias and the settings clear exactly its override,
    # checked on the argument values, not on names in the joined text.
    for ((i = 0; i < ${#argv[@]}; i++)); do
      case ${argv[i]} in
        --model) [[ ${argv[i + 1]:-} == fable ]] || fail "$name reviews with '${argv[i + 1]:-}' instead of the fable alias" ;;
        --model=*) fail "$name passes the model as ${argv[i]}" ;;
        --settings) jq -e '.env == {ANTHROPIC_DEFAULT_FABLE_MODEL: ""}' <<<"${argv[i + 1]:-}" >/dev/null 2>&1 ||
          fail "$name settings do not clear exactly the fable override" ;;
      esac
    done
  fi
  [[ $args != *'/var/tmp/spar-'* ]] || fail "$name still references a handoff directory"

  run_bridge "$bridge" ok "$calls" "Review an outside artifact." "$HOMEBOX/outside.md"
  [[ $BRIDGE_RC == 2 && ! -e $calls && $(<"$calls.err") == *'scratch'* ]] ||
    fail "$name accepted an artifact outside the repository and temp roots"
  run_bridge "$bridge" ok "$calls" "Do not expand roots." --root "$HOMEBOX" "$HOMEBOX/outside.md"
  [[ $BRIDGE_RC == 2 && ! -e $calls ]] || fail "$name accepted caller scanner options"
  printf '\n[broken\n' >>"$repo/.git/config"
  run_bridge "$bridge" ok "$calls" "Refuse config lookup errors."
  [[ $BRIDGE_RC == 2 && ! -e $calls ]] || fail "$name accepted a Git configuration error"
  git config --file "$repo/.git/config.new" core.repositoryformatversion 0
  mv -- "$repo/.git/config.new" "$repo/.git/config"
  for path in "$repo/.git/HEAD" "$repo/secrets/ordinary.md"; do
    run_bridge "$bridge" ok "$calls" "Review a confined path." "$path"
    [[ $BRIDGE_RC == 2 && ! -e $calls ]] || fail "$name accepted an artifact under a sensitive or Git-internal path: $path"
  done

  mkdir -p "$repo/bin" "$TMP/bin"
  for dir in "$repo/bin" "$TMP/bin"; do
    cp -- "$SHIMS/${name#spar-}" "$dir/${name#spar-}"
    cp -- "$SHIMS/shim.env" "$dir/shim.env"
    rm -f -- "$calls"
    rc=0
    PATH="$dir:$SHIMS:$PATH" /usr/bin/env -C "$repo" "$bridge" review "Review with a planted runtime." >"$calls.out" 2>"$calls.err" || rc=$?
    [[ $rc == 2 && ! -e $calls ]] || fail "$name accepted a reviewer runtime under $dir"
  done
  rm -rf -- "${repo:?}/bin" "${TMP:?}/bin"

  resume_id="22222222-2222-4222-8222-222222222222"
  run_bridge "$bridge" ok "$calls" --resume "$resume_id" "Follow up."
  [[ $BRIDGE_RC == 0 && $(<"$calls") == *"$resume_id"* ]] || fail "$name did not resume the requested session"
  run_bridge "$bridge" ok "$calls" --resume not-a-uuid "Follow up."
  [[ $BRIDGE_RC == 64 && ! -e $calls ]] || fail "$name accepted a malformed resume id"

  run_bridge "$bridge" ok "$calls" "$(printf '%s=%s' "$key_name" "$token")"
  [[ $BRIDGE_RC == 2 && ! -e $calls ]] || fail "$name sent a credential-shaped request"
  run_bridge "$bridge" ok "$calls" "Review leak." "$TMP/art/leak.md"
  [[ $BRIDGE_RC == 2 && ! -e $calls && $(<"$calls.err") != *"$token"* ]] || fail "$name sent a credential-shaped artifact"

  SPAR_TEST_REPLY="$(printf '%s=%s' "$key_name" "$token")" run_bridge "$bridge" reply "$calls" "Review reply."
  [[ $BRIDGE_RC == 2 && $(<"$calls.out") != *"$token"* && $(<"$calls.err") != *"$token"* ]] ||
    fail "$name relayed a credential-shaped reply"
  SPAR_TEST_REPLY='The .env path is denied.' run_bridge "$bridge" reply "$calls" "Review prose."
  [[ $BRIDGE_RC == 0 && $(<"$calls.out") == 'The .env path is denied.' ]] || fail "$name rejected sensitive-path prose"
  SPAR_TEST_REPLY="$token" run_bridge "$bridge" bad-version "$calls" "Review unsafe version metadata."
  [[ $BRIDGE_RC == 0 && $(<"$calls.err") != *"$token"* && $(<"$calls.err") == *'"clientversion":"unknown"'* ]] ||
    fail "$name leaked or inferred malformed version metadata"
  if [[ $name == spar-claude ]]; then
    SPAR_TEST_REPLY=claude-observed-fixture run_bridge "$bridge" metadata "$calls" "Review metadata."
    [[ $BRIDGE_RC == 0 && $(<"$calls.err") == *'"model":"claude-observed-fixture","effort":"unknown","tier":"standard","clientversion":"2.1.261"'* ]] ||
      fail "$name lost observed safe provenance"
    for value in $'claude-fixture\nunexpected text' $'claude-fixture\n' "$(printf 'claude-fixture\n%0200d' 0)"; do
      SPAR_TEST_REPLY="$value" run_bridge "$bridge" metadata "$calls" "Review multiline model metadata."
      [[ $BRIDGE_RC == 0 && $(<"$calls.err") == *'"model":"unknown"'* ]] || fail "$name retained a multiline model identifier"
      SPAR_TEST_REPLY="$value" run_bridge "$bridge" metadata-tier "$calls" "Review multiline tier metadata."
      [[ $BRIDGE_RC == 0 && $(<"$calls.err") == *'"tier":"unknown"'* ]] || fail "$name retained a multiline tier identifier"
    done
    SPAR_TEST_REPLY="$token" run_bridge "$bridge" metadata "$calls" "Review unsafe metadata."
    [[ $BRIDGE_RC == 0 && $(<"$calls.err") != *"$token"* && $(<"$calls.err") == *'"model":"unknown"'* ]] ||
      fail "$name leaked unsafe metadata"
    SPAR_TEST_REPLY="$token" run_bridge "$bridge" malformed-metadata "$calls" "Review malformed metadata."
    [[ $BRIDGE_RC == 0 && $(<"$calls.err") != *"$token"* && $(<"$calls.err") == *'"model":"unknown"'* ]] ||
      fail "$name leaked a metadata parser diagnostic"
  fi

  run_bridge "$bridge" limit "$calls" "Review limit."
  [[ $BRIDGE_RC == 3 && $(<"$calls.err") == *'SPAR-BRIDGE LIMIT'* ]] || fail "$name did not classify a usage limit"
  run_bridge "$bridge" error-result "$calls" "Review error."
  [[ $BRIDGE_RC == 5 && $(<"$calls.err") == *'SPAR-BRIDGE ERROR'* ]] || fail "$name did not classify an error result"
  run_bridge "$bridge" failure "$calls" "Review failure."
  [[ $BRIDGE_RC == 5 && $(<"$calls.err") == *'reviewer failed while reading .env policy'* ]] ||
    fail "$name did not relay safe reviewer diagnostics"

  child_pid_file="$TMP/child-$name"
  configure_shims hang "$calls" "" "$child_pid_file"
  start=$(date +%s)
  rc=0
  SPAR_BRIDGE_TIMEOUT=1 PATH="$SHIMS:$PATH" /usr/bin/env -C "$repo" "$bridge" review "Review timeout." \
    >"$calls.out" 2>"$calls.err" || rc=$?
  [[ $rc == 124 && $(<"$calls.err") == *'SPAR-BRIDGE TIMEOUT'* ]] || fail "$name did not classify a timeout"
  (( $(date +%s) - start <= 8 )) || fail "$name timeout was not bounded"
  expect_child_stopped "$child_pid_file" "$name timeout"

  rm -f -- "$child_pid_file" "$calls"
  configure_shims hang "$calls" "" "$child_pid_file"
  PATH="$SHIMS:$PATH" /usr/bin/env -C "$repo" "$bridge" review "Review signal." >/dev/null 2>"$calls.err" &
  bridge_pid=$!
  for _ in $(seq 1 50); do [[ -s $child_pid_file ]] && break; sleep 0.1; done
  kill -TERM "$bridge_pid"
  rc=0
  wait "$bridge_pid" || rc=$?
  [[ $rc == 130 ]] || fail "$name did not return 130 after TERM"
  expect_child_stopped "$child_pid_file" "$name TERM"
  rc=0
done

python3 - "$TMP" "$repo" "$HOMEBOX" "$SHIMS" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

scratch, repo, home, shims = sys.argv[1:]
cases = json.loads(Path(scratch, "path-cases.json").read_text())

def argv(name):
    return Path(scratch, name + ".argv").read_bytes().decode().rstrip("\0").split("\0")

claude_args = argv("spar-claude")
settings = json.loads(claude_args[claude_args.index("--settings") + 1])
permissions = settings["permissions"]
assert permissions["allow"] == [f"Read(/{repo}/**)"], "Claude reviewer read scope changed"
denies = set(permissions["deny"])
for path in cases["system_files"]:
    assert f"Read(//{path})" in denies, path
for path in cases["system_trees"]:
    assert {f"Read(//{path})", f"Read(//{path}/**)"} <= denies, path
for path in cases["home_files"]:
    assert f"Read(/{home}/{path})" in denies, path
for path in cases["home_trees"]:
    assert {f"Read(/{home}/{path})", f"Read(/{home}/{path}/**)"} <= denies, path
for prefix in ("./", "./**/"):
    for path in cases["system_files"] + cases["home_files"] + cases["additional_shapes"]:
        assert f"Read({prefix}{path})" in denies, path
    for path in cases["system_trees"] + cases["home_trees"] + [".git", "secrets"]:
        assert {f"Read({prefix}{path})", f"Read({prefix}{path}/**)"} <= denies, path

# Exercise real rg --files selection of synthetic paths only. This catches the
# bare-directory-glob bug without claiming reviewer dispatch.
def selected(patterns):
    command = ["rg", "--files", "--hidden", "--no-ignore", "--null"]
    for pattern in sorted(patterns):
        command += ["--glob", pattern]
    result = subprocess.run(command + ["."], cwd=Path(scratch, "path-fixtures"), capture_output=True)
    assert result.returncode in (0, 1), result.stderr
    return {path.removeprefix("./") for path in result.stdout.decode().split("\0") if path}

for name, patterns in (
    ("Claude repository rules", [rule[len("Read(./"):-1] for rule in denies if rule.startswith("Read(./")]),
):
    matches = selected(patterns)
    assert set(cases["denied"]) <= matches, (name, "unselected payloads", set(cases["denied"]) - matches)
    assert not set(cases["positive"]) & matches, (name, "positive source excluded", set(cases["positive"]) & matches)
print(f"ok: the reviewer profile retains scope and mask {len(set(cases['denied']))} synthetic payload paths; {len(cases['positive'])} positives usable")
PY

if ! $FIXTURES_ONLY; then
  SPAR_BRIDGE_FIXTURES="$TMP" env -u CONFIG_CONTRACT_ROOT python3 -B "$ROOT/tests/config-contracts.py"
fi
printf 'ok: spar bridges relay scanned one-pass reviews from a scrubbed environment and honor opt-out\n'
