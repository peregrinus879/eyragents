# Maintenance Ledger

[Overview](../README.md) · [Operations](operations.md)

Open work only. Each item states what is open, why, and what closes it; when an item closes, any lasting rule moves to its owner and the item is removed.

## WSL Host Pass

Every change since the last WSL deployment is waiting for this pass: the retirement of Codex and Hermes, the persistent-scratch relocation, the lean harness and its permission model, the `sparrer` rename and the standalone mise startup. Run it on the WSL host, stop at the first mismatch, and never inspect credentials or print host configuration values; if a read-only diagnostic is blocked, give H the exact command instead of changing permissions.

1. **EyrWSL first.** Complete sections 1 to 6 of EyrWSL's [WSL host handoff](https://github.com/peregrinus879/eyrwsl/blob/main/docs/handoff.md), which moves persistent scratch to `~/Projects/eyrie/scrape` and retires Codex and Hermes; it owns those steps and checks.
2. **Clone and tools.** After H pulls, check that `uname -r` identifies WSL 2, the worktree is clean, and `make require-clone` passes; preserve any local work for H. Complete [setup](setup.md) on the normal user account and confirm Claude Code is 2.1.277 or newer (`mise ls --current`).
3. **Deploy.** Run `make dry-run`, `make check-skills`, `make restow` and `make verify`, stopping on refusals. Confirm that `~/.agents/skills/{ship,spar}` and `~/.claude/skills/{ship,spar}` are directory links, that `~/.claude/agents` and `~/.agents/agents` hold `sparrer.md` and no `auditor.md`, and that the retired `commit`, `publish` and `develop` skill directories are gone. Delete the retired `~/.agents/hooks/commit-gate` and its emptied directory. Confirm GitHub access, which the EyrWSL handoff completes: `git ls-remote` over HTTPS succeeds without a prompt.
4. **Load.** Restart OpenCode and start fresh sessions. Confirm that both tools load global guidance once, Claude Code reads the project `AGENTS.md` natively, the skills include `ship`, `spar` and the local `eyrsync`, `opencode agent list` shows `sparrer (all)`, and a fresh mise shell supplies `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` and `OPENCODE_ENABLE_EXA=1` without host exports.
5. **Behavior.** Run [permission acceptance](operations.md#permission-acceptance), one live review through each bridge, `bash scripts/update-references.sh --dry-run` (expect identity checks and no writes), and `make canary`. Record client versions, the tested revision and each result.

Closes when every step succeeds, or each remaining limitation is recorded here with its reason.

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
| Remote verification over custom SSH expressions can be unobservable | [ship](../agents/.agents/skills/ship/SKILL.md#publish) | the transport changes |

## Deferred Work

- **Skill behavior evaluations.** `claude plugin eval` scenarios: free text never commits, a commit runs only after its cards and at the native prompt, a push waits for H's go. Closes when evaluation beyond the canary is adopted.
- **Permission prompt review.** Run `/fewer-permission-prompts` on accumulated sessions and promote only durable read-only rules, keeping `gh api` gated.
- **Reproducible test images** for local and hosted checks of exact staged states, if environment-driven CI failures recur; container infrastructure needs its own approval.
- **omasecboot gates.** Give omasecboot a `check` target that runs its tests, once H's current work there is done.

## Revalidation Triggers

- **`/eyrsync`** when a client release changes a configuration key, hook, agent or skill field, permission rule or tool surface; on a major release; when references are missing or stale; or periodically.
- **`make canary`** after a restow or a relevant interface change.
- **One live review per bridge** after a change to a bridge, the sparrer charter or a client CLI.
- **Claude Code skill discovery:** when Claude Code reads `~/.agents/skills` natively, stop linking skills into `~/.claude/skills` after checking `/skills` for duplicates.
- **Restricted launch:** after an OpenCode release, confirm `OPENCODE_DISABLE_PROJECT_CONFIG` and `OPENCODE_DISABLE_EXTERNAL_SKILLS` still exist.
