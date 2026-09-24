#!/usr/bin/env bash
# Deployment preparation: dangling managed links are removed, everything else
# is preserved (retired packages included), no-folding Stow keeps every parent
# real, skill directories deploy as single links, and the gate stays guarded.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GATE # Fixture homes must not inherit Make's exported host endpoint.

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# A clone named like the real repository, with the package shape that matters.
make_clone() {
  local repo=$1
  mkdir -p "$repo/agents/.agents/skills/commit/scripts" "$repo/claude-code/.claude/skills/commit/scripts" \
    "$repo/agents/.agents/skills/develop/references" "$repo/claude-code/.claude/skills/develop/references" \
    "$repo/agents/.agents/skills/publish/scripts" "$repo/claude-code/.claude/skills/publish/scripts" \
    "$repo/claude-code/.claude/skills/spar/scripts" \
    "$repo/agents/.agents/skills/spar/scripts" \
    "$repo/opencode/.config/opencode" "$repo/opencode/.config/mise/conf.d" \
    "$repo/scripts" "$repo/templates/hooks"
  printf 'tracked\n' >"$repo/claude-code/.claude/settings.json"
  printf 'guidance\n' >"$repo/agents/.agents/global-agents.md"
  cp -- "$ROOT/agents/.agents/skills/develop/SKILL.md" "$repo/agents/.agents/skills/develop/"
  ln -s ../../../../agents/.agents/skills/develop/SKILL.md "$repo/claude-code/.claude/skills/develop/SKILL.md"
  for resource in workstream verification; do
    cp -- "$ROOT/agents/.agents/skills/develop/references/$resource.md" "$repo/agents/.agents/skills/develop/references/"
    ln -s "../../../../../agents/.agents/skills/develop/references/$resource.md" "$repo/claude-code/.claude/skills/develop/references/$resource.md"
  done
  printf 'skill\n' >"$repo/agents/.agents/skills/commit/SKILL.md"
  printf 'script\n' >"$repo/agents/.agents/skills/commit/scripts/commit-apply"
  ln -s ../../agents/.agents/global-agents.md "$repo/claude-code/.claude/CLAUDE.md"
  ln -s ../../../../agents/.agents/skills/commit/SKILL.md "$repo/claude-code/.claude/skills/commit/SKILL.md"
  ln -s ../../../../../agents/.agents/skills/commit/scripts/commit-apply "$repo/claude-code/.claude/skills/commit/scripts/commit-apply"
  printf 'skill\n' >"$repo/agents/.agents/skills/publish/SKILL.md"
  cp -- "$ROOT/agents/.agents/skills/publish/scripts/publish-apply" "$repo/agents/.agents/skills/publish/scripts/publish-apply"
  ln -s ../../../../../agents/.agents/skills/publish/scripts/publish-apply "$repo/claude-code/.claude/skills/publish/scripts/publish-apply"
  printf 'tracked\n' >"$repo/agents/.agents/skills/spar/scripts/spar-claude"
  printf 'tracked\n' >"$repo/agents/.agents/skills/spar/scripts/spar-payload-scan"
  printf 'tracked\n' >"$repo/agents/.agents/skills/spar/scripts/spar-opencode"
  for tool in spar-claude spar-opencode spar-payload-scan; do
    ln -s "../../../../../agents/.agents/skills/spar/scripts/$tool" "$repo/claude-code/.claude/skills/spar/scripts/$tool"
  done
  printf '{}\n' >"$repo/opencode/.config/opencode/opencode.json"
  cp -- "$ROOT/opencode/.config/mise/conf.d/eyragents-opencode.toml" "$repo/opencode/.config/mise/conf.d/"
  cp -- "$ROOT/scripts/prepare-stow.sh" "$repo/scripts/prepare-stow.sh"
  cp -- "$ROOT/templates/hooks/commit-gate" "$repo/templates/hooks/commit-gate"
  cp -- "$ROOT/Makefile" "$repo/Makefile"
  git -C "$repo" init -q
}

prepare() { HOME=$1 bash "$2/scripts/prepare-stow.sh"; }
deploy() {
  HOME=$1 stow --no-folding -R -d "$2" -t "$1" claude-code opencode &&
    HOME=$1 stow --no-folding --ignore='\.agents/skills' -R -d "$2" -t "$1" agents &&
    HOME=$1 bash "$2/scripts/prepare-stow.sh" --link-skills
}
undeploy() {
  HOME=$1 stow --no-folding -D -d "$2" -t "$1" claude-code opencode &&
    HOME=$1 stow --no-folding --ignore='\.agents/skills' -D -d "$2" -t "$1" agents &&
    HOME=$1 bash "$2/scripts/prepare-stow.sh" --unlink-skills
}

