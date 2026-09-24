#!/usr/bin/env python3
"""Check the managed tool configurations against the shared guidance.

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


def oc_file(key: str, path: str, agent: dict | None = None, worktree: str = WORKTREE) -> str:
    """Decision for a native read or edit of an absolute path; subjects are worktree-relative."""
    inside = path == worktree or path.startswith(worktree + "/")
    if not inside:
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
    "repo": ["create", "edit", "rename", "fork", "sync", "archive", "delete", "deploy-key"],
    "run": ["rerun", "cancel", "delete"], "workflow": ["run", "enable", "disable"], "label": ["create", "delete"],
    "variable": ["set", "delete"], "cache": ["delete"], "project": ["create", "item-add", "delete"],
    "codespace": ["create", "delete", "ssh", "ports", "cp", "stop"], "discussion": ["create", "comment", "edit"],
    "skill": ["install", "update", "publish"], "agent-task": ["create"], "extension": ["install", "upgrade", "remove"],
}
COMMANDS = {
    "gh api repos/owner/repo": "ask", "gh api -X POST repos/owner/repo/issues": "ask",
    "gh auth token": "deny", "gh auth status": "deny", "gh secret set TOKEN": "deny", "gh ssh-key add key.pub": "deny",
    "git status": "allow", "git log --oneline": "allow", "git diff": "allow", "git fetch": "allow",
    "git clean -fd": "ask", "git -C /x clean -fd": "ask", "git reset --hard HEAD": "ask", "git -C /x reset --hard": "ask",
    "git restore file": "ask", "git checkout -- file": "ask", "git stash drop": "ask", "git branch -D topic": "ask",
    "git config --global user.name x": "ask", "git config core.hooksPath hooks": "ask", "git remote set-url origin u": "ask",
    "ssh host": "ask", "scp a host:b": "ask", "sudo pacman -Syu": "deny", "su": "deny", "pkexec true": "deny",
    "git push": "deny", "git push origin main": "deny", "git -C /x push": "deny",
    "gh copilot": "deny", "gh copilot -p x": "deny", "copilot -p x": "deny", "gemini": "deny", "cursor-agent -p x": "deny",
    "crush run x": "deny", "gh status": "allow", "gh co 12": "allow", "gh config set editor nvim": "allow",
    "ls -la": "allow", "make check": "allow", "pacman -Qi git": "allow",
}
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
require(claude_decision("Bash", "opencode run x") == "deny", "Claude can launch a nested OpenCode client")
for command in ("claude -p x", "opencode run x"):
    require(oc_last(oc_rules(opencode["permission"], "bash"), command) == "deny", f"OpenCode can launch `{command}`")

# --- Paths: secrets and personal folders denied, everything else readable --------------------
PROTECTED = [
    "~/.ssh/id_ed25519", "~/.ssh/config", "~/.aws/credentials", "~/.gnupg/pubring.kbx", "~/.kube/config",
    "~/.password-store/x.gpg", "~/.local/share/keyrings/login.keyring", "~/.mozilla/firefox/p/logins.json",
    "~/.config/google-chrome/Default/Login Data", "~/.config/1Password/x", "~/.config/gh/hosts.yml",
    "~/.docker/config.json", "~/.netrc", "~/.npmrc", "~/.pypirc", "~/.claude/.credentials.json", "~/.codex/auth.json",
    "~/.local/share/opencode/auth.json", "~/.bash_history", "~/.zsh_history", "~/.local/share/fish/fish_history",
    "~/.python_history", "~/.node_repl_history", "~/.psql_history", "~/.mysql_history",
    "~/.claude/projects/p/session.jsonl", "~/.codex/sessions/s.jsonl", "~/.local/share/opencode/storage/s",
    "/proc/1234/environ", "/var/lib/systemd/coredump/core.x.zst", "/var/crash/x",
    "/mnt/c/Users/h/AppData/Local/Google/Chrome/User Data/Default/Login Data",
    "/mnt/c/Users/h/AppData/Roaming/Microsoft/Credentials/x", "/mnt/c/Users/h/.ssh/id_rsa",
    "{w}/.env", "{w}/.env.local", "{w}/config/server.key", "{w}/certs/site.pem", "{w}/id_rsa", "{w}/auth.json",
    "{w}/credentials", "{w}/secrets/token.txt", "{w}/backup/.ssh/id_rsa", "{w}/etc/ssh/ssh_host_ed25519_key",
    "~/Projects/other/.env",
]
PERSONAL = ["~/Desktop/a.txt", "~/Documents/tax.pdf", "~/Downloads/x.zip", "~/Music/a.mp3", "~/Pictures/a.jpg",
            "~/Sync/notes.md", "~/Videos/a.mp4", "/mnt/c/Users/h/Documents/a.docx", "/mnt/c/Users/h/OneDrive/a.xlsx"]
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
for worktree in (WORKTREE, HOME + "/Projects/quarry/opencode", HOME + "/Work/tries/a"):
    require(oc_file("edit", "/tmp/opencode/session/x.md", worktree=worktree) == "allow",
            f"OpenCode cannot write its own temp root from {worktree}")
for path in ("~/Projects/other/app.py", "~/.bashrc"):
    require(claude_decision("Edit", expand(path)) != "allow", f"Claude pre-approves an edit outside scope: {path}")
for path in ("{w}/.git/config", "{w}/.git/hooks/pre-commit", "~/.agents/hooks/commit-gate", "~/.config/git/config"):
    require(claude_decision("Edit", expand(path)) == "deny", f"Claude can edit {path}")
    require(oc_file("edit", expand(path)) == "deny", f"OpenCode can edit {path}")
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
require(claude.get("env", {}).get("CLAUDE_CODE_EFFORT_LEVEL") == "xhigh", "Claude Code effort is not xhigh")
gate = [hook["command"] for entry in claude["hooks"]["PreToolUse"] if entry.get("matcher") == "Bash" for hook in entry["hooks"]]
require(any(command.endswith(".agents/hooks/commit-gate") for command in gate), "Claude does not run the commit gate")

require(opencode["share"] == "disabled" and opencode["autoupdate"] is False, "OpenCode sharing or autoupdate drifted")
primary = opencode["model"].split("/", 1)[1]
require(opencode["provider"]["openai"]["models"][primary]["options"]["reasoningEffort"] == "xhigh",
        "OpenCode primary model is not configured at xhigh")
require(not opencode.get("instructions"), "OpenCode duplicates native guidance")
# Native discovery finds ~/.agents/skills; the explicit path keeps them in the restricted untrusted-checkout launch.
require(opencode.get("skills") == {"paths": ["~/.agents/skills"]}, "OpenCode shared skill path drifted")
plugins = sorted(p.name for p in (ROOT / "opencode/.config/opencode/plugins").iterdir())
require(plugins == ["commit-gate.js"], f"unexpected OpenCode plugins: {plugins}")

# Auditors: the same charter in both tools; no edit tools, shell and web under the primary rules.
charter = (ROOT / "agents/.agents/agents/auditor.md").read_text(encoding="utf-8")
claude_auditor = (ROOT / "claude-code/.claude/agents/auditor.md").read_text(encoding="utf-8")
front, body = claude_auditor.split("---\n", 2)[1:]
fields = dict(line.split(":", 1) for line in front.strip().splitlines())
require(body.strip() == charter.strip(), "Claude auditor body differs from the shared charter")
require({t.strip() for t in fields["tools"].split(",")} == {"Read", "Bash", "WebFetch", "WebSearch"},
        "Claude auditor tools drifted: read, shell and web, never edit")
require(fields.get("effort", "").strip() == "xhigh", "Claude auditor effort is not xhigh")
auditor = opencode["agent"]["auditor"]
# "all" lets spar-opencode run the auditor headless; a subagent would fall back to the build agent.
require(auditor["mode"] == "all" and auditor["prompt"] == "{file:~/.agents/agents/auditor.md}", "OpenCode auditor charter drifted")
for key in ("edit", "task"):
    require(oc_last(oc_rules(opencode["permission"], key, auditor), "*") == "deny", f"OpenCode auditor can use {key}")
for key in ("webfetch", "websearch"):
    require(oc_last(oc_rules(opencode["permission"], key, auditor), "*") == "allow", f"OpenCode auditor lacks {key}")
require(oc_last(oc_rules(opencode["permission"], "bash", auditor), "git log -1") == "allow" and
        oc_last(oc_rules(opencode["permission"], "bash", auditor), "git push") == "deny", "OpenCode auditor shell does not follow the primary rules")
require(oc_file("read", expand("{w}/src/app.py"), auditor) == "allow", "OpenCode auditor cannot read the repository")
require(oc_file("read", expand("~/.ssh/id_rsa"), auditor) == "deny", "OpenCode auditor reads secrets")

# --- Loading and skills ----------------------------------------------------------------------
guidance = ROOT / "opencode/.config/opencode/AGENTS.md"
require(guidance.is_symlink() and guidance.resolve() == (ROOT / "agents/.agents/shared-guidance.md").resolve(),
        "OpenCode global guidance is not linked to shared guidance")
require((ROOT / "CLAUDE.md").read_text().strip() == "@AGENTS.md", "project CLAUDE.md import changed")
for skill, script in (("commit", "commit-candidate"), ("commit", "commit-apply"), ("publish", "publish-bind"),
                      ("publish", "publish-apply"), ("publish", "publish-verify")):
    source = ROOT / "agents/.agents/skills" / skill / "scripts" / script
    link = ROOT / "claude-code/.claude/skills" / skill / "scripts" / script
    require(os.access(source, os.X_OK), f"skill script missing or not executable: {skill}/{script}")
    require(link.is_symlink() and link.resolve() == source.resolve(), f"Claude skill link missing or drifted: {script}")
require(os.access(ROOT / "templates/hooks/commit-gate", os.X_OK), "templates/hooks/commit-gate is not executable")
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

print(f"ok: {len(COMMANDS)} commands and {len(PROTECTED) + len(PERSONAL) + len(READABLE)} paths decide alike in both tools; "
      "auditors share one charter without edit tools; configuration contracts hold (modeled matching, not live dispatch)")
