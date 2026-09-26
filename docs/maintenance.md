# Maintenance Ledger

[Overview](../README.md) · [Operations](operations.md)

Open work only. Each item states what is open, why, and what closes it; when an item closes, any lasting rule moves to its owner and the item is removed.

## Open Decisions

- **Personal and shareable guidance.** The harness is to become a common harness for other users, but global guidance opens with H's profile and addresses H throughout. Decide how a user supplies their own profile and name without editing the shared files. Closes with H's decision and its implementation.
- **Prompt-audit flags** (2026-09-25). Five low-confidence findings from the Opus 5.5 prompt audit (the root-cause rule, the evidence standard, the sparrer's review areas, AGENTS.md version pins, delegation limits) were kept. Closes when H revisits them after a few sessions on the current harness.
- **Claude Code sandbox.** An untracked Omarchy trial denies `~/.ssh`, `~/.aws` and `~/.gnupg` and asks before `dangerouslyDisableSandbox`. Its localhost-only network default would block research fetches and reference refreshes unless `sandbox.network.allowedDomains` lists each host. Closes when a session of ordinary work with a tracked allowlist shows whether it is worth promoting, and WSL behavior is checked.

## Limitations Under Watch

Each is documented at its owner and rechecked when its trigger fires.

| Limitation | Owner | Recheck when |
| --- | --- | --- |
| OpenCode checks `Move to` destinations only against external-directory rules | [access](access.md#move-destinations) | Apply Patch's permission subjects change |
| OpenCode's worktree-relative subjects, unresolved symlinks, and unchecked shell file commands and grep | [access](access.md#enforcement-limits) | OpenCode's matcher or tool call sites change |
| OpenCode WebFetch has no SSRF boundary (source-checked 1.18.18) | [access](access.md#enforcement-limits) | `tool/webfetch.ts` changes |
| OpenCode subagents cannot launch subagents (`subagent_depth` 1; the sparrer denies `task`) | [access](access.md#the-sparrer) | `tool/task.ts` changes |
| OpenCode's effort badge shows the selection, not the request sent ([#25126](https://github.com/anomalyco/opencode/issues/25126)) | [operations](operations.md#model-effort) | variant persistence or request precedence changes |
| Claude Code's status line cannot show the weekly Fable window, which only the usage API exposes | [status line](../claude-code/.claude/statusline.sh) | a release adds that window to `rate_limits` |
| A renamed file under `~/.claude/agents` may need a new session before it registers (observed 2.1.260) | this ledger | a scoped check on a current release |
| The workspace guide's saved-key export after a browser relaunch intermittently ends Chromium in automated tests (152.0.7977.82, Playwright 1.63.0); a minimal Blob download reproduces it, so no guide-specific cause is established, and interactive browsers are unverified | [guide notes](workspace-guide-src/README.md#saved-keys) | Chromium or Playwright changes, or an upstream fix |
| OpenCode model IDs are pinned by hand | [design](design.md#models-and-effort) | `opencode models` lists a newer generation |
| `opencode agent list` output is cut short when stdout is a pipe: the CLI exits before its buffered output drains, so a piped `grep` lost the last agents on WSL (1.18.32, 2026-09-26) while a file redirect showed all eight; the spar bridge reads the listing from a file | [spar-opencode](../agents/.agents/skills/spar/scripts/spar-opencode) | the CLI's listing or exit path changes |
| Remote verification over custom SSH expressions can be unobservable | [ship](../agents/.agents/skills/ship/SKILL.md#publish) | the transport changes |

## Deferred Work

- **Skill behavior evaluations.** `claude plugin eval` scenarios: free text never commits, a commit runs only after its cards, or H's exact command, and at the native prompt, a push waits for H's go. Closes when evaluation beyond the canary is adopted.
- **Permission prompt review.** Run `/fewer-permission-prompts` on accumulated sessions and promote only durable read-only rules, keeping `gh api` gated.
- **Reproducible test images** for local and hosted checks of exact staged states, if environment-driven CI failures recur; container infrastructure needs its own approval.
- **omasecboot gates.** Give omasecboot a `check` target that runs its tests, once H's current work there is done.

## Revalidation Triggers

- **`/eyrsync`** when a client release changes a configuration key, hook, agent or skill field, permission rule or tool surface; on a major release; when references are missing or stale; or periodically.
- **`make canary`** after a restow or a relevant interface change.
- **One live review per bridge** after a change to a bridge, the sparrer charter or a client CLI.
- **Claude Code skill discovery:** when Claude Code reads `~/.agents/skills` natively, stop linking skills into `~/.claude/skills` after checking `/skills` for duplicates.
- **Restricted launch:** after an OpenCode release, confirm `OPENCODE_DISABLE_PROJECT_CONFIG` and `OPENCODE_DISABLE_EXTERNAL_SKILLS` still exist.
