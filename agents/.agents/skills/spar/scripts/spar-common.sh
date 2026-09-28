#!/usr/bin/env bash
# Shared bridge contracts: workspace selection and stateless resume handles.
# Callers provide fail() and strict shell options. No permissions are changed.

spar_valid_reply() {
  grep -v '^[[:space:]]*$' | tail -n 1 | grep -qE '^VERDICT: (CLEAR|BLOCKED|INCOMPLETE)$'
}

spar_workspace() {
  local work=$1 status dir
  workspace_is_git=1
  if workspace=$(LC_ALL=C git rev-parse --show-toplevel 2>"$work/git-error"); then
    workspace=$(realpath -e -- "$workspace") || fail "cannot resolve the Git workspace"
    return
  else
    status=$?
  fi
  # A broken repository, missing Git or a trust/configuration error is not a plain folder.
  if [[ $status != 128 ]] || ! grep -qE '^fatal: not a git repository \(or (any of the parent directories\): \.git|any parent up to mount point .+\))$' "$work/git-error"; then
    fail "cannot discover the workspace; check Git and directory access"
  fi
  workspace=$(pwd -P) || fail "cannot resolve the working directory"
  dir=$workspace
  while :; do
    [[ ! -e $dir/.git && ! -L $dir/.git ]] || fail "Git discovery failed despite a .git entry"
    [[ $dir != / ]] || break
    dir=$(dirname -- "$dir")
  done
  workspace_is_git=0
}

spar_scope() {
  printf '%s\0%s' "$1" "$2" | sha256sum | cut -d ' ' -f 1
}

spar_handle() {
  [[ $3 =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  printf '%s@%s' "$3" "$(spar_scope "$1" "$2")"
}

spar_resume() {
  [[ $3 == *@* && ${3##*@} == "$(spar_scope "$1" "$2")" && ${3%@*} =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  printf '%s' "${3%@*}"
}

spar_claude_shadow_check() {
  local work=$1 dir=$workspace status
  # Without Git, project configuration can be inherited from parent directories.
  # The user's own agent directory is the intended source, not a project override.
  while :; do
    if [[ $dir != "$HOME" && -d $dir/.claude/agents ]]; then
      status=0
      grep -rsE --include='*.md' '^name:[[:space:]]*["'\'']?sparrer["'\'']?[[:space:]]*(#.*)?$' \
        -- "$dir/.claude/agents" >"$work/shadow" || status=$?
      [[ $status == 1 ]] || fail "a project sparrer overrides the user reviewer, or its definitions cannot be checked"
    fi
    [[ $workspace_is_git == 0 && $dir != / ]] || break
    dir=$(dirname -- "$dir")
  done
}