case_clean_links() {
  local home="$TMP/clean/home" repo="$TMP/clean/eyragents" old="$TMP/clean/old/eyragents"
  mkdir -p "$home/.claude/skills" "$home/.codex" "$home/.agents/skills" "$home/.local/bin" "$home/.config/opencode" "$home/.hermes/plugins/eyragents"
  make_clone "$repo"
  ln -s "$old/claude-code/.claude/hooks" "$home/.claude/hooks"
  # Links left by the retired codex and hermes packages.
  ln -s "$old/codex/.codex/config.toml" "$home/.codex/config.toml"
  ln -s "$old/hermes/.hermes/plugins/eyragents/__init__.py" "$home/.hermes/plugins/eyragents/__init__.py"
  ln -s "../../Projects/renamed-clone/agents/.agents/skills/retired" "$home/.agents/skills/retired"
  ln -s "$repo/claude-code/.claude/settings.json" "$home/.claude/settings.json"
  ln -s /usr/share/nothing/here "$home/.claude/skills/vendor"
  ln -s "$old/unrelated/codex/thing" "$home/.local/bin/thing"
  ln -s "$TMP/clean/other/eyragents/codex/tool" "$home/.local/bin/tool"
  printf 'user data\n' >"$home/.config/opencode/opencode.json"
  # Links into entries the packages once had, and the directories they leave empty.
  mkdir -p "$home/.claude/rules" "$home/.config/opencode/skills/commit" "$home/.config/opencode/lib"
  ln -s "../../Projects/eyrie/eyragents/agents/.local/bin/commit-apply" "$home/.local/bin/commit-apply"
  ln -s "../../Projects/eyrie/eyragents/claude-code/.claude/rules/shared-guidance.md" "$home/.claude/rules/shared-guidance.md"
  ln -s "../../../../Projects/eyrie/eyragents/opencode/.config/opencode/skills/commit/SKILL.md" "$home/.config/opencode/skills/commit/SKILL.md"
  ln -s "../../../../Projects/eyrie/eyragents/opencode/.config/opencode/lib/safety-paths.mjs" "$home/.config/opencode/lib/safety-paths.mjs"
  prepare "$home" "$repo"
  [[ ! -L $home/.local/bin/commit-apply ]] || fail "dangling link into a retired package entry remains"
  [[ ! -e $home/.claude/rules ]] || fail "emptied retired directory ~/.claude/rules remains"
  [[ ! -e $home/.config/opencode/skills ]] || fail "emptied retired directory ~/.config/opencode/skills remains"
  [[ ! -e $home/.config/opencode/lib ]] || fail "emptied retired directory ~/.config/opencode/lib remains"
  [[ ! -e $home/.claude/hooks && ! -L $home/.claude/hooks ]] || fail "dangling managed directory link remains"
  [[ ! -L $home/.codex/config.toml ]] || fail "dangling link into the retired codex package remains"
  [[ ! -L $home/.hermes/plugins/eyragents/__init__.py ]] || fail "dangling link into the retired hermes package remains"
  [[ ! -L $home/.agents/skills/retired ]] || fail "dangling link from a renamed clone remains"
  [[ -L $home/.claude/settings.json ]] || fail "resolving managed link was removed"
  [[ -L $home/.claude/skills/vendor ]] || fail "unmanaged dangling link was removed"
  [[ -L $home/.local/bin/thing ]] || fail "dangling link outside the package layout was removed"
  [[ -L $home/.local/bin/tool ]] || fail "dangling link with the repository name but no package entry was removed"
  [[ $(<"$home/.config/opencode/opencode.json") == "user data" ]] || fail "regular file was changed"
}

