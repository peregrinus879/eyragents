# Access Policy

The comparison point for Claude Code and OpenCode: what each agent may do, how each tool enforces it, and where the tools differ. [Shared guidance](../agents/.agents/shared-guidance.md#safety) owns authorization, [`AGENTS.md`](../AGENTS.md) owns invariants, the linked configurations implement both, and [`maintenance.md`](maintenance.md) holds open gaps. [`/eyrsync`](../.agents/skills/eyrsync/SKILL.md#access-reconciliation) keeps these views aligned.

## Model

The governing rule is the most freedom possible without exposing H, with the same outcome in both tools wherever each can express it. Exposure means secrets and personal data, remote or third-party effects, and destructive or hard-to-reverse changes. Everything else runs without a prompt.

| Outcome | Scope |
| --- | --- |
| Allow | Reads anywhere except secrets and personal folders; edits in the worktree and persistent scratch (`~/Projects/eyrie/scrape`); ordinary commands, read-only `gh` and Git commands; web fetch and search. |
| Ask | Remote-changing `gh` subcommands and every `gh api` call; `git clean`, `reset`, `restore`, `checkout --`, `stash drop`/`clear`, branch deletion; Git configuration writes (global, system, unset, aliases, hooks path, pager, credential helpers) and remote changes; `ssh`, `scp`, `sftp`. OpenCode also asks before edits outside the worktree and scratch; Claude Code's auto-mode classifier reviews those instead. |
| Deny | Secrets and personal folders (read and edit); edits to `.git/**`, `~/.agents/hooks`, `~/.config/git` and `~/.config/gh`; `sudo`, `su`, `doas`, `pkexec`; `gh auth`, `secret`, `ssh-key`, `gpg-key`; `git push` until publication moves to native prompts; launching another AI agent client (the other tool, Copilot, Gemini, Cursor Agent, Crush). |

An Ask is a native prompt: the agent states what the command does and H selects. The commit gate additionally blocks raw commit-producing Git commands before either tool's shell runs them; the [commit](../agents/.agents/skills/commit/SKILL.md) and [publish](../agents/.agents/skills/publish/SKILL.md) skills own the approved path.

Both tools use one `gh` verb table covering every top-level group in `gh` 2.101; groups that only read or change local `gh` settings stay allowed. Claude Code lists each remote-changing verb as Ask. OpenCode asks for every subcommand of a gated group, then allows its read-only verbs, so a verb added in a later `gh` release asks in OpenCode and reaches Claude Code's classifier. `tests/config-contracts.py` holds both to the same decisions.

### Protected Paths

One inventory serves both primaries:

- **Home stores:** `.ssh`, `.aws`, `.gnupg`, `.kube`, `.password-store`, keyrings, browser and password-manager profiles (Firefox, Chrome, Chromium, Brave, 1Password, Bitwarden), `gh` hosts, Docker config, `.netrc`, `.npmrc`, `.pypirc`.
- **Client state:** Claude Code credentials, history, sessions and transcripts (`.claude/projects/**/*.jsonl`, not its memory files); OpenCode auth, database, storage and logs; the Codex desktop app's auth, config, history and sessions.
- **Histories and runtime:** Bash, Zsh, fish, Python, Node, psql and MySQL histories; `/proc/*/environ`; `/var/lib/systemd/coredump`; `/var/crash`.
- **Shapes anywhere:** `.env`, `.env.*`, `secrets/`, `credentials`, `credentials.*`, `auth.json`, `*.key`, `*.pem`, `*.p12`, `*.pfx`, `*.keytab`, private OpenSSH keys (`id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519`) and private `ssh_host_*_key` files, including copies under any directory.
- **Windows through WSL mounts:** browser profiles, 1Password, Bitwarden, Credential Manager, DPAPI keys and GitHub CLI under `AppData`.

Root-only system secrets such as `/etc/shadow` rely on OS permissions, since the agents run unprivileged. `example.env`, `credentials-policy.md`, public host keys and ordinary configuration stay readable. A finite inventory cannot recognize a renamed secret; shared guidance still governs it.

### Personal Folders

`~/Desktop`, `~/Documents`, `~/Downloads`, `~/Music`, `~/Pictures`, `~/Sync` and `~/Videos`, plus the WSL `/mnt/*/Users/*` counterparts and OneDrive, are denied for read and edit. Rules for folders absent on a host have no effect. Claude Code's classifier also prohibits reaching them through the shell.

### Temporary Directories

Each tool keeps out of the other's session root: Claude Code denies `/tmp/opencode`, OpenCode denies `/tmp/claude-*`. The rest of `/tmp` is ordinary. OpenCode's own session scratch is a child of `/tmp/opencode`.

## Enforcement Limits

Rules are named forms, not containment. Path rules govern each tool's native file tools; an allowed command can still read or write any path the OS permits. Claude Code also applies Read and Edit denies to recognized file commands (`cat`, `head`, `tail`, `sed`, `tee`) and redirection targets, and its classifier reviews the rest; OpenCode checks directories for recognized file commands only. A command rule matches the literal form: `git push` rules miss `git -c x=y push` or `/usr/bin/git push`. Shared guidance binds where rules cannot reach.

| Surface | Claude Code | OpenCode |
| --- | --- | --- |
| Search | Grep and Glob honor Read denies on a best-effort basis | Grep returns matching lines without per-file Read checks; Glob lists names |
| Edits outside scope | Classifier review | `../* = ask`; a non-Git worktree is `/`, where `../*` never matches |
| Move destinations | Not applicable | See [Move Destinations](#move-destinations) |
| Nested clients | `opencode` and other agent clients denied; `claude` runs under the same user rules | `claude`, `opencode` and other agent clients denied, except `--version` for the two tools |
| Web | Available; no tracked domain rules | `webfetch` and `websearch` allowed |
| Sharing | Off by guidance | `share = "disabled"` |

Web reads send queries and URLs to a service; that is not permission to upload or change anything remote.

### Auditors

Both tools carry an `auditor` with the shared reviewer charter [`auditor.md`](../agents/.agents/agents/auditor.md). It has read, search, shell and web tools and no edit tools; the charter keeps it read-only, and its commands pass the primary's rules, so it never exceeds the primary. The [spar skill](../agents/.agents/skills/spar/SKILL.md)'s bridges run the other tool's reviewer: `spar-claude` runs Claude Code with the auditor's tool list and no MCP tools, `spar-opencode` runs OpenCode's `auditor` agent. Bridges are the sanctioned route; direct nested client launches stay denied.

## Untrusted Checkouts

Normal interactive use assumes a trusted repository. For an untrusted checkout, suppress project-provided instructions and configuration using the supported client launch:

```bash
claude --safe-mode --setting-sources user
OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode
```

Claude's safe mode ignores project instructions, hooks, and settings. OpenCode disables project configuration and external skills, but has no equivalent untrusted mode or shell sandbox. The spar bridges launch the other client with normal settings, so a restricted parent does not restrict the reviewer; use the in-tool auditor there. These launches do not make instructions encountered in file contents trustworthy, nor do they remove every client/app surface.

## Implementation And Semantics

### Claude Code

Implementation: [`settings.json`](../claude-code/.claude/settings.json) `permissions`, `autoMode` and the `hooks.PreToolUse` Bash matcher; [`auditor.md`](../claude-code/.claude/agents/auditor.md). The tool runs in auto mode with bypass disabled and no tracked sandbox.

Precedence is deny, then ask, then allow; an Ask rule prompts even in auto mode. A trailing ` *` matches the bare command only when it is the rule's sole wildcard, so `git -C` forms carry both shapes. Ask and deny rules apply to each subcommand of a compound command. `Read(//...)` is absolute, `Read(~/...)` home-relative, with gitignore-style globs; `Edit(path)` governs Edit, Write and NotebookEdit.

`autoMode` keeps the built-in defaults and adds: scratch implementation follows repository rules (allow); deleting files the task did not create, editing startup, systemd or mise configuration, and changing the agents' own permissions, hooks, plugins or skills need H's instruction naming the file (soft deny); reading or copying secrets even when named, reaching personal folders through the shell, and transmitting credentials are prohibited (hard deny). Classifier rules are prose, not native denies.

Official sources: [permissions](https://code.claude.com/docs/en/permissions), [permission modes](https://code.claude.com/docs/en/permission-modes), [auto-mode configuration](https://code.claude.com/docs/en/auto-mode-config), [hooks](https://code.claude.com/docs/en/hooks).

### OpenCode

Implementation: [`opencode.json`](../opencode/.config/opencode/opencode.json) `permission` and `agent.auditor`; the [commit-gate](../opencode/.config/opencode/plugins/commit-gate.js) plugin; startup flags in [the mise fragment](../opencode/.config/mise/conf.d/eyragents-opencode.toml). OpenCode discovers `~/.agents/skills` natively; `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` drops only the `.claude` copies, and `skills.paths` names the shared skills so the [untrusted-checkout launch](#untrusted-checkouts), which disables external discovery, keeps them.

The last matching rule wins, in config order, starting from OpenCode's own `* = allow`. A `*` matches any characters, including `/`, and a trailing ` *` also matches the bare command. `~/` expands in every pattern. Read and edit subjects are paths relative to the worktree; `external_directory` subjects are the absolute parent directory plus `/*`, checked first for anything outside the worktree. Because edit subjects are relative, the scratch grants use location-independent patterns: `../scrape/**` for worktrees in `~/Projects/eyrie`, `**/eyrie/scrape/**` elsewhere, and `**/tmp/opencode/**`. From a worktree under `/tmp`, `/tmp/opencode` edits ask.

Checked 1.18.32 sources: [permission evaluation](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/permission/index.ts), [Edit](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/edit.ts), [Grep](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/grep.ts), [external directories](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/external-directory.ts), [skill discovery](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/skill/index.ts). Official interfaces: [permissions](https://opencode.ai/docs/permissions/), [agents](https://opencode.ai/docs/agents/), [config precedence](https://opencode.ai/docs/config/#precedence-order).

### Move Destinations

[Apply Patch 1.18.32](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/apply_patch.ts) submits only source paths to the `edit` check; a `Move to` destination is checked against `external_directory` alone. An Edit deny such as `.git/**` therefore does not bind a move destination. The shell already reaches the same paths, so this adds no reach, but never use a move to evade a rule.

## Evidence And Refresh

[`tests/config-contracts.py`](../tests/config-contracts.py) models both matchers and requires the same decision in both tools for every listed command and path, the scratch grants from several worktree locations, and both auditors' tools (no edit tools). It checks configuration, not live dispatch. [The canary](../scripts/canary.sh) is behavioral smoke through the real clients; a model-reported refusal is not proof of a native denial. The [eyrsync source table](../.agents/skills/eyrsync/SKILL.md#sources) owns the reference strategy.

Source and configuration reconciled **2026-09-24** against Claude Code 2.1.281 official documentation and OpenCode 1.18.32 source. Every `/eyrsync` pass reconciles decision, implementation, current official semantics and evidence for both tools, and records unresolved drift in the ledger. Do not change policy just to make a check pass.
