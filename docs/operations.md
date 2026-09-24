# Operations

[Overview](../README.md) · [Setup](setup.md) · [Access policy](access.md)

Run repository commands from the EyrAgents root. The client commands below run from the project you want to work on.

## Start And Continue

| Client | Start | Continue |
| --- | --- | --- |
| Claude Code | `claude` | `claude -c` |
| OpenCode | `opencode` | `opencode -c` |

Continuation follows each client's native session and working-directory rules. The [offline workspace guide](workspace-guide.html) combines client controls and workflow links with `hdw`, Herdr, editor, shell and host references. Select Omarchy or Arch WSL in the browser. Its [source and maintenance contract](workspace-guide-src/README.md) live here; `make workspace-guide` rebuilds both profiles into one file, and `make check` rejects stale output. Use mise activation or shims for ordinary launches, and `mise exec -- <client>` for non-interactive launchers that need the configured environment. Restart a client after deploying its configuration.

For untrusted projects, use the [documented restricted launches](access.md#untrusted-checkouts).

## Model Effort

The configured primary OpenCode model defaults to `xhigh`. In `/variants`, `Default` means use configured request defaults, not medium effort. An explicit named variant overrides that setting. OpenCode remembers choices separately for base Astra and Astra Fast and can skip the follow-up effort dialog when a choice already exists; use `/variants` to inspect it. A missing effort badge is not evidence of a lower request effort. Keep deliberate overrides rather than rewriting saved state or adding duplicate model pins solely for the display.

## Shared Workflows

Use [develop](../agents/.agents/skills/develop/SKILL.md) for substantive work from goal clarification or resumption through a verified result. Its [workstream contract](../agents/.agents/skills/develop/references/workstream.md) owns compact task memory, pauses, handoffs and automatic cleanup. [commit](../agents/.agents/skills/commit/SKILL.md), [publish](../agents/.agents/skills/publish/SKILL.md) and [spar](../agents/.agents/skills/spar/SKILL.md) own their specialized procedures; [eyrsync](../.agents/skills/eyrsync/SKILL.md) owns harness reconciliation. All projects inherit the global skill; no project-local reference is required.

### OpenCode Workflow Mode

The managed [`/develop` wrapper](../opencode/.config/opencode/commands/develop.md) inherits the current agent; commit, publish and spar wrappers explicitly select Build. OpenCode 1.18.31 [command execution](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/opencode/src/session/prompt.ts#L1356-L1473) uses `cmd.agent ?? input.agent`, and [TUI dispatch](https://github.com/anomalyco/opencode/blob/v1.18.31/packages/tui/src/component/prompt/index.tsx#L1083-L1090) supplies the current agent. These are managed-definition and versioned-source facts, not live mode acceptance. Workflow selection supplies no commit or publication approval.

For native acceptance after restart, select Plan in an owned disposable project, invoke `/develop` with a plan-only task and confirm the selected agent and source/index preservation. Separately invoke it from Build and confirm that agent is retained. Record the observed command/agent dispatch where exposed, rather than inferring it from the answer's wording. An ordinary `opencode run` prompt saying "plan only" tests instruction adherence, not native Plan selection or slash-command dispatch.

### Review Briefs

After verified implementation, [develop's handoff](../agents/.agents/skills/develop/SKILL.md#finish-and-handoff) offers **Prepare commit reviews** or **Pause here** when Git preparation has not already been directed. The first hands the existing map and evidence to commit; the second preserves a minimal concrete resumption. It does not approve a commit or push. Clear existing direction skips the extra question, and read-only/no-change work needs no Git selector.

Commits are reviewed one at a time: one compact card with the change, file/hunk scope, full proposed message, checks and short candidate reference, immediately followed by its selector. Review the staged diff for that candidate before approving it. Pushes use one consolidated summary of the fixed ordered set, with destinations/audiences, reviewed commits, effects, checks and binding references, followed by one selector for the set. Grouping push approval preserves the separate commit history and diffs.

Full IDs, hashes, raw argv, execution context and detailed gate/scan evidence are available on request. Short references identify exact immutable records, not latest entries. Material exceptions and required inspections stay visible in the normal brief. Asking for details or copying a command is not approval. The skills own the exact fields and selector behavior, including individual push review when needed.

### Workstream Close-Out

Develop's workstream contract removes owned scratch and obsolete notes automatically when their last dependency ends. Paused work and pending publication/CI retain only necessary state and evidence. Commit/publication receipts use the commit skill's exact-ID close-out. If H explicitly chooses a local-only finish, `--local-only` validates and retires eligible candidate records without creating a publication binding or making a remote-success claim. The same flag is required to resume interrupted local-only disposal; publication and unsafe/active records are not eligible for that mode.

### Exact-Approved Publication

`publish-bind` prints the reviewed push argv, exact `publish-apply ID` invocation, repository and record-root context. Retain those details and present the compact set summary for H's contemporaneous approval. Preflight all listed bindings before the first attempt, then execute and verify each with separate tool invocations in order. Use its recorded repository context and the same `EYRAGENTS_RECORD_ROOT`; each helper accepts only the full ID. Stop on failure or drift and obtain fresh approval before continuing the unattempted remainder. Native execution authority remains required. Follow the [publish skill](../agents/.agents/skills/publish/SKILL.md).

The executor makes one noninteractive push attempt, preserves named-remote hooks/tracking and exact-base lease, and suppresses raw Git/hook/transport output. The push budget is 300 seconds. `executing` is written durably before launch; handled completion becomes `attempted` with execution/cleanup evidence. Even an error or timeout can follow a remote update. Observe with `publish-verify ID` rather than replaying or resetting the receipt. Verification is separate: bound endpoint, local tracking, trusted-worktree make/npm targets when defined, and hosted CI are distinct checks. Drift preserves attempted evidence. A surviving `executing` marker stays protected for H, including when endpoint equality is later observed; only eligible records enter the commit skill's deliberate exact-ID close-out.

HTTPS preflight checks Git's effective URL-matched redirect policy with the execution-time `http.followRedirects=false` override. A matching URL-scoped setting that still permits redirects, or an unparseable result, refuses before binding/execution or endpoint observation. Resolve that configuration locally before preparing a new publication; do not follow a redirect to substitute another endpoint.

GitHub normally uses HTTPS with the standard host-local `gh` credential helper. Follow [standalone setup](setup.md#github-access) for login/storage choices and helper configuration outside Stow sources. Tools need the normal trusted PATH and host login; restart them after relevant environment changes. Authentication readiness is separate from the exact Push approval, and credential access carries account permissions rather than read-only isolation. Existing SSH destinations retain normal host configuration and inherited `SSH_AUTH_SOCK`; changing transport requires its own review and a fresh binding. The publication helper does not inspect credentials or alter authentication setup. Preserve TLS validation, SSH host trust and the bound endpoint. [Pending host/native evidence](maintenance.md#publication-access) is separate from local fixtures. Clipboard copy remains optional and H-triggered, never approval or proof.

The client's noninteractive options do not control an independent credential provider's UI. A locked store or expired login is an H-local recovery condition, not routine Push authorization. The publication timeout bounds its Git/transport process group, not provider-owned dialogs. Report timeout/unknown outcomes honestly, preserve the binding and never replay a push automatically. A public `ls-remote` result can be anonymous; combine it with API/account and helper checks, while retaining actual approved-push evidence as a separate requirement.

## CI Reruns

Once H has approved the commits and their publication, necessary failed-CI reruns for those exact published repositories/commits are part of the authorized follow-up. The agent follows the [publish skill's CI rerun procedure](../agents/.agents/skills/publish/SKILL.md#ci-reruns): verify run/job ownership and the full SHA, inspect the failure, establish a retryable cause, retry the smallest affected job scope, and verify the new attempt. No additional approval prompt is needed for that same-scope retry.

For paired repositories, a twin job can fetch the earlier peer between sequential pushes. Confirm that both approved tips are now published before rerunning the failed twin job, then inspect the actual pair in the successful log. This does not call for another push or a new workflow dispatch. Repeated unchanged failures return to diagnosis; source fixes and additional deployment effects require their own approval.

OpenCode permits `gh run rerun`; the native wildcard rule enables the command, while the publication procedure supplies the approval/scope checks. Claude's classifier recognizes the same exception. See [the access comparison](access.md#ci-reruns-after-publication) for these limits.

After deploying this permission change, quit and restart/resume OpenCode. A read-only `gh run rerun --help` checks that the old blanket deny is gone without creating a GitHub run. Exercise the real rerun only when an actual failed job satisfies the approved-publication conditions; do not create or replay work merely for a smoke test. Record pending activation or host evidence in [maintenance](maintenance.md#publication-access).

## OpenCode Read Approvals

After `make restow verify`, quit and restart OpenCode. The read adapter handles eligible **Read and Glob** requests for task-relevant system, own-dotfile and Projects material. Its shared `lib/safety-paths.mjs` must deploy with both read/scratch plugins. Each reply covers only the current request; explicit restrictions and unclassified affected mounts retain native handling. Protected files and stores are checked before native access. The [access policy](access.md#read-approval-adapter) owns exact scope and limits.

For post-restart acceptance, read one known non-secret application config and one installed package source file, then perform a filename Glob in the same source directory. Confirm they complete without your approval. In an owned disposable fixture, separately confirm an external native write still asks and leave it unapproved. Verify an explicit read restriction also remains effective. Test both a Git project and the usual non-Git family-directory launch. These are live acceptance checks, not reasons to inspect credentials or existing session history.

Unexpected or overly broad parent patterns stay interactive. Report the tool, non-secret target, and displayed pattern rather than approving an entire home/data tree. `opencode run` can reject outstanding requests before asynchronous adaptation completes; the headless canary's external-temp case remains skipped. The normal interactive workflow is the live acceptance target.

### Persistent Scratch

An implementation request includes in-scope work under `~/Projects/eyrie/scrape`; existing work there remains preserved project data. Use a unique owned child for disposable tests. OpenCode requires supported ownership, canonical-path, mount and target metadata; an absent, linked or unsafe root receives no new automatic grant. Claude uses a scoped Edit allow. [The matrix](access.md#workspace-and-home) distinguishes these controls.

After restarting the affected clients, verify ordinary file creation/update in an owned scratch child, protected-path refusal using synthetic fixtures, and the unchanged behavior of an external target outside scratch, including an `eyrie` sibling outside the active repository. Use Add/Delete for OpenCode scratch moves. Do not repair ownership/links or delete neighboring work merely to obtain a passing probe.

## Verify

After changing managed payloads:

```bash
make lint
make check
```

After stowing, `make verify` runs both and adds deployment checks. GitHub Actions runs `make lint` and `make check` on every push to `main` and every pull request. Restart OpenCode after changing its config or skills because they load at process startup.

CI uses the official `archlinux:base` container with a full signed-package upgrade, matching the Arch userspace of both supported hosts. `ubuntu-latest` supplies only GitHub's VM. Checks run as an unprivileged `ci` user with explicit Bash, a private temporary directory and container process reaping; checkout credentials are not persisted. CI does not perform or attest deployment to Omarchy or WSL.

`make canary` is separate live behavioral smoke testing, not a repository gate or independent permission-dispatch proof. Within six calls per tool, it checks skills, reported gate denial, README read plus ordinary workspace/persistent-scratch writes, system read, external temporary read and fixture-marker non-disclosure. Scratch uses only an exclusive child of the existing safe root, with identity-checked cleanup; root safety and identity checks include the intermediate `~/Projects/eyrie` directory. Drift is retained and reported. Fixture and client-side Git commands use process-local isolated Git configuration, preserving real HOME/client authentication and native permissions. OpenCode's general external-temp check remains interactive-only and skipped. Performed assertions require successful nonempty replies. Exit 1 means failure; 2 means skipped/unverified, including unavailable scratch or uncertain cleanup; 0 means all selected behavioral checks passed. A moved/unreadable fixture HEAD stops the probe without reset. Mocks and static checks do not establish live behavior.

Use `CANARY_TOOLS=claude CANARY_CHECKS=read make canary` for a focused retry of the combined README/workspace/scratch case. `CANARY_CHECKS` accepts unique names from `skills gate read system temp secret`; unset runs all. The output names a selected scope, and invalid selectors refuse before fixture creation. A focused pass covers only its selected cases. Failed README replies are displayed only within the scanner's bounded safe-output check. Each client runs under an owned supervisor; verified termination precedes cleanup, while uncertain child termination preserves both work and scratch fixtures.

Cross-client canaries use the script's standard `/tmp` fixture layout. When the caller's `TMPDIR` names a tool-specific session root, use `env -u TMPDIR CANARY_TOOLS=claude make canary` for fresh shared-temp fixtures. Claude Code protects `/tmp/opencode` as foreign session material; placing their ordinary workspace/temp probes there tests that exclusion instead of normal access.

`make canary-develop` is an opt-in, four-call OpenCode workflow check after deployment, with a 600-second budget per call. It uses the configured model and normal permissions in disposable repositories, checking implicit develop loading, plan-only source/index preservation, default and pre-directed commit handoffs, explicit pause, and cleanup that retains live/user artifacts. Its plan case sends an ordinary `opencode run` prompt; [native Plan and `/develop` acceptance](#opencode-workflow-mode) are separate. It never approves a commit or publication. Raw client events stay in memory; output contains bounded results and content-screened failure diagnostics, as does the ordinary canary for client errors. Failed fixtures remain for diagnosis; prepared fixtures remain for primary receipt inspection and exact-ID close-out. Remove obsolete owned artifacts after those dependencies end. Use `python3 tests/develop-live.py --opencode <installed-binary> --case prepare --timeout 600` for a focused retry. These are bounded behavior observations, not universal dispatch or containment. Run through mise activation or `mise exec -- make canary-develop` so startup defaults apply.

Consult [`docs/maintenance.md`](maintenance.md) before major tool or plugin changes, permission or bridge changes, cross-host work, `/doctor`, or work on a listed limitation or deferred item.

### Claude Compatibility Acceptance

After the 2.1.272 upgrade, use owned non-secret fixtures and the existing controls to check the [changed 2.1.271 interfaces](access.md#claude-code):

- Confirm global guidance and develop/resource discovery in a fresh session using safe native listings and observed skill/resource reads.
- Exercise Bash file operands following unrecognized options, wildcard expansion inside pattern/option values, and declaration-flag handling under an approved synthetic path policy, with an ordinary allowed-read control. Record native permission decisions. The optional external-read fence needs its own authorized fixture if tested; it is not enabled in the managed baseline.
- When reviewer execution is authorized, confirm the read-only auditor can return through the classifier-reviewed hand-back path under auto mode while retaining its guidance and tool caps.
- Switch between explicitly owned fixture conversations and check the resumed conversation's read-before-edit behavior. A successful reread alone does not prove stale tracking was rejected; record a native decision witness where the client exposes one.

Keep unavailable native evidence marked unverified and retain pending checks in the ledger. A model's refusal or assurance is not independent dispatch proof; do not force prohibited calls to manufacture evidence. Inline skill-shell permission handling needs a separate check if a managed skill later adopts it. These checks require no feature adoption, new service or wider permissions.
