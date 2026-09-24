#!/usr/bin/env bash
# Prepare $HOME for `stow --no-folding` and link skill directories.
#
# Without arguments: remove dangling symlinks under the managed target
# directories whose link text names a path inside one of this repository's
# packages, recognized by the package name followed by a top-level entry that
# package really has or once had (RETIRED_ENTRIES), so retired files and moved
# or renamed clones are cleaned and unrelated links with a similar spelling are
# not. The match is not bound to this clone's path, so a dangling link into
# another clone with the same package layout is removed too; only dangling
# links are ever removed, and afterwards the retired managed directories those
# links leave empty are pruned. Links that resolve, links that point elsewhere,
# and regular files are never touched; Stow itself reports any remaining
# conflict without changing the filesystem.
#
# --link-skills: make each ~/.agents/skills/<name> and ~/.claude/skills/<name>
# one link to the skill's directory in the agents package, so a file added to a
# skill deploys without a restow; Claude Code reads only ~/.claude/skills. A
# directory left by an earlier deploy is emptied of links into that skill's
# source (including recognized retired package links) and removed. All selected
# skills are preflighted before any mutation; foreign files and links, including
# dangling links, stop the script unchanged. --check-skills runs that preflight
# without making changes. --unlink-skills removes the links that resolve into
# this clone's package. --require-clone checks all managed endpoints and parents
# without writing.
set -euo pipefail

abort() {
  printf 'prepare-stow: %s\n' "$1" >&2
  exit 1
}

script_dir=$(dirname -- "${BASH_SOURCE[0]}")
repository_root=$(realpath -e -- "$script_dir/..") || abort 'cannot resolve repository root'
[[ -n ${HOME:-} && -d $HOME ]] || abort 'HOME must name an existing non-root directory'
HOME=$(realpath -e -- "$HOME") || abort 'cannot resolve HOME'
[[ $HOME != / ]] || abort 'HOME must name an existing non-root directory'
PACKAGES=(agents claude-code opencode)
TARGET_ROOTS=("$HOME/.claude" "$HOME/.codex" "$HOME/.agents" "$HOME/.local/bin" "$HOME/.config/opencode" "$HOME/.config/mise/conf.d" "$HOME/.hermes/plugins")
# Package entries that once existed, including retired packages: links into
# them are still ours to clean.
RETIRED_ENTRIES=(agents/.local codex/.agents codex/.codex hermes/.hermes claude-code/.claude/rules claude-code/.claude/skills
  opencode/.config/opencode/skills opencode/.config/opencode/commands opencode/.config/opencode/plugins)
# Skills that once shipped: the directories their Claude links leave behind are pruned when empty.
RETIRED_SKILLS=(commit develop publish)
SKILL_ROOTS=("$HOME/.agents/skills" "$HOME/.claude/skills")
STRICT=0

