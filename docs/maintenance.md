# Maintenance Ledger

[Overview](../README.md) · [Operations](operations.md)

Open work only. Each item states what is open, why, and what closes it; when an item closes, any lasting rule moves to its owner and the item is removed.

## Open Decisions

- **Personal and shareable guidance.** The harness is to become a common harness for other users, but global guidance opens with H's profile and addresses H throughout. Decide how a user supplies their own profile and name without editing the shared files. Closes with H's decision and its implementation.
- **Prompt-audit flags.** The evidence standard and AGENTS.md version pins remain open from the prompt audit. Closes when H revisits them after a few sessions on the current harness.
- **Reviewer capabilities.** Native Claude skill invocation may improve discovery, but forked skills can launch another agent; language-server checks need a reviewed server/tool configuration. OpenCode excludes `.claude`-only skills along with duplicate copies. Closes when a concrete review needs one of these capabilities and its tool, data and delegation boundaries are verified, or H declines it. Existing shell, web and scratch checks remain available.

## Host Acceptance

- **Ship continuation on WSL.** After this revision is available on WSL, run `make lint check`, then `make restow verify`, restart both clients and exercise the [ship acceptance scenarios](../tests/ship-behavior.md). Closes with observed continuation to a separate native push prompt, local-only stopping and prompt-decline handling, using owned fixtures or an otherwise authorized delivery.
- **Fable default on WSL.** After this revision is available on WSL, run `make lint check`, then `make restow verify`, and start a fresh Claude Code session. Confirm `/model` selects the configured [Fable family default](design.md#models-and-effort) and `/effort` shows `xhigh`. A resumed session can retain its previous model. Closes with the WSL selection observed; the current Omarchy settings already use the shared source.
- **Spar simplification and shared guidance on WSL.** After this revision is available on WSL, run `make lint check`, then `make restow verify`, restart both clients, and exercise the [spar acceptance scenarios](../tests/spar-behavior.md) through each bridge from a Git workspace and an ordinary folder, including a same-workspace resume. Confirm both clients load the shared [commit-message guidance](../agents/.agents/skills/ship/SKILL.md#commit). Check original-file preservation in Explore/Sparrer, ordinary Build edits and native approval behavior with owned, non-sensitive fixtures. Native Plan is optional; do not enable a plan-file feature merely to satisfy an acceptance check. Closes with observed WSL results and any differences recorded in the access policy.
- **Fault-effect guidance on WSL.** After the [verification clarification](../agents/.agents/global-agents.md#approach) reaches WSL, run `make lint check`, `make restow verify`, restart both clients and repeat the inert fault-effect scenario in [spar acceptance](../tests/spar-behavior.md). Closes with observed handling of the fault's possible effects, keeping the [Omarchy plan-review result's limits](../tests/spar-software-evidence.md#post-restart-inert-plan-review) explicit rather than claiming demonstrated execution containment.

## Limitations Under Watch

Each is documented at its owner and rechecked when its trigger fires.

| Limitation | Owner | Recheck when |
| --- | --- | --- |
| OpenCode checks `Move to` destinations only against external-directory rules | [access](access.md#move-destinations) | Apply Patch's permission subjects change |
| OpenCode's worktree-relative subjects, unresolved symlinks, and unchecked shell file commands and grep | [access](access.md#enforcement-limits) | OpenCode's matcher or tool call sites change |
| OpenCode WebFetch has no SSRF boundary (source-checked 1.18.18) | [access](access.md#enforcement-limits) | `tool/webfetch.ts` changes |
| OpenCode subagents cannot launch subagents (`subagent_depth` 1; the sparrer denies `task`) | [access](access.md#the-sparrer) | `tool/task.ts` changes |
| OpenCode's effort badge shows the selection, not the request sent ([#25126](https://github.com/anomalyco/opencode/issues/25126)) | [operations](operations.md#model-effort) | variant persistence or request precedence changes |
| Claude's native safeguards can switch the selected model; a bridge usage record can name additional models beyond the final reviewer | [operations](operations.md#model-effort) | native fallback behavior or bridge model-identity reporting changes |
| The status line reads its limits from the undocumented usage endpoint behind `/usage`, because `rate_limits` lags it and omits model windows (Fable); it shows every weekly model window, while `/usage` also applies a server-side allowlist it cannot read | [status line](../claude-code/.claude/statusline.sh) | the endpoint's shape changes, `/usage` lists a window the status line does not or the reverse, or `rate_limits` matches `/usage` including model windows (then drop the endpoint call) |
| A renamed file under `~/.claude/agents` may need a new session before it registers (observed 2.1.260) | this ledger | a scoped check on a current release |
| The workspace guide's saved-key export after a browser relaunch intermittently ends Chromium in automated tests (152.0.7977.82, Playwright 1.63.0); a minimal Blob download reproduces it, so no guide-specific cause is established, and interactive browsers are unverified | [guide notes](workspace-guide-src/README.md#saved-keys) | Chromium or Playwright changes, or an upstream fix |
| Claude Code keeps effort per model: a new Claude model starts at its default (Opus 5.5: `medium`) until `/effort xhigh` saves its `modelSettings` entry | [operations](operations.md#model-effort) | a new Claude model ships |
| OpenCode model IDs are pinned by hand | [design](design.md#models-and-effort) | `opencode models` lists a newer generation |
| `opencode agent list` output is cut short when stdout is a pipe, because the CLI exits before its buffered output drains (1.18.32); the spar bridge reads the listing from a file | [spar-opencode](../agents/.agents/skills/spar/scripts/spar-opencode) | the CLI's listing or exit path changes |
| Reviewers running nothing that needs H's approval is an instruction in the charter, not a native block; headless bridge runs reject prompts on their own, so only an in-tool review shows whether a reviewer would prompt | [sparrer charter](../agents/.agents/agents/sparrer.md) | an in-tool review raises a prompt |
| CI runs on `ubuntu-latest`, which GitHub moves to Ubuntu 26 from 2026-10-19 ([runner-images#14748](https://github.com/actions/runner-images/issues/14748)) | [CI workflow](../.github/workflows/test.yml) | the first CI run after the move |
| Remote verification over custom SSH expressions can be unobservable | [ship](../agents/.agents/skills/ship/SKILL.md#publish) | the transport changes |

## Deferred Work

- **Claude Code sandbox adoption.** Blocked by the [observed Git-view incompatibility](access.md#enforcement-limits) in 2.1.283. Keep the H-approved local trial under `~/Projects/eyrie/scrape/spar-acceptance-20260928`, including its disposable `git-workspace`, scoped there: enabled, fail if unavailable, no unsandboxed fallback or sandbox auto-approval. After an approved release update addressing placeholders, first repeat the small inside/outside Git-status comparison: start the client/bridge in `git-workspace` and run `python3 ../sandbox-git-check.py`. That probe asserts the observed fixture inventory; `git -C` from a different sandbox working directory does not exercise the defect. If that passes, complete representative protected-pattern coverage and ordinary-work checks, including actual deployment and a ship round when authorised. On WSL, revalidate bubblewrap/socat and the optional Unix-socket filter, then verify Windows interop cannot escape the intended boundary; package changes need H's exact approval. Closes when evidence supports adoption or another disposition is recorded at the access-policy owner. OpenCode's lack of an equivalent native shell sandbox remains explicit.
- **Skill behavior evaluations.** The [ship scenarios](../tests/ship-behavior.md) extend the canary with requested-commit continuation to a separately approved push, local-only intent, declined prompts, blocked publication and inline-content approval for GitHub posts. Exercise them in fresh native sessions or `claude plugin eval`, recording observed cases and remaining gaps. Closes with recorded behavior beyond the canary; WSL acceptance has its own host item.
- **Unavailable or INCOMPLETE review.** The [directed primary trial](../tests/spar-software-evidence.md#named-astra-follow-up) established named-Astra routing but delivered substantive reviews on every pass. Exercise the remaining [directed case](../tests/spar-behavior.md#primary-orchestration) in a native top-level session. Closes with evidence that a missing or incomplete review is reported without silent reviewer substitution or a clearance claim. WSL routing acceptance remains with the host item.
- **Client patch-release reconciliation.** Omarchy now selects Claude Code 2.1.284 and OpenCode 1.18.33. A focused instruction-loading check did not reconcile their other interfaces; the declared local references lack both installed-release tags. Run `/eyrsync` for relevant changes, including Claude's instruction-link handling, auto-memory processing and Linux sandbox-start fix. Closes with version-matched source/public-documentation and scoped runtime evidence, or specific differences recorded at their owners. Do not assume the sandbox-start fix resolves the separately observed Git-view incompatibility.
- **Permission prompt review.** Run `/fewer-permission-prompts` on accumulated sessions and promote only durable read-only rules, keeping `gh api` gated.
- **Reproducible test images** for local and hosted checks of exact staged states, if environment-driven CI failures recur; container infrastructure needs its own approval.
- **omasecboot gates.** Give omasecboot a `check` target that runs its tests, once H's current work there is done.

## Revalidation Triggers

- **`/eyrsync`** when a client release changes a configuration key, hook, agent or skill field, permission rule or tool surface; on a major release; when references are missing or stale; or periodically.
- **`make canary`** after a restow or a relevant interface change.
- **One live review per bridge** after a change to a bridge, the sparrer charter or a client CLI.
- **Claude Code skill discovery:** when Claude Code reads `~/.agents/skills` natively, stop linking skills into `~/.claude/skills` after checking `/skills` for duplicates.
- **Restricted launch:** after an OpenCode release, confirm `OPENCODE_DISABLE_PROJECT_CONFIG` and `OPENCODE_DISABLE_EXTERNAL_SKILLS` still exist.
