#!/usr/bin/env bash
# Real local Git repositories establish preservation and manifest isolation.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
umask 077
TMP=$(mktemp -d "${TMPDIR:-/tmp}/eyragents-refs.XXXXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
for inherited_git_name in "${!GIT_@}"; do unset "$inherited_git_name"; done
export HOME="$TMP/home" HISTFILE=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
mkdir -p "$HOME" "$TMP/harness/scripts" "$TMP/unrelated" "$TMP/quarry"
cp "$ROOT/scripts/update-references.sh" "$TMP/harness/scripts/"
cp "$ROOT/scripts/update-references.py" "$TMP/harness/scripts/"
git init -q -b main "$TMP/upstream"
git -C "$TMP/upstream" config user.name fixture
git -C "$TMP/upstream" config user.email fixture@example.invalid
printf 'one\n' >"$TMP/upstream/README.md"
git -C "$TMP/upstream" add README.md
git -C "$TMP/upstream" commit -qm initial
git -C "$TMP/upstream" tag stable
git clone -q "file://$TMP/upstream" "$TMP/quarry/reference"
printf 'reference file://%s/upstream\n' "$TMP" >"$TMP/harness/references.txt"
# A malformed neighboring manifest must have no effect, and an unrelated clone
# must not be touched or classified as stale merely because it shares storage.
printf 'invalid sibling data\n' >"$TMP/unrelated/references.txt"
git init -q -b main "$TMP/quarry/unrelated"

update() { QUARRY="$TMP/quarry" bash "$TMP/harness/scripts/update-references.sh" "$@"; }
reject() { if update "$@" >"$TMP/result" 2>&1; then printf 'FAIL: unexpected refresh success\n' >&2; exit 1; fi; }
before=$(git -C "$TMP/quarry/reference" rev-parse HEAD)
if GIT_DIR="$TMP/upstream/.git" GIT_WORK_TREE="$TMP/quarry/reference" update >"$TMP/result" 2>&1; then
  printf 'FAIL: inherited Git context override was accepted\n' >&2; exit 1
fi
[[ $(git -C "$TMP/quarry/reference" rev-parse HEAD) == "$before" ]]
printf 'two\n' >>"$TMP/upstream/README.md"
git -C "$TMP/upstream" commit -qam advance
update --dry-run
[[ $(git -C "$TMP/quarry/reference" rev-parse HEAD) == "$before" ]]
update
[[ $(git -C "$TMP/quarry/reference" rev-parse HEAD) == "$(git -C "$TMP/upstream" rev-parse HEAD)" ]]
[[ $(git -C "$TMP/quarry/unrelated" symbolic-ref --short HEAD) == main ]]

# Tracked work is retained, and unknown arguments cannot widen the manifest.
printf 'local work\n' >>"$TMP/quarry/reference/README.md"
reject
[[ $(git -C "$TMP/quarry/reference" diff --numstat) == *README.md ]]
reject undeclared
git -C "$TMP/quarry/reference" config user.name fixture
git -C "$TMP/quarry/reference" config user.email fixture@example.invalid
git -C "$TMP/quarry/reference" commit -qam 'local change'
local_head=$(git -C "$TMP/quarry/reference" rev-parse HEAD)
reject
[[ $(git -C "$TMP/quarry/reference" rev-parse HEAD) == "$local_head" ]]

# A separately selected missing reference is reported without creating it.
printf 'missing file://%s/upstream\n' "$TMP" >>"$TMP/harness/references.txt"
reject missing
[[ ! -e $TMP/quarry/missing ]]

# A fresh fixture proves ignored collisions survive a refused fast-forward.
git clone -q "file://$TMP/upstream" "$TMP/quarry/collision"
printf 'collision file://%s/upstream\n' "$TMP" >>"$TMP/harness/references.txt"
printf 'local.txt\n' >"$TMP/quarry/collision/.git/info/exclude"
printf 'keep me\n' >"$TMP/quarry/collision/local.txt"
printf 'upstream\n' >"$TMP/upstream/local.txt"
git -C "$TMP/upstream" add local.txt
git -C "$TMP/upstream" commit -qm collision
old_head=$(git -C "$TMP/quarry/collision" rev-parse HEAD)
reject collision
[[ $(<"$TMP/quarry/collision/local.txt") == 'keep me' ]]
[[ $(git -C "$TMP/quarry/collision" rev-parse HEAD) == "$old_head" ]]

# Replacing an upstream tag must not overwrite a local tag or partially fetch.
git clone -q "file://$TMP/upstream" "$TMP/quarry/tags"
printf 'tags file://%s/upstream\n' "$TMP" >>"$TMP/harness/references.txt"
old_tag=$(git -C "$TMP/quarry/tags" rev-parse refs/tags/stable)
git -C "$TMP/upstream" tag -d stable >/dev/null
git -C "$TMP/upstream" tag stable
reject tags
[[ $(git -C "$TMP/quarry/tags" rev-parse refs/tags/stable) == "$old_tag" ]]
printf 'ok:   references are standalone, scoped, and preservation-first\n'
