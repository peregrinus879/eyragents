#!/usr/bin/env bash
# Exercise startup defaults with the real mise and no host config or exports.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MISE=$(command -v mise)
umask 077
TMP=$(mktemp -d "${TMPDIR:-/tmp}/eyragents-mise.XXXXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/home/.config/mise/conf.d" "$TMP/project" "$TMP/elsewhere" "$TMP/system"

probe() {
  # shellcheck disable=SC2016 # The isolated child expands these variables.
  env -i PATH="$PATH" HOME="$TMP/home" HISTFILE=/dev/null \
    XDG_CONFIG_HOME="$TMP/home/.config" XDG_DATA_HOME="$TMP/home/.local/share" \
    XDG_CACHE_HOME="$TMP/home/.cache" XDG_STATE_HOME="$TMP/home/.local/state" \
    MISE_CONFIG_DIR="$TMP/home/.config/mise" MISE_DATA_DIR="$TMP/data" \
    MISE_CACHE_DIR="$TMP/cache" MISE_SYSTEM_CONFIG_DIR="$TMP/system" \
    MISE_CEILING_PATHS="$TMP" MISE_QUIET=1 "$@" \
    "$MISE" exec --no-deps --fresh-env -- /bin/bash --noprofile --norc -c \
    'printf "%s/%s" "${OPENCODE_DISABLE_CLAUDE_CODE_SKILLS-unset}" "${OPENCODE_ENABLE_EXA-unset}"'
}

# Work outside the source checkout. No shell initialization or sibling files.
pushd "$TMP/project" >/dev/null
[[ $(probe) == unset/unset ]]
cp "$ROOT/opencode/.config/mise/conf.d/eyragents-opencode.toml" "$TMP/home/.config/mise/conf.d/"
[[ $(probe) == 1/1 ]]
[[ $(probe OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=0 OPENCODE_ENABLE_EXA=false) == 0/false ]]
[[ $(probe OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 OPENCODE_ENABLE_EXA=0) == 1/0 ]]
popd >/dev/null
pushd "$TMP/elsewhere" >/dev/null
[[ $(probe) == 1/1 ]]
popd >/dev/null
printf 'ok:   mise supplies standalone OpenCode defaults and preserves explicit overrides\n'
