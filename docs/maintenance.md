# Maintenance Ledger

[Overview](../README.md) · [Operations](operations.md)

Open work only. Each item states what is open, why, and what closes it; when an item closes, any lasting rule moves to its owner and the item is removed.

## Open Decisions

- **Personal and shareable guidance.** The harness is to become a common harness for other users, but global guidance opens with H's profile and addresses H throughout. Decide how a user supplies their own profile and name without editing the shared files. Closes with H's decision and its implementation.
- **Prompt-audit flags.** Five low-confidence findings from the Opus 5.5 prompt audit (the root-cause rule, the evidence standard, the sparrer's review areas, AGENTS.md version pins, delegation limits) were kept. Closes when H revisits them after a few sessions on the current harness.
- **Reviewer capabilities.** Native Claude skill invocation may improve discovery, but forked skills can launch another agent; language-server checks need a reviewed server/tool configuration. OpenCode excludes `.claude`-only skills along with duplicate copies. Closes when a concrete review needs one of these capabilities and its tool, data and delegation boundaries are verified, or H declines it. Existing shell, web and scratch checks remain available.
- **Claude Code sandbox.** The [sandbox](https://code.claude.com/docs/en/sandboxing) merges the `Read` deny rules and has the kernel enforce them for every Bash command and its children; today those rules and the auto-mode classifier judge only the command text. An untracked Omarchy trial denies `~/.ssh`, `~/.aws` and `~/.gnupg` and asks before `dangerouslyDisableSandbox`. WebFetch runs outside the sandbox, and in auto mode a sandboxed command names the hosts it needs for the classifier to review, so no pre-listed `allowedDomains` should be needed; this is from the documentation, unverified live. OpenCode has no shell sandbox, so promotion adds a difference to the [access policy](access.md). Promotion into the shared settings reaches both hosts, so it follows both steps, Omarchy first:
  1. On Omarchy, run a session of ordinary work under the trial, including research, `make refs`, `make restow` and a `ship` round, and record what prompted or failed.
  2. On WSL, where bubblewrap already creates sandboxes, install `socat` from `extra` and restart Claude Code; `/sandbox` should then list only the optional seccomp filter as missing. Without that filter, a sandboxed command can start a Windows program through WSL interop, outside the sandbox. The filter comes only from npm (`@anthropic-ai/sandbox-runtime`), outside EyrWSL's official-repository baseline, so H decides between installing it and accepting the gap.

  Closes with H's decision to promote or drop the sandbox, recorded in the access policy.

## Host Acceptance

- **Permission boundaries on WSL.** After this revision is available on WSL, run `make lint check`, then `make restow verify` and restart both clients. Repeat the [permission acceptance checks](operations.md#permission-acceptance) with owned, non-sensitive fixtures; confirm original-file preservation in read-only roles, ordinary Build edits and the live-control-file approval rule. Do not touch the real privileged script to test a refusal. Closes with observed WSL results and any differences recorded in the access policy.

## Limitations Under Watch

Each is documented at its owner and rechecked when its trigger fires.

| Limitation | Owner | Recheck when |
| --- | --- | --- |
| OpenCode checks `Move to` destinations only against external-directory rules | [access](access.md#move-destinations) | Apply Patch's permission subjects change |
| OpenCode's worktree-relative subjects, unresolved symlinks, and unchecked shell file commands and grep | [access](access.md#enforcement-limits) | OpenCode's matcher or tool call sites change |
| OpenCode WebFetch has no SSRF boundary (source-checked 1.18.18) | [access](access.md#enforcement-limits) | `tool/webfetch.ts` changes |
| OpenCode subagents cannot launch subagents (`subagent_depth` 1; the sparrer denies `task`) | [access](access.md#the-sparrer) | `tool/task.ts` changes |
| OpenCode's effort badge shows the selection, not the request sent ([#25126](https://github.com/anomalyco/opencode/issues/25126)) | [operations](operations.md#model-effort) | variant persistence or request precedence changes |
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

- **Skill behavior evaluations.** `claude plugin eval` scenarios: free text never commits, a commit or GitHub post runs only at the native prompt with its full content inline, and a push only after H asks for one. Closes when evaluation beyond the canary is adopted.
- **Permission prompt review.** Run `/fewer-permission-prompts` on accumulated sessions and promote only durable read-only rules, keeping `gh api` gated.
- **Reproducible test images** for local and hosted checks of exact staged states, if environment-driven CI failures recur; container infrastructure needs its own approval.
- **omasecboot gates.** Give omasecboot a `check` target that runs its tests, once H's current work there is done.

## Revalidation Triggers

- **`/eyrsync`** when a client release changes a configuration key, hook, agent or skill field, permission rule or tool surface; on a major release; when references are missing or stale; or periodically.
- **`make canary`** after a restow or a relevant interface change.
- **One live review per bridge** after a change to a bridge, the sparrer charter or a client CLI.
- **Claude Code skill discovery:** when Claude Code reads `~/.agents/skills` natively, stop linking skills into `~/.claude/skills` after checking `/skills` for duplicates.
- **Restricted launch:** after an OpenCode release, confirm `OPENCODE_DISABLE_PROJECT_CONFIG` and `OPENCODE_DISABLE_EXTERNAL_SKILLS` still exist.