case_no_folding() {
  local home="$TMP/fold/home" repo="$TMP/fold/eyragents" root="$TMP/fold/home/.config/opencode"
  mkdir -p "$home/.config" "$home/.local"
  make_clone "$repo"
  # Folded links as an older Stow deployment created them: relative, so Stow
  # still recognizes them as its own and unfolds them.
  ln -s ../eyragents/claude-code/.claude "$home/.claude"
  ln -s ../../eyragents/opencode/.config/opencode "$home/.config/opencode"
  prepare "$home" "$repo"
  deploy "$home" "$repo" >/dev/null 2>&1 || fail "restow could not replace folded links"
  for path in .claude .claude/skills/commit .claude/skills/commit/scripts .claude/skills/publish/scripts .agents .agents/skills .claude/skills/spar/scripts .config/opencode .config/mise/conf.d; do
    [[ -d $home/$path && ! -L $home/$path ]] || fail "$path is not a real directory after no-folding stow"
  done
  for name in develop commit publish spar; do
    [[ -L $home/.agents/skills/$name && $(readlink -f -- "$home/.agents/skills/$name") == "$repo/agents/.agents/skills/$name" ]] ||
      fail "skill directory $name is not one link into the clone"
  done
  [[ $(readlink -f -- "$home/.claude/skills/develop/references/workstream.md") == "$repo/agents/.agents/skills/develop/references/workstream.md" ]] ||
    fail "develop's workstream resource is unavailable through Claude's skill path"
  [[ $(readlink -f -- "$home/.agents/global-agents.md") == "$repo/agents/.agents/global-agents.md" ]] ||
    fail "leaf link does not resolve into the clone"
  [[ $(readlink -f -- "$home/.claude/CLAUDE.md") == "$repo/agents/.agents/global-agents.md" ]] ||
    fail "Claude user instructions symlink did not deploy"
  [[ $(readlink -f -- "$home/.claude/skills/commit/SKILL.md") == "$repo/agents/.agents/skills/commit/SKILL.md" ]] ||
    fail "Claude skill symlink did not deploy"
  [[ $(readlink -f -- "$home/.claude/skills/commit/scripts/commit-apply") == "$repo/agents/.agents/skills/commit/scripts/commit-apply" ]] ||
    fail "Claude skill scripts symlink did not deploy"
  [[ -x $home/.agents/skills/publish/scripts/publish-apply &&
     $(readlink -f -- "$home/.claude/skills/publish/scripts/publish-apply") == "$repo/agents/.agents/skills/publish/scripts/publish-apply" ]] ||
    fail "exact-publication wrapper did not deploy through both skill paths"
  for tool in spar-claude spar-opencode spar-payload-scan; do
    [[ $(readlink -f -- "$home/.claude/skills/spar/scripts/$tool") == "$repo/agents/.agents/skills/spar/scripts/$tool" ]] ||
      fail "Claude spar link for $tool does not reach its own source"
  done
  [[ $(readlink -f -- "$home/.agents/skills/commit/SKILL.md") == "$repo/agents/.agents/skills/commit/SKILL.md" ]] ||
    fail "skill leaf link does not resolve into the clone"
  printf 'host-local\n' >"$root/package.json"
  mkdir "$root/node_modules"
  prepare "$home" "$repo"
  deploy "$home" "$repo" >/dev/null 2>&1 || fail "restow failed with host-local generated state present"
  [[ ! -L $root/package.json && $(<"$root/package.json") == "host-local" && -d $root/node_modules ]] ||
    fail "restow changed host-local generated state"
  [[ ! -e $repo/opencode/.config/opencode/package.json ]] || fail "generated state reached the package source"
  undeploy "$home" "$repo" >/dev/null 2>&1 || fail "unstow failed"
  [[ ! -e $home/.claude/CLAUDE.md && ! -e $home/.agents/skills/commit && -d $home/.agents/skills && -f $root/package.json ]] ||
    fail "unstow removed the wrong things"
}

