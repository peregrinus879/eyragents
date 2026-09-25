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

A commit or push needs your explicit choice, made after the agent has shown what it does. Text an agent writes in the same message as a tool call can remain in its hidden reasoning and never reach you, while a reply that ends the turn always does. So `ship` ends a turn with every card of a round, and your reply brings one native prompt that makes the round. Git history is the record; no receipt, token or shell gate stands between the card and the prompt.

Authentication belongs to the host: GitHub over HTTPS with the standard `gh` credential helper, managed by you. Holding credentials gives the agent capability, never approval.

## Independent Review

A second opinion is worth most from a fresh context, and more from a different model family. `spar` is the single entry point for review. Its reviewer, the `sparrer`, is read-only, follows one [charter](../agents/.agents/agents/sparrer.md) in both tools, and has shell and web access under the primary's rules, so it checks claims itself rather than trusting a curated brief. The drafter passes what it ran and checked but withholds its conclusions until the first pass, so the reviewer uses the evidence without inheriting the judgment. Findings that block carry how they fail; the rest are optional suggestions.

The in-tool sparrer is the default. A bridge runs the other tool's sparrer when another model family's view is worth the time; the bridge supervises the reviewer's processes and fails unless the reply ends with the charter's verdict line. Review is never mandatory.

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

## Records

Durable decisions live in the repository, open work in the [maintenance ledger](maintenance.md), and provenance in Git history. Work that spans sessions keeps one live plan file outside the repositories, deleted when the work is done; steps pending on another host live in the ledger's host pass, or in a handoff file where a repository keeps one, as EyrWSL does. Native memory is a revisable local cache, never authority.

## Models and Effort

Each tool's configuration owns its model choices, so a model change edits one file: Claude Code's settings name the primary model and the sparrer's frontmatter its reviewer model, both as moving aliases; OpenCode's configuration names its primary and small models by concrete ID, bumped by hand when a newer generation appears. Claude Code defines no `fallbackModel`: a silent downgrade would override the chosen primary. Effort is set once per tool and can be changed per session.
