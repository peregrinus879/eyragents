# Design

[AGENTS.md](../AGENTS.md) states the rules; this document gives the reasons, so you can judge whether the same shape fits your own setup.

## Full Capability, Named Exposures

Agents are most useful when they rarely stop to ask. Each restriction here exists to prevent a named exposure: secrets and personal folders are denied; remote, third-party, destructive and hard-to-reverse actions ask at the tool's native prompt. Everything else runs, including reads anywhere else on the machine, because ordinary configuration, package metadata and diagnostics are what an agent needs to do good work. A rule, hook or procedural step that prevents no exposure is removed.

## Enforce, Then Instruct

Rules live at the lowest layer that can hold them. A native permission rule holds regardless of what the model decides; a script makes a procedure repeatable and testable; prose covers what neither can express. Approval sits in each tool's native prompt, which the model cannot answer for you.

Native rules match command text and file paths, so they are not containment: an absolute binary path, a wrapper or a script can reach what a pattern names. Global guidance forbids such evasion, and Claude Code's auto-mode classifier reviews what rules miss. The [access policy](access.md#enforcement-limits) lists these limits per tool.

## One Policy, Two Tools

Both tools carry the same policy, but enforce it to different depths. Claude Code combines rules with a classifier that reviews unlisted actions; OpenCode has only static rules, so it asks in a few places where Claude Code's classifier reviews instead, such as a recursive `rm`. Parity means the same authorized work and the same safety outcome wherever each tool can express it, not identical tables; a stricter boundary is never weakened just to match. A test models both tools' matchers and requires the same decision for every listed command and path, so a rule changed in one tool alone fails the checks.

## Approvals That Reach You

A commit, push or GitHub post needs your explicit choice, made after the agent has shown what it does, or after your own message gives the exact command. Text an agent writes in the same message as a tool call can remain in its hidden reasoning and never reach you, while the tool call itself always does. So `ship` runs each round as one command that carries its full content, commit messages and post bodies inline, and the native prompt is both the card and your one approval. Checks run first; a failure, or a question for you, ends the turn with a report instead of a prompt. Git history is the record; the prompt needs no receipt, token or shell gate beside it.

Authentication belongs to the host: GitHub over HTTPS with the standard `gh` credential helper, managed by you. Holding credentials gives the agent capability, never approval.

## Independent Review

A fresh context lets the sparrer challenge the primary's judgment; another model family can add perspective, not proof. The [spar skill](../agents/.agents/skills/spar/SKILL.md) keeps the acceptance brief and original evidence available without the primary's first-pass advocacy. Later exchange resolves material uncertainty instead of obeying a round count. The primary integrates and checks the reviewer's proposed corrections, while the [charter](../agents/.agents/agents/sparrer.md) keeps investigation independent of authority to edit or issue the work.

The bridges supervise the other client's processes and reject failed or malformed responses. CLEAR, BLOCKED and INCOMPLETE describe a scoped review; a successful bridge exit only establishes delivery of that result. Workspace-bound resume handles prevent accidentally continuing in another folder or tool without a separate session registry. They are routing metadata, not authentication or artifact-version evidence. Review remains discretionary.

## One Neutral Source

Guidance and skills exist once, under `~/.agents`, the home of the Agent Skills format. Each tool reaches them through its native loading: symlinks for global instructions, whole-directory links for skills, and native project `AGENTS.md` reading. Nothing is duplicated per tool, so a change to guidance or a skill reaches both at once, with one exception: Claude Code's agent file needs frontmatter, so it carries a copy of the sparrer charter's body, which the parity test holds equal to the source.

| Component | Source and deployment |
| --- | --- |
| Global guidance and skills | `agents/.agents/`; skill directories linked whole into `~/.agents/skills` and `~/.claude/skills` |
| Claude Code | `claude-code/.claude/`: instruction link, settings, sparrer, status line |
| OpenCode | `opencode/.config/opencode/`: instruction link, configuration, sparrer; a mise fragment for startup defaults |
| This repository's instructions | Root `AGENTS.md` and the `eyrsync` skill, which apply here only |

Client-owned state (sessions, memory, credentials) stays outside the packages.

## Live Deployment

Stow links the packages into place without folding directories, so the tools can still write their own files beside the links. The deployed clone is therefore live: an edit takes effect before it is committed, which is fast to iterate on and the reason work on this repository happens in a watched session. Guards stop a deployment from taking over another clone's links or foreign files, and a change to deployed state records the other host's steps in the ledger until it is done there.

## Evidence

Two upstream references anchor reconciliation: OpenCode's client source, and Claude Code's public release and support repository, which is not its CLI source. Official documentation states the supported interface, release notes show changes, source explains available implementation, and runtime checks show only what was observed; none substitutes for the others, and disagreements stay explicit. Reference clones are pinned to GitHub node IDs, because a redirect or shared history alone does not prove a project's identity. The [eyrsync skill](../.agents/skills/eyrsync/SKILL.md#sources) owns this.

## Files and Lifetimes

A file lives where its lifetime belongs:

| Tier | Where | Lifetime | Holds |
| --- | --- | --- | --- |
| Records | `~/Projects/eyrie/scrape` (persistent scratch) | Survives crashes and reboots | H's scratch projects; task-owned checkpoints in `plans/` when an existing task or native plan is not suitable |
| Session scratch | Claude Code's scratchpad under `/tmp/claude-*`; OpenCode's `/tmp/opencode` | Ends with the session or at reboot | One session's working files, such as test fixtures and logs |
| Script temp | `mktemp` under `/tmp` | Deleted when the script exits | The bridges' request, reply and error files; the canary's fixture repository |

The canary also creates one uniquely named child in persistent scratch, to prove the scratch permission, and removes it.

## Records

Durable decisions live in the repository, persistent open work in the [maintenance ledger](maintenance.md), and provenance in Git history. Global guidance's [Continuity rule](../agents/.agents/global-agents.md#workflow) owns checkpoint creation, updates and retirement. Checkpoints preserve the state needed to resume; transcripts retain the conversation. Native plans can carry that state without a duplicate scratch plan. Native memory is a revisable local cache, never authority.

## Models and Effort

Each tool's configuration owns its model choices. Claude Code's settings name the primary model and the sparrer's frontmatter its reviewer model, both as moving aliases. OpenCode's configuration names its primary and small models by concrete ID, bumped by hand when a newer generation appears. Effort is `xhigh` in each tool's configuration, per model where the tool keys it that way, and can be changed per session. Configured choices remain distinct from [native safeguard fallbacks and observed reviewer identity](operations.md#model-effort).