case_skill_links() {
  local home="$TMP/links/home" repo="$TMP/links/eyragents"
  mkdir -p "$home/.agents/skills/commit/scripts"
  make_clone "$repo"
  # The leaf-link layout an earlier no-folding deploy left behind becomes one link,
  # a dangling link from a retired package entry inside it included.
  ln -s "$repo/agents/.agents/skills/commit/SKILL.md" "$home/.agents/skills/commit/SKILL.md"
  ln -s "$repo/agents/.agents/skills/commit/scripts/commit-apply" "$home/.agents/skills/commit/scripts/commit-apply"
  ln -s "$repo/codex/.agents/skills/commit/scripts/retired" "$home/.agents/skills/commit/scripts/retired"
  HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null || fail "link-skills failed on the leaf-link layout"
  [[ -L $home/.agents/skills/commit && $(readlink -f -- "$home/.agents/skills/commit") == "$repo/agents/.agents/skills/commit" ]] ||
    fail "the leaf-link skill directory was not replaced by one link"
  [[ -L $home/.agents/skills/spar ]] || fail "a missing skill directory was not linked"
  HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null || fail "link-skills is not idempotent"
  # A foreign entry stops the conversion and stays.
  rm "$home/.agents/skills/spar"
  mkdir -p "$home/.agents/skills/spar"
  printf 'mine\n' >"$home/.agents/skills/spar/notes.md"
  if HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null 2>&1; then fail "link-skills replaced a directory holding a foreign entry"; fi
  [[ -f $home/.agents/skills/spar/notes.md ]] || fail "link-skills removed a foreign entry"
  rm -r "$home/.agents/skills/spar"
  # A link that resolves elsewhere is refused, not repointed.
  mkdir -p "$TMP/links/elsewhere"
  ln -s "$TMP/links/elsewhere" "$home/.agents/skills/spar"
  if HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null 2>&1; then fail "link-skills repointed a foreign link"; fi
  [[ $(readlink -- "$home/.agents/skills/spar") == "$TMP/links/elsewhere" ]] || fail "link-skills changed a foreign link"
  rm "$home/.agents/skills/spar"
  # A moved clone's selected skill link is recognized, unlike a foreign dangling link.
  ln -s "$TMP/links/old/agents/.agents/skills/spar" "$home/.agents/skills/spar"
  HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null || fail "a recognized moved-clone skill link was not migrated"
  [[ $(readlink -f -- "$home/.agents/skills/spar") == "$repo/agents/.agents/skills/spar" ]] || fail "moved-clone skill link did not reach this clone"
  HOME=$home bash "$repo/scripts/prepare-stow.sh" --unlink-skills >/dev/null || fail "unlink-skills failed"
  [[ ! -e $home/.agents/skills/commit && -d $home/.agents/skills ]] || fail "unlink-skills left the link or removed the root"
}

case_skill_preflight() {
  local kind home repo before after out mode
  for kind in file dangling foreign dangling-root; do
    home="$TMP/preflight-$kind/home"; repo="$TMP/preflight-$kind/eyragents"
    mkdir -p "$home/.agents/skills/commit/scripts" "$home/.agents/skills/spar/scripts"
    make_clone "$repo"
    ln -s "$repo/agents/.agents/skills/commit/SKILL.md" "$home/.agents/skills/commit/SKILL.md"
    ln -s "$repo/codex/.agents/skills/commit/scripts/retired" "$home/.agents/skills/commit/scripts/retired"
    ln -s "$repo/agents/.agents/skills/spar/scripts/spar-claude" "$home/.agents/skills/spar/scripts/spar-claude"
    case $kind in
      file) printf 'keep my notes\n' >"$home/.agents/skills/spar/notes.md" ;;
      dangling) ln -s "$TMP/missing/foreign-tool" "$home/.agents/skills/spar/scripts/foreign" ;;
      foreign) ln -s "$repo/agents/.agents/skills/commit/scripts/commit-apply" "$home/.agents/skills/spar/scripts/foreign" ;;
      dangling-root)
        rm -r -- "$home/.agents/skills/spar"
        ln -s "$TMP/missing/foreign-skill" "$home/.agents/skills/spar" ;;
    esac
    before=$(find "$home" -printf '%y %p %l\n' | sort)
    for mode in --check-skills --link-skills --unlink-skills ''; do
      local -a args=()
      [[ -z $mode ]] || args=("$mode")
      if out=$(HOME=$home bash "$repo/scripts/prepare-stow.sh" "${args[@]}" 2>&1); then fail "preflight accepted $kind via $mode"; fi
      [[ $out == *foreign* || $out == *unmanaged* ]] || fail "unexpected preflight refusal: $out"
      after=$(find "$home" -printf '%y %p %l\n' | sort)
      [[ $before == "$after" ]] || fail "$mode partially migrated skills before refusing $kind"
      [[ $kind != file || $(<"$home/.agents/skills/spar/notes.md") == 'keep my notes' ]] || fail "foreign file contents changed"
    done
    if HOME=$home make --no-print-directory -C "$repo" -j8 restow clean >/dev/null 2>&1; then fail "Make accepted a conflicting skill"; fi
    [[ $before == "$(find "$home" -printf '%y %p %l\n' | sort)" ]] || fail "Make cleaned before all selected skills passed preflight"
  done
}