managed_link_text() { # link text
  local text=$1 package tail entry
  for package in "${PACKAGES[@]}" "${RETIRED_ENTRIES[@]%%/*}"; do
    [[ $text == *"/$package/"* ]] || continue
    tail=${text#*"/$package/"}
    [[ -n $tail && -e "$repository_root/$package/${tail%%/*}" ]] && return 0
    for entry in "${RETIRED_ENTRIES[@]}"; do
      [[ "$package/$tail" == "$entry" || "$package/$tail" == "$entry"/* ]] && return 0
    done
  done
  return 1
}

require_clone() {
  local src path resolved scan
  local -a sources=()
  [[ -n ${HOME:-} && $HOME != / && -d $HOME ]] || abort 'HOME must name an existing non-root directory'
  mapfile -d '' -t sources < <(git -C "$repository_root" ls-files -z --cached --others --exclude-standard -- "${PACKAGES[@]}")
  scan=$!; wait "$scan" || abort 'cannot enumerate package files'
  ((${#sources[@]})) || abort 'no Git-visible package files found'
  for src in "${sources[@]}"; do
    path="$HOME/${src#*/}"
    while [[ $path != "$HOME" ]]; do
      if [[ -L $path ]]; then
        resolved=$(realpath -m -- "$path") || abort "cannot resolve $path"
        if [[ $resolved != "$repository_root"/* ]]; then
          if [[ -e $path ]] || ! managed_link_text "$(readlink -- "$path")"; then
            abort "$path is linked from another clone or an unmanaged location; run from the deployed clone"
          fi
        fi
      fi
      path=${path%/*}
    done
  done
}

clean_links() {
  local root path text dir
  [[ -n ${HOME:-} && $HOME != / ]] || abort 'HOME must name a non-root directory'
  for root in "${TARGET_ROOTS[@]}"; do
    [[ -d $root && ! -L $root ]] || continue
    while IFS= read -r -d '' path; do
      text=$(readlink -- "$path") || continue
      managed_link_text "$text" || continue
      rm -- "$path"
      printf 'removed dangling managed link: %s\n' "$path"
    done < <(find "$root" -xtype l -print0 2>/dev/null)
  done
  # Managed directories the retired links leave behind, pruned only when empty, deepest first.
  local -a retired=("$HOME"/.config/opencode/skills/*/ "$HOME/.config/opencode/skills" "$HOME/.config/opencode/lib"
    "$HOME/.config/opencode/commands" "$HOME/.config/opencode/plugins" "$HOME/.claude/rules")
  local skill
  for skill in "${RETIRED_SKILLS[@]}"; do
    retired+=("$HOME/.claude/skills/$skill/scripts" "$HOME/.claude/skills/$skill/references" "$HOME/.claude/skills/$skill")
  done
  for dir in "${retired[@]}"; do
    dir=${dir%/}
    [[ -d $dir && ! -L $dir ]] || continue
    rmdir -- "$dir" 2>/dev/null || continue
    printf 'removed empty retired directory: %s\n' "$dir"
  done
}

package_skills() {
  local dir
  for dir in "$repository_root"/agents/.agents/skills/*/; do
    [[ -d $dir ]] || continue
    basename -- "$dir"
  done
}

check_skills() {
  local root name source target entry resolved scan
  local -a entries=()
  [[ -n ${HOME:-} && $HOME != / ]] || abort 'HOME must name a non-root directory'
  for root in "${SKILL_ROOTS[@]}"; do
    if [[ -L ${root%/skills} ]]; then
      # Before Stow runs, a fold into this clone is left for Stow to replace; linking
      # and unlinking need real parents, or they would write into the package source.
      [[ $STRICT == 0 && $(realpath -m -- "${root%/skills}") == "$repository_root"/* ]] ||
        abort "the skills parent must be a real directory, not a link: ${root%/skills}"
      continue
    fi
    [[ ! -L $root ]] || abort "the skills root must be a real directory, not a link: $root"
    [[ ! -e $root || -d $root ]] || abort "the skills root is not a directory: $root"
    while IFS= read -r name; do
      source="$repository_root/agents/.agents/skills/$name"
      target="$root/$name"
      if [[ -L $target ]]; then
        resolved=$(realpath -m -- "$target") || abort "cannot resolve $target"
        [[ $resolved == "$source" ]] && continue
        if [[ ! -e $target && ( $resolved == */agents/.agents/skills/"$name" ||
          $resolved == */codex/.agents/skills/"$name" ) ]]; then continue; fi
        abort "refusing to repoint a foreign skill link: $target"
      elif [[ -d $target ]]; then
        mapfile -d '' -t entries < <(find "$target" -mindepth 1 -print0)
        scan=$!; wait "$scan" || abort "cannot inspect the skill directory: $target"
        for entry in "${entries[@]}"; do
          if [[ -L $entry ]]; then
            resolved=$(realpath -m -- "$entry") || abort "cannot resolve $entry"
            [[ $resolved == "$source"/* ]] && continue
            # Earlier deployments linked each file, through codex/.agents or the
            # retired claude-code/.claude/skills tree; recognize only a dangling
            # link naming this selected skill, not arbitrary missing targets.
            if [[ ! -e $entry && ( $resolved == */codex/.agents/skills/"$name"/* ||
              $resolved == */agents/.agents/skills/"$name"/* ||
              $resolved == */claude-code/.claude/skills/"$name"/* ) ]]; then continue; fi
            abort "foreign link inside a managed skill directory: $entry"
          elif [[ -d $entry ]]; then
            continue
          fi
          abort "foreign entry inside a managed skill directory: $entry"
        done
      elif [[ -e $target ]]; then
        abort "skill endpoint is neither a link nor a directory: $target"
      fi
    done < <(package_skills)
  done
}

link_skills() {
  local root name source target text entry
  STRICT=1
  check_skills
  for root in "${SKILL_ROOTS[@]}"; do
    mkdir -p -- "$root"
    while IFS= read -r name; do
      source="$repository_root/agents/.agents/skills/$name"
      target="$root/$name"
      if [[ -L $target ]]; then
        [[ $(realpath -m -- "$target") == "$source" ]] && continue
        rm -- "$target"
      fi
      text=$(realpath --relative-to="$root" -- "$source")
      if [[ -d $target ]]; then
        while IFS= read -r -d '' entry; do
          rm -- "$entry"
        done < <(find "$target" -type l -print0)
        find "$target" -depth -type d -exec rmdir -- {} + || abort "cannot remove empty skill directories: $target"
      fi
      ln -s -- "$text" "$target"
      printf 'linked skill directory: %s -> %s\n' "$target" "$text"
    done < <(package_skills)
  done
}

unlink_skills() {
  local root name target
  for root in "${SKILL_ROOTS[@]}"; do
    while IFS= read -r name; do
      target="$root/$name"
      [[ -L $target ]] || continue
      [[ $(realpath -m -- "$target") == "$repository_root/agents/.agents/skills/$name" ]] || continue
      rm -- "$target"
      printf 'removed skill directory link: %s\n' "$target"
    done < <(package_skills)
  done
}

[[ $# -le 1 ]] || abort "unsupported arguments: $*"
case ${1:-} in
  ''|--require-clone|--check-skills|--link-skills|--unlink-skills) ;;
  *) abort "unsupported arguments: $*" ;;
esac
require_clone
case ${1:-} in
  '') check_skills; clean_links ;;
  --require-clone) ;;
  --check-skills) check_skills ;;
  --link-skills)
    [[ $# == 1 ]] || abort "unsupported arguments: $*"
    link_skills ;;
  --unlink-skills)
    [[ $# == 1 ]] || abort "unsupported arguments: $*"
    STRICT=1
    check_skills
    unlink_skills ;;
  *) abort "unsupported arguments: $*" ;;
esac
