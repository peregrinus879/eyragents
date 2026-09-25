#!/usr/bin/env python3
"""Check the managed tool configurations against the global guidance.

Both tools must reach the same decision for the same command or path: read
freely, ask before remote or destructive actions, and deny secrets, personal
folders and privilege escalation. This models each tool's documented matching
(Claude Code: deny, then ask, then allow; OpenCode: last matching rule wins).
It checks configuration, not live dispatch.
"""

from __future__ import annotations

import json
import os
import posixpath
import re
from pathlib import Path

ROOT = Path(os.environ.get("CONFIG_CONTRACT_ROOT", Path(__file__).resolve().parent.parent))
HOME = "/fixture-home"
WORKTREE = HOME + "/Projects/eyrie/repo"


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def load(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


claude = load("claude-code/.claude/settings.json")
opencode = load("opencode/.config/opencode/opencode.json")


# Claude Code matching: https://code.claude.com/docs/en/permissions
def claude_bash_match(rule: str, command: str) -> bool:
    if rule.endswith(" *") and rule.count("*") == 1:
        pattern = re.escape(rule[:-2]) + "(?: .*)?"
    else:
        pattern = ".*".join(re.escape(part) for part in rule.split("*"))
    return re.fullmatch(pattern, command, re.S) is not None


def claude_path_regex(rule: str) -> str:
    if rule.startswith("//"):
        rule = rule[1:]
    elif rule.startswith("~/"):
        rule = HOME + rule[1:]
    out, i = "", 0
    while i < len(rule):
        if rule.startswith("/**/", i):
            out, i = out + "/(?:.*/)?", i + 4
        elif rule.startswith("/**", i) and i + 3 == len(rule):
            out, i = out + "(?:/.*)?", i + 3
        elif rule.startswith("**", i):
            out, i = out + ".*", i + 2
        elif rule[i] == "*":
            out, i = out + "[^/]*", i + 1
        else:
            out, i = out + re.escape(rule[i]), i + 1
    return out


def claude_decision(tool: str, subject: str) -> str:
    permissions = claude["permissions"]
    for action in ("deny", "ask", "allow"):
        for rule in permissions.get(action, []):
            name, _, body = rule.partition("(")
            if name != tool or not body.endswith(")"):
                continue
            body = body[:-1]
            if tool == "Bash":
                hit = claude_bash_match(body, subject)
            else:
                hit = re.fullmatch(claude_path_regex(body), subject) is not None
            if hit:
                return action
    return "auto"  # the auto-mode classifier decides; not a rule outcome


# OpenCode matching: packages/opencode/src/util/wildcard.ts and permission/index.ts
def oc_match(subject: str, pattern: str) -> bool:
    if pattern.startswith("~/"):
        pattern = HOME + pattern[1:]
    escaped = "".join(".*" if ch == "*" else "." if ch == "?" else re.escape(ch) for ch in pattern)
    if escaped.endswith(r"\ .*"):
        escaped = escaped[:-4] + "(?: .*)?"
    return re.fullmatch(escaped, subject, re.S) is not None


def oc_rules(permission: dict, key: str, agent: dict | None = None):
    rules = []
    for source in (permission, (agent or {}).get("permission", {})):
        value = source.get(key)
        if isinstance(value, str):
            rules.append(("*", value))
        elif isinstance(value, dict):
            rules += list(value.items())
    return rules


def oc_last(rules, subject: str) -> str:
    result = "allow"  # OpenCode's own default is "*": "allow"
    for pattern, action in rules:
        if oc_match(subject, pattern):
            result = action
    return result


def oc_file(key: str, path: str, agent: dict | None = None, worktree: str = WORKTREE, launch: str | None = None) -> str:
    """Decision for a native read or edit of an absolute path; subjects are worktree-relative.

    OpenCode skips the external-directory check for paths under the worktree or the launch directory."""
    def under(base: str) -> bool:
        return base == "/" or path == base or path.startswith(base + "/")
    if not (under(worktree) or under(launch or worktree)):
        external = oc_last(oc_rules(opencode["permission"], "external_directory", agent), posixpath.dirname(path) + "/*")
        if external == "deny":
            return "deny"
    return oc_last(oc_rules(opencode["permission"], key, agent), posixpath.relpath(path, worktree))


# --- Commands: the same decision in both tools --------------------------------------------
GH_READ = {
    "issue": ["list", "status", "view"], "pr": ["list", "status", "view", "checks", "diff", "checkout"],
    "release": ["list", "view", "download", "verify"], "gist": ["list", "view"], "repo": ["view", "clone", "read-file"],
    "run": ["list", "view", "watch"], "workflow": ["list", "view"], "label": ["list"], "variable": ["list", "get"],
    "codespace": ["list", "view", "logs"], "discussion": ["list", "view"], "skill": ["list", "search"],
    "agent-task": ["list", "view"], "extension": ["list", "exec"], "search": ["issues", "prs"], "ruleset": ["list"],
}
GH_WRITE = {
    "issue": ["create", "comment", "edit", "close", "reopen", "delete", "develop", "lock", "transfer"],
    "pr": ["create", "comment", "edit", "review", "ready", "merge", "close", "revert", "update-branch"],
    "release": ["create", "edit", "upload", "delete", "delete-asset"], "gist": ["create", "edit", "rename", "delete"],
    "repo": ["create", "edit", "rename", "fork", "sync", "archive", "delete"],
    "run": ["rerun", "cancel", "delete"], "workflow": ["run", "enable", "disable"], "label": ["create", "delete"],
    "variable": ["set", "delete"], "cache": ["delete"], "project": ["create", "item-add", "delete"],
    "codespace": ["create", "delete", "ssh", "ports", "cp", "stop"], "discussion": ["create", "comment", "edit"],
    "skill": ["install", "update", "publish"], "agent-task": ["create"], "extension": ["install", "upgrade", "remove"],
}
COMMANDS = {
    # gh api is gated whole: method, field and input flags combine and reorder freely (-iX, -if, -XPOST).
    "gh api repos/o/r": "ask", "gh api -X GET repos/o/r": "ask", "gh api -iX DELETE repos/o/r": "ask",
    "gh api -iXDELETE repos/o/r": "ask", "gh api -if title=x repos/o/r/issues": "ask",
    "gh api -iF title=x repos/o/r/issues": "ask", "gh api --method PATCH user": "ask",
    "gh api graphql -f query='mutation { x }'": "ask",
    "gh alias set co 'pr checkout'": "ask", "gh alias import aliases.yml": "ask", "gh alias delete co": "ask",
    # Credentials are H's: all of gh auth, key and secret writes.
    "gh auth status": "deny", "gh auth status -at": "deny", "gh auth token": "deny", "gh auth login": "deny",
    "gh secret set TOKEN": "deny", "gh secret delete TOKEN": "deny", "gh ssh-key add key.pub": "deny",
    "gh gpg-key delete 1": "deny",
    # git clean is gated whole: -i and clean.requireForce=false delete without -f.
    "git clean -fd": "ask", "git clean -dfx": "ask", "git clean -i": "ask", "git clean -d": "ask", "git clean -n": "ask",
    "git -C /x clean -fd": "ask",
    "git reset --hard HEAD": "ask", "git reset": "ask", "git -C /x reset --hard": "ask", "git -C /x reset": "ask",
    "git restore file": "ask", "git checkout -- file": "ask", "git stash drop": "ask", "git branch -D topic": "ask",
    # Git configuration writes: a dotted key with a value, editors, and every mutating option or subcommand.
    "git config --global user.name x": "ask", "git config core.hooksPath hooks": "ask", "git config set user.name x": "ask",
    "git config --unset user.name": "ask", "git config --global --unset alias.co": "ask", "git config --edit": "ask",
    "git config --global -e": "ask", "git config --system -e": "ask", "git -C /x config --global -e": "ask",
    "git config --global --add include.path x": "ask", "git config --global --replace-all core.pager less": "ask",
    "git config --remove-section alias": "ask", "git config edit": "ask", "git -C /x config user.name y": "ask",
    "git -c core.pager=cat config --global user.name y": "ask",
    "git remote set-url origin u": "ask", "git -C /x remote add up u": "ask",
    "ssh host": "ask", "scp a host:b": "ask", "sudo pacman -Syu": "deny", "su": "deny", "pkexec true": "deny",
    # Commits and pushes ask: H approves each at the native prompt, also behind global options.
    "git push": "ask", "git push origin main": "ask", "git -C /x push": "ask", "git -c push.default=current push": "ask",
    "git --no-pager push origin main": "ask", "git --git-dir=/x/.git push": "ask",
    "git commit -m x": "ask", "git commit": "ask", "git -C /x commit -F msg": "ask", "git -c core.hooksPath=/x commit -m x": "ask",
    "git merge topic": "ask", "git pull": "ask", "git rebase main": "ask", "git cherry-pick abc": "ask", "git revert abc": "ask",
    "git am patch.mbox": "ask", "git commit-tree abc -m x": "ask", "git update-ref refs/heads/x abc": "ask",
    "git replace abc def": "ask", "git filter-branch --all": "ask", "git notes add -m x": "ask", "git fast-import": "ask",
    "git -C/x commit -m x": "ask", "git -cuser.name=x commit -m x": "ask", "git -C/x push": "ask",
    "git notes --ref=x add -m y": "ask", "git notes remove HEAD": "ask", "git notes prune": "ask",
    # Every form of another agent client is gated: launches, exports, auth, uninstall.
    "opencode": "deny", "opencode .": "deny", "opencode run x": "deny", "opencode serve": "deny",
    "opencode export ses_1": "deny", "opencode auth login": "deny", "opencode uninstall --force": "deny",
    "gh copilot": "deny", "gh copilot -p x": "deny", "copilot -p x": "deny", "gemini": "deny", "cursor-agent -p x": "deny",
    "crush run x": "deny",
    "git status": "allow", "git log --oneline": "allow", "git diff": "allow", "git fetch": "allow",
    "gh status": "allow", "gh co 12": "allow", "gh config set editor nvim": "allow",
    "ls -la": "allow", "make check": "allow", "pacman -Qi git": "allow",
    # Options before the verb, abbreviated long options and destructive checkout forms.
    "gh secret -R o/r set TOKEN": "deny", "gh secret --repo o/r delete TOKEN": "deny", "gh ssh-key -R x add k": "deny",
    "gh issue -R o/r comment 1 -b x": "ask", "gh pr --repo o/r merge 1": "ask", "gh release -R o/r delete v1": "ask",
    "git config --global --rename alias renamed": "ask", "git config --global --remove alias": "ask",
    "git config --global --ad include.path x": "ask", "git config --global --unset-all x": "ask",
    "git config --global --ed": "ask", "git branch --del topic": "ask", "git branch -dr origin/x": "ask",
    "git branch -Df topic": "ask", "git checkout .": "ask", "git checkout HEAD -- file": "ask",
    "git checkout -f main": "ask", "git switch --discard-changes main": "ask", "git switch -f main": "ask",
    "git remote --verbose add up u": "ask",
}
# Reads never prompt, except in families gated whole (gh api, git clean, gh auth, other agent
# clients) and a few Git configuration reads shaped like writes (a dotted token followed by another
# argument). Prompt-free paths exist for those: gh subcommands, `git status --ignored`, and reading
# the Git configuration files directly.
READS = [
    "git config --global --get core.excludesFile", "git config --get user.email", "git config user.email",
    "git config --list", "git config --global --list", "git config -l", "git config --get-regexp alias",
    "git config --show-origin --list", "git config get user.email", "git config list", "git config alias.co",
    "git config core.hooksPath", "git config credential.helper", "git -C /x config --get user.email",
    "git remote -v", "git remote show origin", "git remote get-url origin", "git branch -a", "git branch --list",
    "git stash list", "git stash show -p", "git status --ignored", "git log -1", "git show HEAD",
    "git diff --cached", "git var GIT_AUTHOR_IDENT", "git log --grep push",
    "gh secret list", "gh ssh-key list", "gh gpg-key list", "gh variable list", "gh alias list",
    "gh run view 1 --log", "gh workflow view ci", "gh repo view", "gh search repos x", "gh cache list",
    "gh label list", "gh release list", "claude --version",
    "git config --get my.flag-example", "gh issue -R o/r list", "gh pr --repo o/r view 1",
    "git branch --sort=-committerdate", "git checkout main", "git checkout -b feat", "git switch main",
    "git notes show HEAD", "git notes list", "git notes", "git notes --ref=x show HEAD",
    # Stash entries are local and recoverable, and never reach the reviewed history: not gated.
    "git stash", "git stash push -m checkpoint", "git stash pop",
    "gh -R o/r pr view 1", "gh --repo o/r issue list", "gh repo autolink list", "gh repo -R o/r autolink view 1",
    "gh repo deploy-key list", "gh -R o/r repo deploy-key list", "git reflog", "git worktree list", "git gc",
    "npm view x", "docker pull x", "cargo build",
]
COMMANDS.update({command: "allow" for command in READS})
# Leading options before the gh group, nested gh write verbs, history-destroying Git and publication.
COMMANDS.update({command: "ask" for command in (
    "gh --repo o/r pr merge 1", "gh -R o/r issue comment 1 -b x", "gh -R o/r api repos/o/r",
    "gh repo autolink create x y", "gh repo -R o/r autolink delete 1", "gh repo deploy-key add k.pub",
    "gh -R o/r repo deploy-key delete 1", "git reflog expire --expire=now --all", "git -C /x reflog delete HEAD@{1}",
    "git gc --prune=now", "git -C /x gc --aggressive --prune=now", "git worktree remove ../w",
    "npm publish", "npm --workspace x publish", "pnpm publish --access public", "yarn npm publish",
    "cargo publish", "docker push r/i:t", "docker image push r/i", "twine upload dist/*")})
for group, verbs in GH_READ.items():
    COMMANDS.update({f"gh {group} {verb} 1": "allow" for verb in verbs})
for group, verbs in GH_WRITE.items():
    COMMANDS.update({f"gh {group} {verb} 1": "ask" for verb in verbs})
    COMMANDS.update({f"gh {group} {verb}": "ask" for verb in verbs})

for command, expected in COMMANDS.items():
    got_claude = claude_decision("Bash", command)
    got_claude = "allow" if got_claude == "auto" else got_claude
    got_opencode = oc_last(oc_rules(opencode["permission"], "bash"), command)
    require(got_claude == expected, f"Claude decides {got_claude} for `{command}`, expected {expected}")
    require(got_opencode == expected, f"OpenCode decides {got_opencode} for `{command}`, expected {expected}")
for command in ("claude -p x", "claude --bg review", "claude remote-control", "claude", "opencode --help"):
    require(oc_last(oc_rules(opencode["permission"], "bash"), command) == "deny", f"OpenCode can run `{command}`")
# Remote Control is a sharing surface in both tools; a nested `claude -p` stays open in Claude Code.
for command in ("claude remote-control", "claude --remote-control", "claude --rc work", "claude -c --rc"):
    require(claude_decision("Bash", command) == "deny", f"Claude can start Remote Control: `{command}`")
require(claude_decision("Bash", "claude -p x") == "auto", "Claude refuses a nested print session")
# OpenCode has no classifier, so recursive or forced deletion asks there; Claude Code's classifier reviews it.
for command in ("rm -rf build", "rm -f x", "rm --recursive d", "rm d -r"):
    require(oc_last(oc_rules(opencode["permission"], "bash"), command) == "ask", f"OpenCode deletes without asking: `{command}`")
    require(claude_decision("Bash", command) == "auto", f"Claude has a rule for `{command}`; its classifier decides")
for command in ("rm x", "rm my-file.txt"):
    require(oc_last(oc_rules(opencode["permission"], "bash"), command) == "allow", f"OpenCode asks for `{command}`")
require(claude_decision("Bash", "opencode --version") == "deny", "Claude can run the OpenCode client")
require(oc_last(oc_rules(opencode["permission"], "bash"), "opencode --version") == "allow", "OpenCode version check denied")

# --- Paths: secrets and personal folders denied, everything else readable --------------------
PROTECTED = [
    "~/.ssh/id_ed25519", "~/.ssh/config", "~/.aws/credentials", "~/.gnupg/pubring.kbx", "~/.kube/config",
    "~/.password-store/x.gpg", "~/.local/share/keyrings/login.keyring", "~/.mozilla/firefox/p/logins.json",
    "~/.config/google-chrome/Default/Login Data", "~/.config/1Password/x", "~/.config/gh/hosts.yml",
    "~/.docker/config.json", "~/.netrc", "~/.npmrc", "~/.pypirc", "~/.claude/.credentials.json", "~/.codex/auth.json",
    "~/.local/share/opencode/auth.json", "~/.bash_history", "~/.zsh_history", "~/.local/share/fish/fish_history",
    "~/.python_history", "~/.node_repl_history", "~/.psql_history", "~/.mysql_history",
    "~/.claude.json", "~/.claude/backups/.claude.json.backup.1", "~/.claude/.credentials.json.bak",
    "/etc/shadow", "{w}/backup/etc/shadow", "{w}/backup/etc/gshadow-", "/proc/kcore", "{w}/backup/proc/kcore",
    "/etc/NetworkManager/system-connections/wifi.nmconnection",
    "{w}/backup/etc/NetworkManager/system-connections/wifi.nmconnection",
    "/proc/1234/environ", "/var/lib/systemd/coredump/core.x.zst", "/var/crash/x",
    "/mnt/c/Users/h/AppData/Local/Google/Chrome/User Data/Default/Login Data",
    "/mnt/c/Users/h/AppData/Roaming/Microsoft/Credentials/x", "/mnt/c/Users/h/.ssh/id_rsa",
    "{w}/.env", "{w}/.env.local", "{w}/config/server.key", "{w}/certs/site.pem", "{w}/id_rsa", "{w}/auth.json",
    "{w}/credentials", "{w}/secrets/token.txt", "{w}/backup/.ssh/id_rsa", "{w}/etc/ssh/ssh_host_ed25519_key",
    "~/Projects/other/.env",
]
PERSONAL = ["~/Desktop/a.txt", "~/Documents/tax.pdf", "~/Downloads/x.zip", "~/Music/a.mp3", "~/Pictures/a.jpg",
            "~/Sync/notes.md", "~/Videos/a.mp4", "/mnt/c/Users/h/Documents/a.docx", "/mnt/c/Users/h/OneDrive/a.xlsx",
            "/mnt/c/Users/h/Sync/a.md"]
# Conversation transcripts are readable and never editable.
TRANSCRIPTS = ["~/.claude/projects/p/session.jsonl", "~/.claude/projects/p/s/subagents/a.jsonl", "~/.codex/sessions/s.jsonl",
               "~/.local/share/opencode/storage/session/s.json", "~/.local/share/opencode/opencode.db"]
READABLE = ["{w}/README.md", "{w}/src/auth.py", "{w}/example.env", "{w}/docs/credentials-policy.md",
            "~/Projects/other/README.md", "~/Projects/quarry/opencode/README.md", "~/Projects/eyrie/scrape/x.md",
            "~/.bashrc", "~/.config/nvim/init.lua", "~/.config/git/config", "~/.config/gh/config.yml",
            "~/.local/share/opencode/tool-output/out.txt", "~/.claude/projects/p/memory/MEMORY.md", "~/Work/tries/a.md",
            "/etc/os-release", "/usr/share/omarchy/README.md", "/proc/cpuinfo", "/sys/class/net/lo/operstate",
            "/var/lib/pacman/local/ALPM_DB_VERSION", "/tmp/x.txt"]


def expand(path: str) -> str:
    return path.replace("{w}", WORKTREE).replace("~/", HOME + "/")


for path in PROTECTED + PERSONAL:
    full = expand(path)
    for tool, key in (("Read", "read"), ("Edit", "edit")):
        require(claude_decision(tool, full) == "deny", f"Claude {tool} reaches protected {path}")
        require(oc_file(key, full) == "deny", f"OpenCode {key} reaches protected {path}")
for path in READABLE:
    full = expand(path)
    require(claude_decision("Read", full) == "allow", f"Claude cannot read {path}")
    require(oc_file("read", full) == "allow", f"OpenCode cannot read {path}")
for path in TRANSCRIPTS:
    full = expand(path)
    require(claude_decision("Read", full) == "allow" and oc_file("read", full) == "allow", f"a tool cannot read {path}")
    require(claude_decision("Edit", full) == "deny" and oc_file("edit", full) == "deny", f"a tool can edit {path}")
# A session launched from a home directory or / sees personal folders under its own launch directory,
# where OpenCode skips the external-directory check; the read and edit rules still deny them.
for path in ("/home/h/Documents/tax.pdf", "/home/h/Sync/n.md", "/mnt/c/Users/h/Documents/a.docx", "/mnt/c/Users/h/Sync/a.md"):
    for key in ("read", "edit"):
        require(oc_file(key, path, worktree="/", launch="/home/h") == "deny", f"OpenCode {key} reaches {path} from a home launch")

# Writes: the repository and persistent scratch run freely; elsewhere needs H.
for path in ("{w}/src/app.py", "~/Projects/eyrie/scrape/work/x.md"):
    require(claude_decision("Edit", expand(path)) in ("allow", "auto") and oc_file("edit", expand(path)) == "allow",
            f"routine edit blocked: {path}")
require(claude_decision("Edit", expand("~/Projects/eyrie/scrape/work/x.md")) == "allow", "Claude lacks the scratch edit grant")
# OpenCode matches edits relative to the worktree, so the grants must hold wherever the session starts.
for worktree in (WORKTREE, HOME + "/Projects/quarry/opencode", HOME + "/Work/tries/a", "/tmp/canary.x/repo"):
    require(oc_file("edit", expand("~/Projects/eyrie/scrape/work/x.md"), worktree=worktree) == "allow",
            f"OpenCode cannot write persistent scratch from {worktree}")
    for path in ("~/Projects/other/app.py", "~/.bashrc", "~/Projects/eyrie/other/scrape/x"):
        require(oc_file("edit", expand(path), worktree=worktree) == "ask",
                f"OpenCode edits {path} from {worktree} without asking")
# Accepted limit (docs/access.md): from a repository inside persistent scratch, edits elsewhere in scratch ask.
require(oc_file("edit", expand("~/Projects/eyrie/scrape/plans/p.md"), worktree=HOME + "/Projects/eyrie/scrape/fixture/repo") == "ask",
        "OpenCode's scratch-inside-scratch behavior changed; update docs/access.md")
for worktree in (WORKTREE, HOME + "/Projects/quarry/opencode", HOME + "/Work/tries/a"):
    require(oc_file("edit", "/tmp/opencode/session/x.md", worktree=worktree) == "allow",
            f"OpenCode cannot write its own temp root from {worktree}")
for path in ("~/Projects/other/app.py", "~/.bashrc"):
    require(claude_decision("Edit", expand(path)) != "allow", f"Claude pre-approves an edit outside scope: {path}")
for path in ("{w}/.git/config", "{w}/.git/hooks/pre-commit", "~/.config/git/config", "~/.config/gh/config.yml"):
    require(claude_decision("Edit", expand(path)) == "deny", f"Claude can edit {path}")
    require(oc_file("edit", expand(path)) == "deny", f"OpenCode can edit {path}")
for worktree in (HOME + "/dotfiles", HOME + "/Projects/eyrie/eyragents", "/tmp/canary.x/repo"):
    require(oc_file("edit", expand("~/.config/git/config"), worktree=worktree) == "deny", f"OpenCode edits Git config from {worktree}")
require(oc_file("edit", "/home/h/.config/git/config", worktree="/", launch="/home/h") == "deny", "OpenCode edits Git config from /")
# A repository's tracked source for the deployed configuration, as in EyrWSL's git package, stays editable.
eyrwsl = HOME + "/Projects/eyrie/eyrwsl"
require(oc_file("edit", eyrwsl + "/git/.config/git/config", worktree=eyrwsl) == "allow", "OpenCode refuses EyrWSL's Git config source")
require(claude_decision("Read", "/tmp/opencode/s/x") == "deny", "Claude reads OpenCode's session root")
require(oc_file("read", "/tmp/claude-1000/s/x") == "deny", "OpenCode reads Claude Code's session root")

# --- Tool settings ---------------------------------------------------------------------------
permissions = claude["permissions"]
require(permissions["defaultMode"] == "auto" and permissions["disableBypassPermissionsMode"] == "disable",
        "Claude must run in auto mode with bypass disabled")
require("sandbox" not in claude, "Claude tracked settings enable sandboxing")
for section in ("allow", "soft_deny", "hard_deny"):
    require(claude["autoMode"][section][0] == "$defaults", f"Claude auto mode dropped built-in {section} rules")
require("personal folders" in " ".join(claude["autoMode"]["hard_deny"]), "Claude classifier lacks the personal-folder rule")
require(claude.get("attribution", {}).get("sessionUrl") is False, "Claude would add a session URL to commits")
require(claude.get("effortLevel") == "xhigh", "Claude Code effort is not xhigh")
require("CLAUDE_CODE_EFFORT_LEVEL" not in claude.get("env", {}), "the effort env var would override /effort and per-agent effort")
require(claude["autoMode"].get("environment", [None])[0] == "$defaults", "Claude auto mode lacks its environment entries")
# Uploads of conversation content and error reports stay off; metrics stay on for feature flags (docs/access.md).
for switch in ("DISABLE_FEEDBACK_COMMAND", "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY", "DISABLE_ERROR_REPORTING", "DISABLE_AUTOUPDATER"):
    require(claude.get("env", {}).get(switch) == "1", f"Claude Code {switch} is not set")
require("DISABLE_TELEMETRY" not in claude.get("env", {}), "Claude Code telemetry switch would stop feature flags")
require("hooks" not in claude, "Claude settings carry hooks; commits and pushes use native prompts")

require(opencode["share"] == "disabled" and opencode["autoupdate"] is False, "OpenCode sharing or autoupdate drifted")
primary = opencode["model"].split("/", 1)[1]
require(opencode["provider"]["openai"]["models"][primary]["options"]["reasoningEffort"] == "xhigh",
        "OpenCode primary model is not configured at xhigh")
require(not opencode.get("instructions"), "OpenCode duplicates native guidance")
# Native discovery finds ~/.agents/skills; the explicit path keeps them in the restricted untrusted-checkout launch.
require(opencode.get("skills") == {"paths": ["~/.agents/skills"]}, "OpenCode shared skill path drifted")
require(not (ROOT / "opencode/.config/opencode/plugins").exists(), "OpenCode plugins are back; commits use native prompts")
require(not (ROOT / "opencode/.config/opencode/commands").exists(), "OpenCode command wrappers are back; skills are native")

# Sparrers: the same charter in both tools; no edit tools, shell and web under the primary rules.
charter = (ROOT / "agents/.agents/agents/sparrer.md").read_text(encoding="utf-8")
claude_sparrer = (ROOT / "claude-code/.claude/agents/sparrer.md").read_text(encoding="utf-8")
front, body = claude_sparrer.split("---\n", 2)[1:]
fields = dict(line.split(":", 1) for line in front.strip().splitlines())
require(body.strip() == charter.strip(), "Claude sparrer body differs from the shared charter")
require({t.strip() for t in fields["tools"].split(",")} == {"Read", "Bash", "WebFetch", "WebSearch"},
        "Claude sparrer tools drifted: read, shell and web, never edit")
require(fields.get("effort", "").strip() == "xhigh", "Claude sparrer effort is not xhigh")
sparrer = opencode["agent"]["sparrer"]
require(sparrer["description"] == fields.get("description", "").strip(), "sparrer descriptions differ between the tools")
# "all" lets spar-opencode run the sparrer headless; a subagent would fall back to the build agent.
require(sparrer["mode"] == "all" and sparrer["prompt"] == "{file:~/.agents/agents/sparrer.md}", "OpenCode sparrer charter drifted")
for key in ("edit", "task"):
    require(oc_last(oc_rules(opencode["permission"], key, sparrer), "*") == "deny", f"OpenCode sparrer can use {key}")
for key in ("webfetch", "websearch"):
    require(oc_last(oc_rules(opencode["permission"], key, sparrer), "*") == "allow", f"OpenCode sparrer lacks {key}")
require(oc_last(oc_rules(opencode["permission"], "bash", sparrer), "git log -1") == "allow" and
        oc_last(oc_rules(opencode["permission"], "bash", sparrer), "git push") == "ask", "OpenCode sparrer shell does not follow the primary rules")
require(oc_file("read", expand("{w}/src/app.py"), sparrer) == "allow", "OpenCode sparrer cannot read the repository")
require(oc_file("read", expand("~/.ssh/id_rsa"), sparrer) == "deny", "OpenCode sparrer reads secrets")

# --- Loading and skills ----------------------------------------------------------------------
guidance = ROOT / "opencode/.config/opencode/AGENTS.md"
require(guidance.is_symlink() and guidance.resolve() == (ROOT / "agents/.agents/global-agents.md").resolve(),
        "OpenCode global guidance is not linked to global guidance")
# Claude Code 2.1.277+ reads AGENTS.md natively; a project CLAUDE.md would take precedence over it.
require(not (ROOT / "CLAUDE.md").exists(), "a project CLAUDE.md would stop Claude Code reading AGENTS.md")
# Skills deploy as directory links made at stow time; no tracked per-file link tree.
require(not (ROOT / "claude-code/.claude/skills").exists(), "a tracked Claude skill link tree is back")
require(sorted(d.name for d in (ROOT / "agents/.agents/skills").iterdir()) == ["ship", "spar"], "shared skill set drifted")
for script in ("spar-claude", "spar-opencode"):
    require(os.access(ROOT / "agents/.agents/skills/spar/scripts" / script, os.X_OK), f"spar bridge not executable: {script}")
eyrsync = ROOT / ".claude/skills/eyrsync"
require(eyrsync.is_symlink() and eyrsync.resolve() == (ROOT / ".agents/skills/eyrsync").resolve(),
        "project skill eyrsync is not one directory link into .agents/skills")
for skill_dir in sorted([*(ROOT / "agents/.agents/skills").iterdir(), *(ROOT / ".agents/skills").iterdir()]):
    front = (skill_dir / "SKILL.md").read_text(encoding="utf-8").split("---\n", 2)[1]
    keys = {line.split(":", 1)[0] for line in front.splitlines() if ":" in line and not line.startswith(" ")}
    require(f"name: {skill_dir.name}" in front and "description:" in front, f"skill frontmatter drifted: {skill_dir.name}")
    require(keys <= {"name", "description", "license", "compatibility", "metadata", "allowed-tools"},
            f"skill uses non-standard fields: {skill_dir.name}")
references = {line.split()[0]: line.split()[2] for line in (ROOT / "references.txt").read_text().splitlines()
              if line.strip() and not line.startswith("#")}
require(references == {"claude-code": "github:R_kgDON91aYw", "opencode": "github:R_kgDOOiiGLw"},
        "reference identities differ from the reviewed set")

print(f"ok: {len(COMMANDS)} commands and {len(PROTECTED) + len(PERSONAL) + len(READABLE) + len(TRANSCRIPTS)} paths decide alike in both tools; "
      "sparrers share one charter without edit tools; configuration contracts hold (modeled matching, not live dispatch)")