case_make_guards() {
  local home="$TMP/make/home" repo="$TMP/make/eyragents" other="$TMP/make/deployed" bin="$TMP/make/bin" target out
  mkdir -p "$home/.claude" "$bin"
  make_clone "$repo"
  make_clone "$other"
  ln -s "$other/claude-code/.claude/settings.json" "$home/.claude/settings.json"
  ln -s "$TMP/make/old/claude-code/.claude/hooks" "$home/.claude/hooks"
  cat >"$bin/bash" <<'SH'
#!/bin/bash
if [[ ${1:-} == scripts/prepare-stow.sh ]]; then
  case ${2:-} in
    --require-clone) printf 'guard\n' >>"$EYR_TEST_EVENTS"; sleep 0.05 ;;
    --check-skills) ;;
    *) printf 'write\n' >>"$EYR_TEST_EVENTS" ;;
  esac
fi
exec /bin/bash "$@"
SH
  chmod +x "$bin/bash"
  for target in stow unstow restow clean install-gate 'clean restow' 'restow clean'; do
    : >"$TMP/make/events"
    local -a goals=()
    read -r -a goals <<<"$target"
    if out=$(HOME=$home PATH="$bin:$PATH" EYR_TEST_EVENTS="$TMP/make/events" make --no-print-directory -C "$repo" -j8 "${goals[@]}" 2>&1); then
      fail "Make accepted a wrong deployed clone: $target"
    fi
    [[ $out == *'another clone'* ]] || fail "Make failed for the wrong reason ($target): $out"
    [[ $(<"$TMP/make/events") != *write* ]] || fail "cleanup started before the clone guard refused: $target"
    [[ -L $home/.claude/hooks && $(readlink -- "$home/.claude/settings.json") == "$other/claude-code/.claude/settings.json" ]] || fail "Make changed links before refusal: $target"
  done
  for target in '' --link-skills --unlink-skills; do
    local -a args=()
    [[ -z $target ]] || args=("$target")
    if HOME=$home bash "$repo/scripts/prepare-stow.sh" "${args[@]}" >/dev/null 2>&1; then fail "direct preparation accepted a wrong clone: $target"; fi
    [[ -L $home/.claude/hooks ]] || fail "direct preparation cleaned before refusal"
  done
  rm -- "$home/.claude/settings.json"
  ln -s "$repo/claude-code/.claude/settings.json" "$home/.claude/settings.json"
  : >"$TMP/make/events"
  HOME=$home PATH="$bin:$PATH" EYR_TEST_EVENTS="$TMP/make/events" make --no-print-directory -C "$repo" -j8 clean >/dev/null || fail "guarded Make clean failed in the deployed fixture"
  [[ $(<"$TMP/make/events") == $'guard\nwrite' && ! -L $home/.claude/hooks ]] || fail "guard and cleanup were not ordered"
}

case_install_gate() {
  local scenario base home repo gate before after out target
  for scenario in override-repo agents-fold hooks-fold endpoint-link dangling-endpoint hardlink override-expression home-in-repo home-in-other-repo; do
    base="$TMP/install-$scenario"; home="$base/home"; repo="$base/eyragents"
    mkdir -p "$home" "$base/bin"
    make_clone "$repo"
    gate="$home/.agents/hooks/commit-gate"
    case $scenario in
      agents-fold) ln -s "$repo/agents/.agents" "$home/.agents" ;;
      hooks-fold)
        mkdir "$home/.agents"
        ln -s "$repo/templates/hooks" "$home/.agents/hooks" ;;
      endpoint-link|dangling-endpoint|hardlink)
        mkdir -p "$home/.agents/hooks"
        if [[ $scenario == endpoint-link ]]; then ln -s "$repo/templates/hooks/commit-gate" "$gate"
        elif [[ $scenario == hardlink ]]; then ln "$repo/templates/hooks/commit-gate" "$gate"
        else ln -s "$repo/templates/hooks/absent" "$gate"; fi ;;
      override-repo) gate="$repo/templates/hooks/commit-gate" ;;
      override-expression) gate="\$(shell touch INSTALL_MARKER)" ;;
      home-in-repo) home="$repo/fake-home"; mkdir "$home"; gate="$home/.agents/hooks/commit-gate" ;;
      home-in-other-repo)
        make_clone "$base/other-repo"
        home="$base/other-repo/fake-home"; mkdir "$home"; gate="$home/.agents/hooks/commit-gate" ;;
    esac
    # A rejecting guard must not invoke install, even when the fold is ours.
    cat >"$base/bin/install" <<'SH'
