# Access Policy

The comparison point for Claude Code, Codex, OpenCode, and Hermes Agent: intended authorization, implemented access, rationale, upstream semantics, and evidence. Read this before reconstructing permissions from individual files. [`AGENTS.md`](../AGENTS.md) owns invariants, [shared guidance](../agents/.agents/shared-guidance.md#safety) owns authorization, the linked configurations implement it, and [`maintenance.md`](maintenance.md) owns unresolved gaps and live revalidation evidence. [`/eyrsync`](../.agents/skills/eyrsync/SKILL.md#access-reconciliation) keeps these views aligned.

## Reading The Matrices

These are **configured baseline capabilities, not permission to use them**. They assume a trusted, non-root Git workspace on Linux/WSL, the tracked configuration loaded, the primary agent in its normal mode, supported filesystem layouts, and no extra grants or overrides beyond the configured persistent-scratch workspace root. Normal OS permissions still apply. The 2026-09-14 Safety baseline and [selected client compatibility recheck](#evidence-and-refresh) are source/fixture/metadata evidence, not deployment or fresh live dispatch; Codex 0.154.0 also has a [startup blocker](maintenance.md#active-limitations), so its cells describe policy rather than working-host acceptance.

| Cell | Meaning |
| --- | --- |
| Allow | The described tool/profile permits this operation without a new permission decision, subject to exceptions below. |
| Auto | Claude Code's permissive auto-mode read default, not an explicit path allow. The first external-read choice can change it. |
| Review | Claude Code's classifier evaluates the action; this is neither automatic permission nor a guaranteed human prompt. |
| Ask | The tool requests native approval for the applicable subject; retained decisions and bypass modes remain tool-specific. |
| Block | A native deny or baseline sandbox restriction applies to the described surface, not necessarily every other tool surface. |
| Guarded | The managed OpenCode or Hermes guard admits supported native scratch edits only after policy, path, metadata and mount checks. |
| Adapt | The managed OpenCode read adapter can answer an eligible native external-directory fallback ask once, after call, path and policy checks. Explicit restrictions and unsupported cases remain native. |
| M | OpenCode's native [move-destination exception](#move-destinations): a destination can miss the edit permission check. |

Read and write remain separate even when equal. Filesystem tables describe Claude Code's native file tools, Codex's sandboxed local filesystem operations, OpenCode's native file tools, and Hermes's guarded local native tools. **Do not apply their cells to arbitrary shell scripts, search results, MCP calls, or client-internal reads.** Credential and protected-path exceptions qualify ordinary-location cells.

### Workspace And Home

External columns are outside the active workspace. A sibling is not a writable workspace merely because it is under `~/Projects`. A path explicitly added as a workspace or resolved through a Stow link needs its effective rules checked again.

| Tool | Access | Workspace | Other `~/Projects` | `~/Projects/eyrie/scrape` | `~/Projects/quarry` | Other Home Paths | `~/.agents/skills` | `~/.agents/hooks` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [Claude Code](#claude-code) | Read | Allow | Allow | Allow | Allow | Allow named config/dotfiles; Auto otherwise | Auto | Auto |
| Claude Code | Write | Allow, except protected | Review | Allow, except protected | Review | Review | Review | Block |
| [Codex](#codex) | Read | Allow | Allow | Allow | Allow | Block, except named grants | Allow | Block |
| Codex | Write | Allow, except protected | Block | Allow as profile workspace, except protected | Block | Block | Block | Block |
| [OpenCode](#opencode) | Read | Allow | Adapt | Allow | Allow | Adapt own dotfiles/directories; Ask otherwise | Allow | Block |
| OpenCode | Write (M) | Allow, except protected | Ask | Guarded | Ask | Ask | Ask | Block |
| [Hermes Agent](#hermes-agent) | Read | Allow | Allow, mount-checked | Allow, mount-checked | Allow, mount-checked | Allow own dotfiles/directories, mount-checked; Ask otherwise | Allow | Block |
| Hermes Agent | Write | Allow, except protected | Ask | Guarded | Ask | Ask | Block through deployed path | Block |

Shared guidance includes task-relevant own-home dotfiles/directories and Projects. Claude Code and Codex use reviewed literal configuration/software scopes; these do not represent every future dotfile. OpenCode and Hermes check lexical and resolved home/XDG paths, protected stores and supported mounts; their managed predicates add no automatic approval for whole-home or `/` search roots. OpenCode additionally preserves its older no-adaptation categories and auditor scope. [Implementation and limits](#read-approval-adapter) qualify these grants.

Codex also reads specifically named harness files, `~/.config/opencode`, `~/.local/bin`, and `~/.local/share/mise`; its [template](../templates/codex/config.toml) is the exact inventory. It has no model-facing read grant on `~/.codex/config.toml`. The client loading its own configuration or authentication is not permission for the agent to display it. All four can execute authorized skill scripts through their ordinary shell controls; a filesystem read grant does not mean a script is harmless or read-only when executed.

Persistent scratch is ordinary preserved project work. Claude Code's explicit Edit allow and Codex's `workspace_roots` entry differ from OpenCode/Hermes metadata-guarded eligibility; none authorizes unrelated changes or disposal by location. Codex applies its `:workspace_roots` metadata/credential policy to scratch as well as the active workspace. Reviewer bridges receive no scratch write grant, and OpenCode's auditor retains its earlier auto-read scope and edit denial.

Quarry contains preserved reference clones. The [eyrsync lifecycle](../.agents/skills/eyrsync/SKILL.md#reference-lifecycle) authorizes task-required refreshes and verified same-project GitHub fetch-URL migrations of existing declared clones. Reviewed repository IDs, agreeing canonical metadata, preservation-first Git operations and input rechecks constrain migration; the helper can reconcile its own manifest URL and origin while retaining explicit push URLs. Different/unverified projects, new clones, source edits, force updates, disposal and publication changes keep their separate decisions. These shell effects do not broaden native file-write cells or Codex's command/network boundary.

### System Directories

| Tool | Access | `/usr` | `/etc` | `/opt` | Ordinary `/sys` | `/var/lib/pacman` | `/var/log` | `/mnt`, `/media` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Claude Code | Read | Allow | Allow | Allow | Allow | Allow | Allow | Auto |
| Claude Code | Write | Review | Review | Review | Review | Review | Review | Review |
| Codex | Read | Allow | Allow | Allow | Allow | Allow | Allow | Block |
| Codex | Write | Block | Block | Block | Block | Block | Block | Block |
| OpenCode | Read | Allow | Adapt | Adapt | Adapt | Allow | Adapt | Ask |
| OpenCode | Write (M) | Ask | Ask | Ask | Ask | Ask | Ask | Ask |
| Hermes Agent | Read | Allow, mount-checked | Allow, mount-checked | Allow, mount-checked | Allow, mount-checked | Allow, mount-checked | Allow, mount-checked | Ask |
| Hermes Agent | Write | Ask, except native protected subtrees | Block | Ask | Ask | Ask | Ask | Ask |

Claude Code and Codex also name `/bin`, `/boot`, `/efi`, `/lib`, `/lib64`, `/sbin`, `/srv` and `/var`. OpenCode/Hermes support broader task-relevant system reads through their checked predicates. Static location grants do not classify user-storage mounts beneath an allowed tree. The managed predicates leave unclassified affected mounts outside automatic approval; existing native allows remain a separate surface.

Codex's `:minimal` additionally supplies platform/runtime access, not a fixed universal file list or a grant on the entire machine. On the checked Linux implementation it includes existing executable/library roots and `/etc`; a sandbox-local `/proc` is also normally mounted. Do not infer that all `/proc`, `/run`, or `/dev` host resources are either readable or absent from the simplified directory table. Native Windows and other sandbox backends need their own verification.

The general-browse exclusions for `/home`, `/root`, `/proc`, `/dev`, `/run` and mounted user storage are authorization boundaries, not blanket OS masks. H-directed non-secret diagnostics and authorized programs' normal runtime interfaces remain distinct. Raw dump payloads and sensitive kernel interfaces are excluded file-tool targets; use scoped diagnostic output, not another tool to read the same prohibited payload. Ordinary sysfs attributes remain useful diagnostic inputs.

### Temporary Directories

These cells describe ordinary non-secret files, not permission to inspect another session's scratch. An explicit `$TMPDIR` or workspace nested inside one of these roots can change Codex's effective specificity; never point it at another tool's root to gain access.

| Tool | Access | General `/tmp` | General `/var/tmp` | `$TMPDIR` | `/tmp/opencode` | `/tmp/claude-1000` |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Code | Read | Allow | Allow | Containing-path rule | Block | Allow |
| Claude Code | Write | Review | Review | Containing-path rule | Block | Review |
| Codex | Read | Allow | Allow | Allow when set | Block | Block |
| Codex | Write | Allow | Block unless also writable temp/workspace | Allow when set | Block | Block |
| OpenCode | Read | Adapt | Adapt | Containing-path rule | Allow | Block |
| OpenCode | Write (M) | Ask | Ask | Containing-path rule | Guarded | Block |
| Hermes Agent | Read | Allow, mount-checked | Allow, mount-checked | Containing-path rule | Block | Block |
| Hermes Agent | Write | Ask outside workspace | Ask outside workspace | Containing-path rule | Block | Block |

Claude Code's Read allow on `/tmp` covers its own UID-specific tool root but does not establish ownership of every session there. OpenCode denies external `/tmp/claude-*/**` and its file preflight also recognizes Claude/Codex temporary-root shapes under `/tmp` and `/var/tmp`. Codex names only `/tmp/claude-1000`, so another UID is not covered by that literal. Codex's `:slash_tmp` and `:tmpdir` are broad write capabilities; guidance restricts disposable execution work to caller-owned session scratch. Persistent Projects scratch has the separate grants above.

### Protected Paths

The finite inventory includes named/copy credential stores, provider auth files, browser/password-manager profiles, keyrings, shell histories, `.env`, `.env.*`, `.netrc`, `.npmrc`, `.pypirc`, `secrets/`, `auth.json`, `credentials`, `credentials.*`, named OpenSSH `id_*` keys, `*.key`, `*.pem`, `*.p12`, `*.pfx`, `*.keytab` and private `ssh_host_*_key` files. Known session/history paths and `.codex/config.toml` are protected, with caller-specific own-store handling. Hermes retains its native learning stores; OpenCode's broader no-adaptation inventory is distinct from hard material denial.

[`tests/safety-paths.json`](../tests/safety-paths.json) supplies the common system/copy corpus, not a deployed policy dependency. Exact files and component-boundary store trees include:

| Category | Protected targets and primary-source rationale |
| --- | --- |
| Password and authentication history | `/etc/shadow`, `/etc/shadow-`, `/etc/gshadow`, `/etc/gshadow-`, `/etc/security/opasswd`, `/etc/security/opasswd.old`: [shadow](https://man.archlinux.org/man/shadow.5.en), [gshadow](https://man.archlinux.org/man/gshadow.5.en), [PAM history](https://man.archlinux.org/man/pam_pwhistory.8.en) and its [`.old` implementation](https://github.com/linux-pam/linux-pam/blob/v1.7.2/modules/pam_pwhistory/opasswd.c). |
| Machine secrets | `/etc/krb5.keytab`, `/etc/ipsec.secrets`, `/var/lib/NetworkManager/secret_key`, `/var/lib/systemd/credential.secret`: [Kerberos](https://web.mit.edu/kerberos/krb5-latest/doc/basic/keytab_def.html), [IPsec](https://man.archlinux.org/man/ipsec.secrets.5.en), [NetworkManager](https://networkmanager.dev/docs/api/latest/NetworkManager.html), [systemd credentials](https://systemd.io/CREDENTIALS/#relevant-paths). |
| Key and credential trees | `/etc/ssl/private`, `/etc/credstore`, `/etc/credstore.encrypted`, their `/usr/lib/credstore` counterparts, `/etc/cryptsetup-keys.d`: [Arch OpenSSL](https://archlinux.org/packages/core/x86_64/openssl/files/), [systemd credentials](https://systemd.io/CREDENTIALS/#relevant-paths), [crypttab](https://man.archlinux.org/man/crypttab.5.en). |
| Network/VPN stores | `/etc/NetworkManager/system-connections`, `/usr/lib/NetworkManager/system-connections`, `/var/lib/iwd`, `/etc/wireguard`, `/etc/openvpn`, `/etc/ipsec.d/private`: [NetworkManager profiles](https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html), [iwd](https://man.archlinux.org/man/iwd.network.5.en), [WireGuard](https://git.zx2c4.com/wireguard-tools/about/src/man/wg-quick.8), [OpenVPN inline secrets](https://github.com/OpenVPN/openvpn/blob/master/doc/man-sections/inline-files.rst). |
| Identity/signing stores | `/etc/samba/private`, `/var/lib/samba/private`, `/etc/pacman.d/gnupg`, `/etc/letsencrypt`: [Arch Samba](https://archlinux.org/packages/extra/x86_64/samba/files/), [upstream layout](https://github.com/samba-team/samba/blob/master/dynconfig/wscript), [Pacman keyring](https://pacman.archlinux.page/pacman-key.8.html), [Certbot storage](https://eff-certbot.readthedocs.io/en/stable/using.html#where-are-my-certificates). |
| Raw memory/crash/kernel interfaces | `/proc/kcore`, `/proc/vmcore`, `/dev/mem`, `/dev/port`, `/var/lib/systemd/coredump`, `/var/crash`, `/sys/kernel/debug`, `/sys/kernel/tracing`: [memory devices](https://man7.org/linux/man-pages/man4/mem.4.html), [kdump](https://docs.kernel.org/admin-guide/kdump/kdump.html#overview), [systemd coredump](https://man.archlinux.org/man/systemd-coredump.8.en), [FHS crash store](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch05s06.html), [debugfs](https://www.kernel.org/doc/html/latest/filesystems/debugfs.html), [tracing](https://docs.kernel.org/6.1/trace/ftrace.html). |

Mixed OpenVPN/Pacman/Certbot stores are deliberately excluded whole. `/etc/ssh/ssh_config`, `ssh_host_*_key.pub`, `/etc/passwd`, `/etc/crypttab`, public package keyrings, ordinary sysfs, `example.env`, `credentials-policy.md` and normal source such as `auth.py` remain positive cases. There is no generic `core*` or `shadow*` ban. Recognizable copies retain component suffixes; arbitrary renamed copies, unknown secret-containing files and every hardlink/outward alias cannot be classified by this finite inventory.

| Tool | Access | Named Home Credential Stores | Credential Shapes In Workspace | Copied Stores Under `~/Projects` | `.npmrc` In Another Projects Repo | Credential Shapes In General Temp/System Trees | Workspace `.git/**` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Claude Code | Read | Block | Block | Block | Block | Block | Allow |
| Claude Code | Write | Block | Block | Block | Block | Block | Block |
| Codex | Read | Block | Block for configured shapes | Block for configured inventory | Allow | No general shape mask | Allow |
| Codex | Write | Block | Block for configured shapes | Block | Block | Follows location grant | Block at baseline |
| OpenCode | Read | Block | Block | Block | Block | Block through native Read | Allow |
| OpenCode | Write (M) | Block | Block | Block | Block | Block through native rules/preflight | Block through rules/preflight |
| Hermes Agent | Read | Block | Block | Block | Block | Block through native file checks | Allow |
| Hermes Agent | Write | Block | Block | Block | Block | Block through native file checks | Block for literal/resolved `.git` paths |

For Codex, deny-glob protection is a bounded pre-command snapshot of existing matches. New system exclusions are literal paths; recognizable copy globs are confined to Projects and effective workspace roots, including persistent scratch. General temp/system trees still lack a global credential-shape mask. The `.npmrc` omission applies outside effective workspace roots, not to `~/.npmrc` or workspace/scratch `**/.npmrc`. These are **enforcement gaps, never authorization to access credentials**. [Codex semantics](#codex) and the [ledger](maintenance.md#active-limitations) qualify OS masking and startup failures.

Additional persistence protection differs. Claude Code denies native edits under `~/.config/git`, with classifier checks for other execution-sensitive writes. Codex inherits workspace `.git`, `.agents`, and `.codex` write protection from `:workspace`, including resolved Git directories, and explicitly makes `.git/config` and `.git/hooks` read-only. OpenCode combines location/edit rules with protected/Git endpoint preflight. Source files in a harness checkout and installed endpoints are not interchangeable permission subjects.

## Tool Calls

Filesystem reads and writes above are only one axis. Tool availability, local execution, network access, and external effects need separate comparison.

| Tool | Native Read | Grep / Glob | Edit / Write / Patch | Shell Read And Write Operations |
| --- | --- | --- | --- | --- |
| Claude Code | Read path rules and mode | Best-effort Read-policy coverage; checks resolved search directory | `Edit(path)` covers Edit, Write, NotebookEdit; matching Read denies also block Edit/Write | Read-only built-ins/narrow allows, otherwise Review; file/redirect checks have version-dependent coverage pending ledger revalidation; arbitrary subprocess I/O is not contained |
| Codex | Local filesystem profile where supported | Local searches run under the sandbox profile | Writable-root/profile checks, protected metadata and approval boundary | Allow inside the sandbox; eligible boundary crossings go to auto-review, not a universal per-command review |
| OpenCode | Protected-target preflight, `read` rules and external-directory check; eligible fallback asks adapted once | Glob root preflight/adapter; grep retains directory checks, **no per-result Read filtering** | Protected/Git endpoint preflight, native `edit`/external checks and guarded scratch grants; destination permission gap (M) remains | `bash.* = allow` with named asks/denies; recognized file commands check directories, not per-file Read/Edit; arbitrary scripts are unconfined |
| Hermes Agent | Managed task-aware path checks plus native guards | Root checks and additive native result-path filtering, after backend traversal | Every parsed native target checked; task-relative operands normalized before dispatch | Native smart review plus terminal commit gate; arbitrary Python/scripts and process stdin remain outside lexical enforcement |

| Tool | Hosted Web Reads | Shell Network Reads / Writes | MCP, Apps, Browser, Plugins | In-Tool Auditor | Sharing / Remote Control |
| --- | --- | --- | --- | --- | --- |
| Claude Code | Available through auto-mode/tool rules; no tracked domain allowlist | No tracked network sandbox; command rules/classifier apply | No blanket disable; loaded components have their own approval/execution surfaces | Read, Grep, Glob only; parent restrictions retained | Off by guidance; no blanket tracked feature disable |
| Codex | `web_search = "live"` | Block; publication hands off to a separately launched network-capable primary | Separate from command sandbox; apps/browser/plugin availability and permissions depend on product and loaded configuration | Not configured; full-authority verification deferred | Off by guidance; no blanket tracked feature disable |
| OpenCode | `webfetch` and `websearch` Allow | No network sandbox; command rules apply | Primary has no blanket unknown-tool/MCP deny; plugins/custom tools can execute code | Read/Glob only; final-parent-policy intersection and earlier auto-read scope retained | `share = "disabled"`; other remote-control surfaces stay off by guidance |
| Hermes Agent | Native web tools retained; provider/dependency setup required | No network sandbox; native command review and managed gate apply | Native capabilities retained; each configured integration has its own authority | Not configured | Off by shared guidance; no connector/service is activated by deployment |

Web reads still send queries/URLs to a service. Network-enabled does not authorize uploads or remote mutations. No host connector inventory or account permissions are inferred here. Model-provider requests, client configuration loading, inherited environment values, hooks, plugins, and browser/app integrations are not all governed by a local filesystem profile. A native path deny does not sanitize an environment variable or every returned tool result.

### Delegation And Clients

| Tool | Ordinary Delegation | Direct Nested CLI Launches | Cross-Vendor Reviewer |
| --- | --- | --- | --- |
| Claude Code | No blanket agent/workflow deny; parent permissions and agent-specific controls apply | No blanket client deny; command rules/classifier apply | Approved `spar-codex` bridge has fixed read-only flags |
| Codex | Parent sandbox/approval controls apply; no configured read-only auditor | No named client deny; runtime, state and network can remain unavailable inside the sandbox | Codex-to-Claude route remains H-run outside the strict profile |
| OpenCode | `task` available; upstream depth 1 prevents delegates launching more delegates by default; auditor additionally denies Task | Named `claude *`, `codex *`, `opencode *` forms denied; exact version checks allowed, not a general process-containment rule | Approved `spar-claude` bridge is separate from direct client launches |
| Hermes Agent | Native delegation retained; dispatched child tools receive the plugin, with Hermes's own child restrictions | No blanket nested-client disable; guidance and terminal controls apply | Shared `spar-claude` bridge for the Astra primary |

Only the named auditor gets its special read-only cap. Do not infer those caps for general/explore agents, workflows, CLI subprocesses, or MCP-provided agents. The [spar skill](../agents/.agents/skills/spar/SKILL.md) owns bridge scope/consent; a bridge invocation is not authorization to launch an unrestricted client. Upstream [Claude subagents](https://code.claude.com/docs/en/sub-agents#permission-modes), [Codex subagents](https://developers.openai.com/codex/agent-configuration/subagents#approvals-and-sandbox-controls), and [OpenCode depth](https://opencode.ai/docs/config/#subagent-depth) define the relevant defaults.

### Consequential Actions

| Tool | Raw Commit-Producing Git | `git push`, `git clean` | Reset / Restore / Path Checkout / Branch Deletion | Git Config / Remotes | Privilege Escalation |
| --- | --- | --- | --- | --- | --- |
| Claude Code | Block by dispatched Bash gate | Block named forms | Review; explicit target instruction required by policy | Review; explicit instruction or bounded Eyrsync reference migration | Block named forms |
| Codex | Block by dispatched local-tool gate | Network block for push; no blanket `git clean` deny | Filesystem boundary where crossed; guidance still required inside it | Protected Git metadata and auto-review where crossed | Rejected by review policy; not a universal command-name deny |
| OpenCode | Block by dispatched Bash gate | Block named forms | Ask named forms | Ask named forms | Block named forms |
| Hermes Agent | Block by dispatched terminal gate | Block named forms | Native smart review plus explicit-instruction guidance | Native guards/review plus explicit-instruction guidance | Block named forms |

The [commit gate](../templates/hooks/commit-gate) also blocks stash mutations, including `drop`/`clear`, despite any underlying Ask/Review rule. Its literal fast-forward-only merge/pull exemptions and stash list/show exceptions do not waive other restrictions. Recognized `gh` mutation denies differ: Claude Code's extra forms go through classifier prose; OpenCode additionally denies `gh api`, auth, repository creation/deletion, workflow dispatch and other listed forms, but permits `gh run rerun`. Codex has no matching command deny inventory; the sandbox, auto-review, gate and guidance are distinct layers.

These are bounded command-form checks, not semantic interception of every script. Claude Code's hook matches `Bash`, OpenCode's plugin matches `bash`, and Codex dispatches its configured `PreToolUse` hook on supported local tools. Hook loading/trust, errors/timeouts, alternate shell tools, and input to an already-running command need their own evidence. The exact-candidate [commit](../agents/.agents/skills/commit/SKILL.md) and [publication](../agents/.agents/skills/publish/SKILL.md) workflows remain mandatory even when a command could technically execute: H approves each staged commit individually, then the fixed ordered publication set in one decision. That approval permits one agent-executed `publish-apply ID` and subsequent verification per listed binding. Each helper rechecks its own scope; a failure/drift stops the set, and the unattempted remainder requires fresh approval. Records do not attest approval or enforce set membership independently of the primary's procedure; H's authorization never licenses evasion of a native denial.

Reference migration follows the same authority/capability distinction. Claude's classifier recognizes the maintained updater's pinned-identity exception; OpenCode's named Git-configuration asks, Hermes's native review and Codex's external-write/network restrictions remain. The helper checks project continuity and preservation, not native permission or H's publication approval. Identity pins are reviewed inputs, not self-issued authority. Tests use local Git and simulated GitHub metadata; they do not establish universal classifier dispatch, hostile-tool containment or concurrent-writer isolation.

The shared commit gate intentionally permits ordinary scripts, including the exact-ID helpers; it is not arbitrary-script containment. Claude Code and OpenCode already admit ordinary helper calls, so publication adds no blanket allow or raw-push exception to their native rules. Hermes keeps its raw-push deny and routes ordinary helpers through its existing gate/native review. `publish-apply` holds the exact-ID lock across drift recheck and bounded direct-argv execution, with a durable pre-spawn marker and no automatic replay. `publish-verify` observes the bound endpoint but can also run trusted-worktree make/npm targets, so authorization must account for those targets. GitHub normally uses HTTPS with the host-local `gh` credential helper; existing SSH destinations use normal host configuration and inherited `SSH_AUTH_SOCK`. Credential access grants the account/key's permissions, not read-only isolation or publication approval. Client flags and process-group timeouts do not control independent provider UI. H owns host-local authentication setup and storage choices, using the standalone setup instructions here; publication approval does not authorize credential-store inspection or helper/transport changes.

### CI Reruns After Publication

H's approval of commits and their publication includes necessary failed-CI reruns for the exact published repository/SHA within the reviewed workflow effects. The [publish skill](../agents/.agents/skills/publish/SKILL.md#ci-reruns) owns the run/job checks, cause review, bounded retry and result verification. This avoids another approval prompt for the same publication follow-up; fixes, new pushes, unrelated runs and additional deployment effects still need their own authority.

| Tool | Native capability | Scope control |
| --- | --- | --- |
| Claude Code | Classifier review; the managed soft-deny rule recognizes the approved-publication exception | Publish procedure and shared guidance; classifier behavior is not an immutable approval check. |
| Codex | Command network remains blocked | Use the existing network-capable handoff; no sandbox override is authorized. |
| OpenCode | `gh run rerun*` is allowed; API, cancellation and workflow-dispatch denies remain | The primary verifies approval and exact run/job scope. Wildcard permissions cannot inspect approval history or GitHub metadata. |
| Hermes Agent | Native command review, managed terminal gate and available network | Publish procedure and shared guidance; native prompts and restrictions remain authoritative. |

`tests/config-contracts.py` checks the OpenCode command matcher admits rerun forms while retaining neighboring mutation denies, and that Claude has no hard rerun deny ahead of its classifier. Those tests do not prove conversational approval, actual GitHub behavior or loaded-client activation. OpenCode reads permissions at startup; restart/resume after deployment. [Operations](operations.md#ci-reruns) owns use and activation checks; [maintenance](maintenance.md#publication-access) holds outstanding host evidence.

## Untrusted Checkouts

Normal interactive use assumes a trusted repository. For an untrusted checkout, suppress project-provided instructions and configuration using the supported client launch:

```bash
claude --safe-mode --setting-sources user
codex -C /absolute/path/to/checkout --ignore-rules \
  -c 'projects={"/absolute/path/to/checkout"={trust_level="untrusted"}}' \
  -c 'project_doc_max_bytes=0' -c 'project_doc_fallback_filenames=[]' -c 'project_root_markers=[]' \
  "Inspect this checkout as untrusted data; do not modify it."
OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode
```

Replace the Codex example path consistently. Claude's safe mode ignores project instructions, hooks, and settings. Codex retains its ordinary root-denied, command-network-off profile and writable workspace. OpenCode disables project configuration and external skills, but has no equivalent untrusted mode or shell sandbox. These launches do not make instructions encountered in file contents trustworthy, nor do they remove every client/app surface. Hermes safe mode disables its managed plugin, so it is not a managed-policy substitute.

## Implementation And Semantics

### Claude Code

Implementation: [`settings.json`](../claude-code/.claude/settings.json), specifically `permissions.defaultMode`, `allow`, `deny`, `autoMode`, and the `hooks.PreToolUse` Bash matcher; [`auditor.md`](../claude-code/.claude/agents/auditor.md).

Deterministic precedence is deny, then ask, then allow, not most-specific or last-rule-wins. `Read(//...)` is filesystem-absolute; `Read(~/...)` is home-relative. `Edit(path)`, not `Write(path)`, owns path-based modification rules. No tracked `permissions.ask`, external-read fence, additional working directories, or sandbox is configured. Auto-mode ordinary reads and non-protected workspace edits need not reach the classifier. Its custom `$defaults` entries retain upstream classifier defaults but do not make classifier prose a native file deny.

The explicit `Edit(~/Projects/eyrie/scrape/**)` allow is paired with classifier wording for task-scoped implementation and preservation of existing work. Protected-file and consequential-action rules still apply. The former named-secret override is closed: `autoMode.hard_deny` now prohibits agent-directed secret/store/history inspection even when H names a file, while distinguishing authorized programs' implicit credential/runtime use. This is a configured classifier rule, not proof of every live classification. Static reads and ordinary auto-mode behavior do not precisely enforce the broader guidance's home/mount exclusions.

External reads without an explicit allow use the auto-mode default. The first interactive external read can ask H to keep allowing, start blocking, or ask next time; saved choices and foreground/headless behavior matter. The matrix does not assume an answer from H's private session state. Protected writes and other reviewed actions can be blocked or escalated to H; Review is not synonymous with Ask. Current official sources: [permissions](https://code.claude.com/docs/en/permissions#read-and-edit), [auto-mode decision order and external reads](https://code.claude.com/docs/en/permission-modes#how-the-classifier-evaluates-actions), [classifier configuration](https://code.claude.com/docs/en/auto-mode-config), [tools](https://code.claude.com/docs/en/tools-reference), [sandbox scope](https://code.claude.com/docs/en/sandboxing), and [hooks](https://code.claude.com/docs/en/hooks).

The scoped **2.1.272** compatibility review uses the [versioned public changelog](https://github.com/anthropics/claude-code/blob/v2.1.272/CHANGELOG.md) and official documentation. Relevant 2.1.271 semantics are:

- Inline skill/slash-command `!` shell commands follow default-mode permission rules in auto mode; a command no rule decides runs as a reviewed tool call. The managed develop skill uses ordinary tool calls rather than inline shell execution. Subagents now return through a dedicated classifier-reviewed hand-back call.
- Bash permission checks were fixed for file operands following unrecognized options, wildcard-expanded files in pattern/option values, and shell declaration flags that could misrepresent a command. Directory-change/subshell fixes for `permissions.blockReadsOutsideWorkingDirectories` apply when that fence is enabled; the tracked baseline leaves it unset. These fixes do not establish arbitrary subprocess coverage.
- `/resume` and `/teleport` stop carrying the previous conversation's file-read tracking; `/reload-skills` counts after `/cd` were also fixed. Resumed work still needs current input reads and discovery checks; a restored conversation is not proof that those occurred.

Official [instruction loading](https://code.claude.com/docs/en/memory#agents-md) still uses `CLAUDE.md` and imports, and [personal skills](https://code.claude.com/docs/en/skills#where-skills-live) use `~/.claude/skills`; the managed compatibility links remain. The optional [`omitClaudeMd`](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields) field skips user/project/local guidance for a subagent; the auditor leaves it unset and retains guidance loading. The 2.1.272 notes name only bug fixes and reliability improvements, so their unspecified implementation delta remains unknown. This is public-material evidence, not proprietary CLI source or fresh dispatch. [Operations](operations.md#claude-compatibility-acceptance) owns targeted acceptance; the ledger holds pending results.

### Codex

Implementation: [`templates/codex/config.toml`](../templates/codex/config.toml), specifically `default_permissions`, `permissions.trusted-workspace`, `approval_policy`, `approvals_reviewer`, `auto_review.policy`, `web_search`, `features`, and `hooks.PreToolUse`. This template is not the credential-bearing host-local config.

The profile extends `:workspace`, denies `:root`, reads `:minimal` plus named system/configuration roots, writes `:workspace_roots`, `:tmpdir` and `:slash_tmp`, and disables command network. `permissions.trusted-workspace.workspace_roots["~/Projects/eyrie/scrape"] = true` adds persistent scratch to the profile's workspace/metadata protections. Policy matching prefers more-specific paths; equal-target precedence is deny, write, read, not TOML order. Runtime roots and `$TMPDIR` can change effective coverage.

**0.154.0 representability and Linux construction limits:**

- General Read/Write globs are rejected by `compile_read_write_glob_path`; only exact paths and a trailing `/**` reduced to a subtree path are supported. Own-home reads therefore use literal grants, not a future-dotfile wildcard or a whole-home allow.
- `:root = deny` builds an empty filesystem with scoped read binds. A separate `/home = deny` is different: later denied-directory masking can hide narrower read-only descendants, because the reopening pass restores writable descendants. The template retains root denial without that home-wide mask.
- Deny globs expand existing files before execution, with `glob_scan_max_depth = 64` and an upstream match cap. Both directory and subtree copy patterns are retained; a bare directory glob alone does not select descendant files from `rg --files`. New copy globs stay under Projects and workspace roots. Root/system/temp-wide scans are not added to work around the known unreadable-directory and `.npmrc` scan failures.
- `append_unreadable_root_args` skips an absent literal deny when its first missing component lies outside writable roots. Under a writable root it can create a placeholder instead. Ordinary Projects/temp launches therefore differ from a system cwd or `$TMPDIR` moved into a system tree; an absent-file rule is not a persistent OS mask against later appearance.
- Literal `/proc` payload denies express policy, but Linux mounts a fresh `/proc` after filesystem masks and supplies a minimal `/dev`. They are not proof of virtual-interface containment. Existing-file masks also retain the descriptor-reuse and redundant-metadata-mask startup defects recorded in the [ledger](maintenance.md#active-limitations).

The checked [profile compiler](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/core/src/config/permissions.rs) and [bubblewrap construction](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/linux-sandbox/src/bwrap.rs) own these distinctions. Keep scoped grants and native restrictions; application patching, broader masks and sandbox bypasses are not configuration remedies.

`on-request` with `auto_review` changes who evaluates eligible approval requests, not what the baseline sandbox permits. The custom reviewer policy allows necessary turn-scoped non-secret reads of directed context and exact-approved local commits. It rejects session grants, external writes, credentials, privilege, destruction, uploads, remote mutations, and bypasses. In 0.154.0, `sandbox_permissions_preserving_denied_reads` downgrades `require_escalated` to default execution when a restricted profile contains denied reads, and `sandbox_override_for_first_attempt` also refuses unsandboxed execution. This profile has such denies, so reviewer approval cannot supply host-side publication. See the [versioned sandbox implementation](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/core/src/tools/sandboxing.rs) and [denied-read predicate](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/protocol/src/permissions.rs). Keep both file and network restrictions. Codex prepares publication review; H opens a separate network-capable primary, which validates the saved context and obtains fresh exact-binding approval under the [publish handoff](../agents/.agents/skills/publish/SKILL.md). No nested-client, broker or permission-override workaround is authorized. The [ledger](maintenance.md#publication-access) owns revalidation.

The reviewer does not review every already-permitted action. Its local text **replaces**, rather than appends to, the configurable upstream reviewer policy; built-in review instructions remain. Rejection of other external writes is stricter than guidance allowing an explicitly named external edit, so authorization alone may not make that operation available here.

Official interfaces: [permission profiles](https://developers.openai.com/codex/permissions), [auto-review](https://developers.openai.com/codex/sandboxing/auto-review), [configuration](https://developers.openai.com/codex/config-file/config-reference), [hooks](https://developers.openai.com/codex/hooks), and [subagents](https://developers.openai.com/codex/agent-configuration/subagents). The earlier [0.153.4 review-policy replacement check](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/core/src/guardian/prompt.rs) remains separate from this pass's 0.154.0 filesystem reconciliation.

### OpenCode

Startup defaults are owned by [the mise fragment](../opencode/.config/mise/conf.d/eyragents-opencode.toml), applied through mise activation, shims or `mise exec`. It preserves explicit caller values and needs no host-dotfiles exports. OpenCode 1.18.31 reads these [runtime flags](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/effect/runtime-flags.ts) before loading plugins, so a plugin that sets them later would not establish the same behavior. The existing external-skill-disable and other permission restrictions remain authoritative.

Implementation: [`opencode.json`](../opencode/.config/opencode/opencode.json), specifically `permission.read`, `edit`, `bash`, `external_directory`, `webfetch`, `websearch`, `agent.auditor`, and `share`; [auditor](../opencode/.config/opencode/plugins/auditor-permissions.js), [read](../opencode/.config/opencode/plugins/read-permissions.js), [scratch](../opencode/.config/opencode/plugins/scratch-permissions.js), and [commit-gate](../opencode/.config/opencode/plugins/commit-gate.js) plugins. Read and scratch both import [`lib/safety-paths.mjs`](../opencode/.config/opencode/lib/safety-paths.mjs), outside the autoloaded plugins directory; deploy that common dependency with them.

The 1.18.31 [instruction loader](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/session/instruction.ts) and [skill loader](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/skill/index.ts) preserve the [managed loading arrangement](../AGENTS.md#loading-and-ownership): native global guidance, project fallback, the narrower Claude-skills switch and explicit `skills.paths`. [Command precedence](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/command/index.ts) keeps a configured wrapper ahead of a same-named skill command; [operations](operations.md#opencode-workflow-mode) owns its agent-mode behavior and separate native acceptance.

Last matching rule wins. Read/edit subjects are relative to the Git worktree; external subjects name a directory or a file's parent plus `/*`. A normal Git worktree is inside the boundary even when the launch directory is a subdirectory. The six explicit preapprovals are `/tmp/opencode/*`, `~/Projects/eyrie/scrape/**`, `~/Projects/quarry/**`, `~/.agents/skills/**`, `/usr/**`, and `/var/lib/pacman/**`, before sensitive/other-session denies. Upstream can also append a tool-output location grant. An external grant covers location, not read-only use.

Grep has no per-result Read checks. In 1.18.31, a file operand becomes a search of its parent directory rather than a single-file filter; scope searches with the documented directory/include operands and retain the protected-material rule.

Native edits outside a non-root Git worktree match `../* = ask`. The scratch plugin inserts a bounded union for real owner-controlled `/tmp/opencode` and `~/Projects/eyrie/scrape`, preserving later restrictions and checking every supported target before native work. Persistent eligibility is independent of `TMPDIR`; neither root acquires disposal authority. Root identity, ownership/mode, existing symlinks, hardlinks, special files and mount classification are checked. Merged config cannot distinguish a project restating the identical shipped `../* = ask`; this provenance limitation remains. Unsupported layouts receive no new grant, which is not a guaranteed block: **non-Git worktree `/` still defeats the native `../*` ask**. Quarry retains its ordinary edit handling.

The shared helper checks finite protected files/trees and known session/XDG stores using lexical and resolved spellings. Read/Glob and native edit/patch hooks veto protected targets before native file work; edit preflight also checks `.git` source/destination paths. Requested-target permission errors, loops and unresolved links refuse. Inventory discovery instead retains literal exclusions and accessible aliases when a protected parent cannot be traversed, allowing unrelated work to proceed. **Outward aliases hidden behind inaccessible store components cannot be completely discovered.** Older no-adaptation categories, including all XDG state, Git configuration and OpenCode data/tool-output locations, are not thereby converted into universal hard material denies.

Mount checks consume only OS metadata. Known local system/home mounts and ordinary sysfs can qualify; unclassified nested/bind/network mounts do not acquire new automatic grants. Stacked mounts and locatable topology ambiguity affect their subtrees, including recursive searches crossing them, rather than unrelated paths. Actual-root ambiguity or malformed/unlocatable metadata retains native handling. These checks neither revoke existing native location allows nor contain arbitrary shell I/O, filesystem races or later hostile plugins.

### Read Approval Adapter

[`read-permissions.js`](../opencode/.config/opencode/plugins/read-permissions.js) handles eligible Read/Glob fallback prompts within the broader standing system/own-dotfile/Projects scope without granting those directories to write or shell tools. Both actual and lexical homes are checked before containing system/temp scope, preserving the exclusion of unrelated non-dot home documents. `/`, whole-home searches, general runtime browsing and unclassified affected mounts receive no automatic approval. Protected content remains prohibited beyond the finite inventory.

The plugin records a native call, validates the exact `permission.asked` identity/operand/parent pattern, checks the requesting message's agent and session policies, and sends only an exact-request `once` reply. It binds the canonical target and rechecks relevant path/search-subtree topology; unrelated overmount changes do not invalidate the call. Explicit global/project/agent/session restrictions remain; the redundant managed `external_directory["*"]` leaf is absent so an explicit restatement stays distinguishable from native fallback. The auditor retains its earlier positive auto-read scope, including the lexical-home distinction, and supplies original-cap provenance valid only while its generated policy objects and content remain intact.

No retained `always` decision or external-directory allow is added by the adapter. It does not answer edit/shell/MCP/content-grep asks. Glob discovers names without per-result Read filtering. Unknown events, broad/unexpected parent patterns, failed lookups and relevant layout changes retain native prompting. Call records are bounded and expire. Policy lookups are cancellable; an already-submitted exact once-reply completes without that cancellation signal, because native Replied is published before the waiting tool is released. The adapter bounds its wait rather than interrupting that completion. Trusted native tools/plugins remain prerequisites, not implementation attestation or atomic filesystem/policy isolation.

The selected source contract was rechecked against OpenCode **1.18.31**: [native requests](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/external-directory.ts), [permission and once-reply semantics](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/permission/index.ts), [call identity and awaited before-tool dispatch](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/session/tools.ts), [fire-and-forget legacy plugin event delivery](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/plugin/index.ts), [event schemas](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/schema/src/v1/permission.ts), and [supplied legacy SDK](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/sdk/js/src/gen/sdk.gen.ts). The adapter still uses the exact request's `once` response through the legacy session-permission endpoint. [Agent inheritance](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/agent/agent.ts) still appends agent rules after parent rules and can append a tool-output allow; the managed auditor's intersection and sentinel retain their purpose. Native read/write location splitting remains absent; [issue #5395](https://github.com/anomalyco/opencode/issues/5395) and [PR #5841](https://github.com/anomalyco/opencode/pull/5841) discuss it. [Operations](operations.md#opencode-read-approvals) owns activation and acceptance; the ledger tracks outstanding live evidence.

### Move Destinations

**M qualifies every OpenCode write row:** [Apply Patch 1.18.31](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/apply_patch.ts) checks a `Move to` destination's external directory but submits only source paths to `edit`. It also reads source content to construct the diff before that Edit ask. The managed preflight now checks protected/Git source and destination spellings before native work, but does not reproduce every destination-specific project/agent/session Edit decision. Those native permission gaps remain.

Moves involving either supported guarded scratch root require separately checked Add/Delete operations. Protected endpoint preflight is not a general repair of upstream destination permissions. Never use a move to evade an approval or deny. The [ledger](maintenance.md#active-limitations) owns revalidation; source and fixture coverage do not certify live dispatch.

`always` accepts tool-proposed session patterns, not necessarily the single file: external approval spans the displayed directory across tool access; native read/edit proposes `*`. Global auto-approval would accept asks, so it is not part of the normal baseline. The primary's permissive tools do not acquire the auditor's read-only restrictions. Official interfaces: [permissions](https://opencode.ai/docs/permissions/), [tools](https://opencode.ai/docs/tools/), [configuration precedence](https://opencode.ai/docs/config/#precedence-order), [agents](https://opencode.ai/docs/agents/), and [plugins](https://opencode.ai/docs/plugins/). Checked 1.18.31 native subjects: [Read](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/read.ts), [Edit](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/edit.ts), [Grep](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/grep.ts), [Glob](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/tool/glob.ts), and the external boundary linked above.

### Hermes Agent

Implementation: [`templates/hermes/config.yaml`](../templates/hermes/config.yaml), the opaque [reconciler](../scripts/reconcile-hermes-config.py), and [`hermes/.hermes/plugins/eyragents`](../hermes/.hermes/plugins/eyragents/__init__.py). Safety source/fixture baseline: mise/PyPI **0.19.0**, 2026-09-14. [Package version](https://pypi.org/project/hermes-agent/0.19.0/), [hooks](https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks), [configuration](https://hermes-agent.nousresearch.com/docs/user-guide/configuration), and [skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills) provide public context; newer online interfaces do not supersede installed-source evidence.

The general-purpose profile keeps native tools and learning. Shared guidance is a stable environment hint, not a replacement for `SOUL.md`; repository-owned skills are external libraries, and `skill_manage` may mutate only its own local skill targets. Hermes-local memory and skills are runtime-owned exceptions to the ordinary repository edit boundary. Native file writes to those locations still follow the file-tool approval path; their native learning tools use their own ownership rules.

The plugin uses `pre_tool_call`, request middleware and a hard-denial execution backstop. Task-relative read/search/patch operands become absolute before v0.19's shared backend can use another task's cwd. Every V4A operation, including both `Move File` endpoints, is checked. `register()` composes both `tools.file_tools.get_read_block_error` and `_search_result_read_block_error`, preserving native refusals and checking original lexical search operands as well as resolved targets. Filtering happens **after backend traversal**, not before content access; native counts/errors can disclose metadata. The model's protected-material rule remains necessary.

`standing_read()` checks broad system/own-dotfile/Projects scope on both home/path spellings, with XDG/application-root protected stores and mount metadata. `persistent_write()` admits only checked `~/Projects/eyrie/scrape` targets, with real owner-controlled parents/root, including the intermediate `eyrie` directory, canonical containment and single-link regular files. Unsupported affected mounts, unsafe scratch layouts and out-of-scope requests retain scoped native approval; protected or unverifiable requested targets block. Stacked mounts remain ambiguous within their subtrees. Inventory discovery tolerates inaccessible declared parents without claiming discovery of hidden outward aliases. The native memory/skill/curator paths are preserved rather than treating Hermes's own learning as foreign history.

Hermes's approval system may retain decisions or bypass asks in YOLO mode; the managed `smart` mode is not YOLO. Upstream native file tools also refuse writes under `/etc`, `/boot` and `/usr/lib/systemd`, and retain configured safe-root restrictions; managed external approval does not override them. Protected paths and terminal gate refusals have an execution backstop against an earlier plugin approval. Later hostile plugins, direct handlers and client configuration can defeat these controls; safe mode or failed plugin import leaves upstream execution unguarded. Verify discovery and start a fresh session after changes.

The local backend is **not a sandbox**. `execute_code` RPC calls to Hermes tools, normal delegated tools and permitted background-review tools reach normal dispatch. Direct Python I/O, subprocesses, shell scripts, native tool-internal subprocesses and bytes delivered to an existing interactive process do not become additional terminal-hook calls. Secret path checks do not sanitize arbitrary tool results or environments. Literal `.git` write denial is not protection for every separately located Git directory. Symlink/metadata races remain. Remote path semantics, alternate Codex app-server execution, and independently configured profiles need separate verification; unsupported remote native-path checks refuse rather than assume local protection.

`~/.hermes/config.yaml` can contain provider/MCP credentials. Primary native policies, reviewer bridges and the payload scanner protect it; the deployment reconciler processes it opaquely and reports structural results. Session stores and other tools' temporary roots remain outside authorized research. These layers preserve shared intent with documented limits, not identical containment across tools.

## Decisions And Parity

Parity means preserving the same authorized work and safety intent where each tool can enforce it, **not broadening the stricter tool until every cell matches**. A technical gap is not an approved exception. Material changes to access, oversight, or useful capabilities require H's decision; this document itself grants nothing.

| Area | Decision And Rationale | Implementation / Current Difference | Status |
| --- | --- | --- | --- |
| Ordinary editing | In-scope implementation in the current repository and persistent Projects scratch; other edits need named authority or an authorized exception | Claude explicit Edit allow, Codex profile workspace root, OpenCode/Hermes guarded scratch; protected and consequential-action rules remain | Shared intent; enforcement differs |
| System/home reads | Task-relevant non-secret system and own-dotfile/Projects context, with protected/runtime/mounted-storage exclusions | Claude/Codex use supported literal scopes; OpenCode/Hermes add checked eligibility. Native/auto behavior can exceed or fall short of authorization | Supported scoped implementation |
| Established OpenCode references | Preapprove `/usr`, Pacman metadata and `~/Projects/quarry` for diagnostics, research and skill dependencies without granting every external location | Named location exceptions alongside skill and scratch roots; neither native grants nor OS ownership are a complete read-only guard | Deliberate tradeoff |
| Quarry maintenance | Task-required refreshes and pinned-ID same-project URL reconciliation for this repository's existing references | Own-manifest preservation-first updater and bounded classifier exception; native command/network restrictions remain | Authorized workflow; enforcement differs |
| Scratch preservation | Persistent work is not disposable by location; execution scratch cleanup follows ownership and dependencies | All four have scoped persistent-scratch capabilities; shared guidance and develop own preservation/cleanup authority | Separate capability and lifecycle |
| Credential material | Never read, write, or expose it; path templates do not authorize real secrets | Native denies aligned by inventory, but Codex scan gaps, Claude indirect subprocesses, and OpenCode search/shell gaps remain | Incomplete enforcement; ledger owns follow-up |
| Git and publication | Protect code-executing metadata and require exact candidate/push review | Native metadata restrictions, lexical gate, receipts, and approval procedure complement one another | Shared intent; no arbitrary-script containment |
| Web and extensions | Keep primary research and H's chosen app/extension capabilities; forbid unauthorized remote effects | Codex command network off while hosted web/apps remain separate; Claude/OpenCode shell network not sandboxed | Deliberate surface differences; actual host inventory unverified |
| Reviewers | Primary convenience changes must not widen reviewer scope or write/network/delegation authority | OpenCode keeps earlier auto-read eligibility and inheritance caps; bridge profiles remain fixed and read-only; Codex auditor remains deferred | Preserved caps, not a primary-policy copy |

The durable rationale is [enforce, then instruct](design.md#enforce-then-instruct). Shared guidance remains binding where native coverage is incomplete. Custom reviewer-policy replacement, hook-surface coverage and unresolved parity choices stay in the ledger rather than being silently weakened to match cells.

## Evidence And Refresh

The [eyrsync source table](../.agents/skills/eyrsync/SKILL.md#sources) owns the four-tool reference strategy: Codex/OpenCode/Hermes client source and Claude Code's public release/support material, plus official docs and scoped runtime evidence for every tool. A maintained clone does not by itself make any matrix cell source-verified or live-verified. Version-specific docs/release disagreements, including Claude's Bash Read-rule reversals, stay explicit in the ledger until checked.

Safety source/configuration reconciliation: **2026-09-14**. The **2026-09-15 scoped compatibility recheck** covers reported Claude Code 2.1.272 and OpenCode 1.18.31, using versioned public material because the local release tags were unavailable. It adds no client execution or deployment evidence and is not a latest-release or full all-tool review. Codex and Hermes retain their 2026-09-14 review depth; earlier live observations keep their dates and versions in the ledger. WSL acceptance remains separate.

| Tool | Version under review | Evidence boundary |
| --- | --- | --- |
| Claude Code | 2.1.272, scoped recheck | Official semantics and public changelog through 2.1.272; 2026-09-14 configuration/schema and modeled contracts retain their 2.1.270 baseline. Proprietary CLI implementation and fresh classifier/hand-back/resume dispatch are not established. |
| Codex | 0.154.0 | Template/schema and versioned compiler/bubblewrap/sandbox source, bounded synthetic path coverage. Known startup/scan/mask defects prevent a working-host acceptance claim. |
| OpenCode | 1.18.31, selected source contracts | 37 selected loading/command/permission/plugin/SDK and supporting source files were byte-identical to 1.18.30. The 2026-09-14 synthetic policy/lifecycle/path/mount fixtures and gu605c metadata checks retain their original baseline: ordinary system, own-dotfile and sysfs eligibility, and both scratch roots' rule generation/prospective-write preflight with targets absent. Neither those checks nor the source recheck used a live permission reply. |
| Hermes Agent | 0.19.0, mise/PyPI | Installed public package interfaces, managed guard source and synthetic fixtures covering normalization, protected paths, mounts, scratch and preserved native learning. Fresh live-client dispatch and host activation remain separate. |

The [OpenCode 1.18.31 release](https://github.com/anomalyco/opencode/releases/tag/v1.18.31) changes ACP session model/effort/mode restoration, remote-config authentication failure reporting and provider support. ACP restoration is a separate transport contract, not proof of TUI resume or slash-command mode acceptance. The reported uv 0.12.14 update affects the future Hermes installer workflow; its [revalidation trigger](maintenance.md#revalidation-triggers) leaves the unchanged Hermes runtime baseline intact. Node 25.8.0 was reported unchanged.

[`tests/config-contracts.py`](../tests/config-contracts.py) and the [shared corpus](../tests/safety-paths.json) check configured inventory and modeled paths. OpenCode [read](../tests/opencode-read.sh), [scratch](../tests/opencode-scratch.sh) and [auditor](../tests/opencode-auditor.sh) fixtures cover the real managed transforms/hooks; Hermes [policy fixtures](../tests/hermes.py) and the [installed-interface fixture](../tests/hermes-runtime.py) separate modeled checks from installed dispatch. [Gate](../tests/commit-gate.sh) and [governance](../tests/commit-governance.py) tests own their command/receipt boundaries. Passing fixtures is not proof of universal runtime enforcement. [The canary](../scripts/canary.sh) is separate behavioral smoke; a model-reported refusal is not independent denial evidence.

For actual effective access, account for configuration precedence, launch mode, workspace roots, `$TMPDIR`, session approvals, tool/plugin inventory, hook trust and host backend. Trusted project and CLI/session settings can change defaults; Codex legacy sandbox settings can select a different permission system. Use safe metadata and synthetic non-secret fixtures, not raw host configuration dumps, credentials, environment dumps, or other-tool session records. An unavailable check stays unknown.

Every relevant `/eyrsync` pass reconciles **decision -> matrix -> implementation -> current official semantics -> verification evidence** for all four tools, with read and write kept distinct. Check release notes for changed matchers, defaults, scopes and newly exposed surfaces, not merely renamed keys. Update the current rows/source baseline only to the extent checked; keep per-tool older dates or explicit unknowns when a check is blocked. Preserve unresolved drift with an owner and concrete revalidation trigger in the ledger. Do not change policy just to make a matrix cell or canary green.
