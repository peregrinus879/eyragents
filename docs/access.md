# Access Policy

[Overview](../README.md) · [Design](design.md)

What each agent may do, how Claude Code and OpenCode enforce it, and where they differ. [Global guidance](../agents/.agents/global-agents.md#safety) states the rules the agents follow; the two configurations implement them; [`tests/config-contracts.py`](../tests/config-contracts.py) holds both configurations to the same decisions; the [maintenance ledger](maintenance.md) holds open gaps.

## Model

The most freedom possible without exposing the owner, with the same outcome in both tools wherever each can express it. An exposure is a secret or personal folder, a remote or third-party effect, or a destructive or hard-to-reverse change. Everything else in the authorized scope runs without a prompt.

| Outcome | Scope |
| --- | --- |
| Allow | Reads anywhere except secrets and personal folders; edits in the project and persistent scratch (`~/Projects/eyrie/scrape`); ordinary commands; web fetch and search. |
| Ask | Remote-changing `gh` subcommands, every `gh api` call and `gh alias` change. Git: every commit-producing command (`commit`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert`, `am`, and the ref and history rewriters), `push`, `clean`, `reset`, `restore`, `checkout --`, `stash drop`/`clear`, branch deletion, configuration writes and remote changes, and history destroyers (`reflog expire`/`delete`, `gc --prune`, `worktree remove`), also behind `git -C`, `-c` and long global options. Package and image publication (`npm`, `pnpm` and `yarn publish`, `cargo publish`, `docker push`, `twine upload`). `ssh`, `scp`, `sftp`. OpenCode also asks for edits outside the project and scratch and for recursive or forced `rm`, which Claude Code's classifier reviews instead. |
| Deny | Secrets and personal folders, for read and edit; edits to `.git/**`, `~/.config/git` and `~/.config/gh`; `sudo`, `su`, `doas`, `pkexec`; all of `gh auth`, and secret and key writes; Remote Control (`claude remote-control`, `--remote-control`, `--rc`); every other agent client (the other tool, Copilot, Gemini, Cursor Agent, Crush), except OpenCode's exact version checks. |

An Ask is the tool's native prompt; the [ship skill](../agents/.agents/skills/ship/SKILL.md) shows the cards before it.

**`gh`.** One verb table covers every top-level group in `gh` 2.101, including options placed before the group (`gh --repo o/r pr merge`); groups that only read or change local `gh` settings stay allowed, and nested groups gate only their writing verbs (`gh repo autolink create`, `gh repo deploy-key add`). Claude Code lists each writing verb as Ask. OpenCode asks for every subcommand of a gated group and then allows its reading verbs, so a verb added in a later `gh` release asks in OpenCode and reaches Claude Code's classifier.

**Families gated whole.** Rules see command text only. Where a family's read and write forms differ only by flags that combine or reorder freely, the whole family is gated, and its reads prompt or are refused. Each has a prompt-free alternative:

| Family | Read instead with |
| --- | --- |
| `gh api` | `gh` subcommands, such as `gh search issues` |
| `git clean -n` | `git status --ignored` |
| `gh auth status` | nothing needed: sign-in is the owner's |
| another agent client's `--version` | `mise ls` |
| a Git configuration read shaped like a write (a dotted key followed by another argument) | the configuration file itself |

`--help` on gated Git commands and `ssh -V`/`-G` prompt too, and a read that passes a gated subcommand word after a global option, such as `git --no-pager log --grep push`, is treated as that subcommand.

### Protected Paths

One inventory, in both configurations:

- **Home stores:** `.ssh`, `.aws`, `.gnupg`, `.kube`, `.password-store`, keyrings, browser and password-manager profiles (Firefox, Chrome, Chromium, Brave, 1Password, Bitwarden), `gh` hosts, Docker configuration, `.netrc`, `.npmrc`, `.pypirc`.
- **Client state:** Claude Code's credentials (`.credentials.json` and copies), sign-in session (`~/.claude.json` and its `backups/`), prompt history and session state; OpenCode's auth and logs; the Codex desktop app's auth, configuration and history.
- **Histories and runtime:** Bash, Zsh, fish, Python, Node, psql and MySQL histories; `/proc/*/environ`; `/var/lib/systemd/coredump`; `/var/crash`.
- **Shapes anywhere:** `.env`, `.env.*`, `secrets/`, `credentials`, `credentials.*`, `auth.json`, `*.key`, `*.pem`, `*.p12`, `*.pfx`, `*.keytab`, private OpenSSH keys (`id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519`) and private `ssh_host_*_key` files, including copies in any directory; recognizable copies of root-only system secrets (`shadow`, `gshadow`, NetworkManager connections, `kcore`), whose originals the OS already protects.
- **Windows through WSL mounts:** browser profiles, 1Password, Bitwarden, Credential Manager, DPAPI keys and GitHub CLI under `AppData`.

Conversation transcripts (Claude Code's `projects/**/*.jsonl`, OpenCode's storage and database, Codex sessions) are readable and never editable; a credential found in one is still a secret. `example.env`, `credentials-policy.md`, public host keys and ordinary configuration stay readable. A finite inventory cannot recognize a renamed secret; global guidance still governs it.

### Personal Folders

`~/Desktop`, `~/Documents`, `~/Downloads`, `~/Music`, `~/Pictures`, `~/Sync` and `~/Videos`, their `/mnt/*/Users/*` counterparts under WSL, and OneDrive are denied for read and edit. OpenCode carries them in its read and edit rules as well as its external-directory rules, because a session launched from a directory above them skips the external-directory check. Claude Code's classifier also prohibits reaching them through the shell. Rules for folders a host lacks have no effect.

### Temporary Directories

Each tool keeps out of the other's session directory: Claude Code denies `/tmp/opencode` and OpenCode denies `/tmp/claude-*`. The rest of `/tmp` is ordinary, and OpenCode writes its own session scratch under `/tmp/opencode`.

## Enforcement Limits

Rules are named forms, not containment. Path rules govern each tool's file tools; an allowed command can still read or write anything the OS permits. Claude Code also applies Read and Edit denies to recognized file commands (`cat`, `head`, `tail`, `sed`, `tee`) and redirection targets, and its classifier reviews the rest; OpenCode checks directories for recognized file commands only. Command rules cover the spellings agents normally produce, including options before a verb, `git -C`, `-c`, long global options and abbreviated Git long options, but an absolute path (`/usr/bin/git push`), a wrapper, an environment prefix or a script escapes any text pattern, as does `git checkout <path>` without `--`. Global guidance forbids such evasion.

| Surface | Claude Code | OpenCode |
| --- | --- | --- |
| Search | On Linux and WSL, `find` and `grep` run inside Bash and meet the rules as Bash calls; the Grep and Glob tools exist only without Bash | Grep returns matching lines without per-file Read checks; Glob lists names |
| Symlinks | Read and Edit rules check the link and its target | Read and Edit check the path as given, not a symlink's target (1.18.32) |
| Deletion | Classifier review | Recursive or forced `rm` asks; other forms (`find -delete`, scripts) run |
| Auto-approval | `bypassPermissions` disabled | `--auto`, or its palette toggle, approves every Ask; keep it off |
| Edits outside the project | Classifier review | `../* = ask`; in a non-Git directory the worktree is `/`, where `../*` never matches |
| Move destinations | Not applicable | Checked only against external-directory rules; see [below](#move-destinations) |
| Nested clients | Other agent clients denied; `claude` runs under the same user rules | `claude`, `opencode` and other agent clients denied, except the two exact version checks |
| Web | Fetch and search available, no domain rules | `webfetch` and `websearch` allowed |
| Sharing | `/feedback`, `/bug`, `/share`, Claude-drafted feedback, the session survey and error reports off; Remote Control denied | `share = "disabled"` |
| Updates | `DISABLE_AUTOUPDATER`; mise owns versions | `autoupdate = false` |

Web access is a deliberate choice: it lets agents check current sources, and it is also an egress path for a prompt-injected session. OpenCode's `webfetch` has no boundary against requests to local or private addresses (source-checked on 1.18.18); secrets and shell network access stay separately restricted. A web read sends queries and URLs to a service; it is not permission to upload or change anything remote. Claude Code's usage metrics stay on: they carry no code, prompts or paths, and turning them off (`DISABLE_TELEMETRY`) also stops the feature flags behind pasted-text marking, the Monitor and PushNotification tools and artifact comments. Auto mode is unaffected, since `defaultMode` sets it.

### The Sparrer

Both tools define a `sparrer` agent from one charter, [`sparrer.md`](../agents/.agents/agents/sparrer.md). It has read, shell and web tools and no edit tools, and its commands pass the primary's rules, so it never exceeds the primary. It cannot launch subagents: it denies `task`, and OpenCode's `subagent_depth` of 1 stops a subagent from delegating further. It is reached through the [spar skill](../agents/.agents/skills/spar/SKILL.md), whose bridges run the other tool's sparrer; `spar-claude` also drops MCP tools and refuses a project that defines its own `sparrer`. The bridges are the only sanctioned launch of another client.

## Untrusted Checkouts

Normal use assumes a trusted repository. For an untrusted checkout, launch without project instructions and configuration:

```bash
claude --safe-mode --setting-sources user
OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode
```

Claude Code's safe mode ignores project instructions, hooks and settings. OpenCode disables project configuration and external skills but has no equivalent untrusted mode or shell sandbox. The bridges start the other client with normal settings, so use the in-tool sparrer in a restricted session. Neither launch makes instructions found in file contents trustworthy.

## Implementation

### Claude Code

[`settings.json`](../claude-code/.claude/settings.json) `permissions` and `autoMode`, and [`sparrer.md`](../claude-code/.claude/agents/sparrer.md). Auto mode is the default, with bypass disabled and no tracked sandbox.

- Precedence is deny, then ask, then allow; an Ask rule prompts even in auto mode, and Ask and deny rules apply to each part of a compound command.
- A trailing ` *` matches the bare command only when it is the rule's only wildcard, so prefixed forms such as `git -C` carry both shapes.
- `Read(//...)` is absolute and `Read(~/...)` home-relative, with gitignore-style globs; `Edit(...)` governs Edit, Write and NotebookEdit.
- `autoMode` keeps the built-in rules and adds prose rules. **Allow:** work in persistent scratch follows repository rules. **Soft deny, needing the owner's instruction naming the file:** deleting files the task did not create; editing shell startup, systemd, autostart or mise configuration; changing the agents' own permissions, hooks, plugins or skills. **Hard deny:** reading or copying secrets even when named, reaching personal folders through the shell, and transmitting credentials. Its `environment` entries describe the owner's source control, public repositories, workstation and sensitive locations.

Official sources: [permissions](https://code.claude.com/docs/en/permissions), [permission modes](https://code.claude.com/docs/en/permission-modes), [auto-mode configuration](https://code.claude.com/docs/en/auto-mode-config), [settings](https://code.claude.com/docs/en/settings).

### OpenCode

[`opencode.json`](../opencode/.config/opencode/opencode.json) `permission` and `agent.sparrer`, and startup flags in [the mise fragment](../opencode/.config/mise/conf.d/eyragents-opencode.toml). OpenCode discovers `~/.agents/skills` natively; `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` drops only the duplicate `.claude` copies, and `skills.paths` names the shared skills so the [untrusted-checkout launch](#untrusted-checkouts), which disables external discovery, keeps them.

- The last matching rule wins, in configuration order, after OpenCode's own `* = allow`. `*` matches any characters, including `/`; a trailing ` *` also matches the bare command; `~/` expands in every pattern.
- Read and edit subjects are paths relative to the worktree; `external_directory` subjects are the absolute parent directory plus `/*`, checked first for anything outside the worktree and skipped for paths under the launch directory.
- Because edit subjects are relative, the scratch grants use location-independent patterns: `../scrape/**` for projects in `~/Projects/eyrie`, `**/eyrie/scrape/**` elsewhere, and `**/tmp/opencode/**`. The deployed Git and `gh` configuration is denied through forms anchored to the home directory (`.config/git/**` from a home worktree, `../**/.config/git/**` from below it, `home/*/.config/git/**` from a root worktree), so a Stow package's tracked copy, such as `git/.config/git/config`, stays editable. From a worktree under `/tmp`, `/tmp/opencode` edits ask, because `**/tmp/opencode/**` cannot match a relative `../opencode/` path; likewise, from a repository inside persistent scratch, edits elsewhere in scratch (such as `../../plans/`) ask, because no location-independent pattern can tell that relative path from one outside scratch.

Checked 1.18.32 source: [permission evaluation](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/permission/index.ts), [Edit](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/edit.ts), [Read](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/read.ts), [external directories](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/external-directory.ts), [launch-directory containment](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/project/instance-context.ts), [skill discovery](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/skill/index.ts). Official interfaces: [permissions](https://opencode.ai/docs/permissions/), [agents](https://opencode.ai/docs/agents/), [configuration precedence](https://opencode.ai/docs/config/#precedence-order).

### Move Destinations

[Apply Patch in 1.18.32](https://github.com/anomalyco/opencode/blob/v1.18.32/packages/opencode/src/tool/apply_patch.ts) submits only source paths to the `edit` check; a `Move to` destination is checked against `external_directory` alone, so an edit deny such as `.git/**` does not bind it. The shell already reaches the same paths, so this adds no reach; a move must never be used to evade a rule.

## Evidence and Refresh

[`tests/config-contracts.py`](../tests/config-contracts.py) models both matchers and requires the same decision in both tools for every listed command and path, including the scratch grants from several project locations and a session launched from a home directory. It checks configuration, not live dispatch. The [canary](operations.md#canary) exercises the real clients; a refusal the model reports is not proof of a native denial. Live [permission acceptance](operations.md#permission-acceptance) passed on Omarchy on 2026-09-25 in both tools (Claude Code 2.1.282, OpenCode 1.18.32), including one `ship` commit and push round each, and the canary passed all 16 checks.

Reconciled on **2026-09-24** against Claude Code 2.1.281 documentation and OpenCode 1.18.32 source; the full-review changes of 2026-09-25 were checked against the then-current Claude Code documentation pages they cite and OpenCode's `instance-context.ts`. Each [`/eyrsync`](../.agents/skills/eyrsync/SKILL.md#access-reconciliation) pass reconciles the policy, both implementations, current official semantics and evidence, and records unresolved drift in the ledger. Never change policy just to make a check pass.