#!/bin/bash
touch "$EYR_INSTALL_CALLED"
exit 99
SH
    chmod +x "$base/bin/install"
    before=$(find "$home" "$repo" -path '*/.git' -prune -o -printf '%y %p %l\n' | sort)
    for target in install-gate verify-deploy; do
      if out=$(HOME=$home PATH="$base/bin:$PATH" EYR_INSTALL_CALLED="$base/install-called" make --no-print-directory -C "$repo" "$target" "GATE=$gate" 2>&1); then
        fail "$target accepted $scenario"
      fi
      [[ $out == *gate* || $out == *GATE* ]] || fail "$target failed for an unrelated reason: $out"
      [[ $out != *'installed commit gate matches'* ]] || fail "$target falsely attested the gate for $scenario"
      [[ ! -e $base/install-called && ! -e $repo/INSTALL_MARKER ]] || fail "install or Make expansion ran before refusal: $scenario"
      after=$(find "$home" "$repo" -path '*/.git' -prune -o -printf '%y %p %l\n' | sort)
      [[ $before == "$after" ]] || fail "$target refusal changed the layout: $scenario"
      cmp -s "$ROOT/templates/hooks/commit-gate" "$repo/templates/hooks/commit-gate" || fail "$target changed source bytes: $scenario"
    done
  done
  base="$TMP/install-normal"; home="$base/home"; repo="$base/eyragents"
  mkdir -p "$home"
  make_clone "$repo"
  HOME=$home make --no-print-directory -C "$repo" install-gate >/dev/null || fail "standalone safe gate installation failed"
  gate="$home/.agents/hooks/commit-gate"
  [[ -f $gate && ! -L $gate && -x $gate && -d $home/.agents/hooks && ! -L $home/.agents/hooks ]] || fail "installed gate is not host-local with real parents"
  HOME=$home make --no-print-directory -C "$repo" -j8 stow >/dev/null 2>&1 || fail "normal stow failed with the hardened gate installer"
  cmp -s "$repo/templates/hooks/commit-gate" "$gate" || fail "normal stow did not install the gate copy"
  [[ $(stat -c '%i' -- "$gate") != "$(stat -c '%i' -- "$repo/templates/hooks/commit-gate")" ]] || fail "installed gate shares the source inode"
  before=$(stat -c '%i %a %s %y %z' -- "$gate")
  HOME=$home bash "$repo/scripts/prepare-stow.sh" --check-gate >/dev/null || fail "valid installed gate was refused"
  [[ $before == "$(stat -c '%i %a %s %y %z' -- "$gate")" ]] || fail "gate verification rewrote the endpoint"
  for scenario in missing drift nonexecutable; do
    cp -- "$repo/templates/hooks/commit-gate" "$gate"
    chmod 755 "$gate"
    case $scenario in
      missing) rm -- "$gate" ;;
      drift) printf 'changed gate\n' >>"$gate" ;;
      nonexecutable) chmod a-x "$gate" ;;
    esac
    before=$(find "$home" -printf '%y %p %l\n' | sort)
    if out=$(HOME=$home bash "$repo/scripts/prepare-stow.sh" --check-gate 2>&1); then fail "gate verification accepted $scenario"; fi
    [[ $out == *'installed commit gate is missing, not executable, unreadable, or drifted'* ]] || fail "gate verification refused $scenario for the wrong reason: $out"
    [[ $before == "$(find "$home" -printf '%y %p %l\n' | sort)" ]] || fail "gate verification changed layout for $scenario"
  done
  home="$base/empty-home"; mkdir "$home"
  if HOME=$home bash "$repo/scripts/prepare-stow.sh" --check-gate >/dev/null 2>&1; then fail "gate verification accepted an undeployed home"; fi
  [[ ! -e $home/.agents ]] || fail "gate verification created directories"
}

case_clean_links
case_no_folding
case_skill_links
case_skill_preflight
case_make_guards
case_install_gate
printf 'ok: prepare-stow removes only dangling managed links, links skill directories, and guards the installed gate\n'
