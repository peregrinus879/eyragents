# Operations

[Overview](../README.md) · [Setup](setup.md) · [Access policy](access.md)

Run repository commands from the EyrAgents root. The client commands below run from the project you want to work on.

## Start And Continue

| Client | Start | Continue |
| --- | --- | --- |
| Claude Code | `claude` | `claude -c` |
| Codex | `codex` | `codex resume --last` |
| OpenCode | `opencode` | `opencode -c` |
| Hermes Agent | `hermes` | `hermes -c` |

Continuation follows each client's native session and working-directory rules. Both host repositories provide `hdw <cc|cx|oc|ha> [-c]` inside an existing Herdr session. Restart a client after deploying its configuration.

For untrusted projects, use the [documented restricted launches](access.md#untrusted-checkouts).

## Model Effort

The configured primary OpenCode model defaults to `xhigh`. In `/variants`, `Default` means use configured request defaults, not medium effort. An explicit named variant overrides that setting. OpenCode remembers choices separately for base Astra and Astra Fast and can skip the follow-up effort dialog when a choice already exists; use `/variants` to inspect it. A missing effort badge is not evidence of a lower request effort. Keep deliberate overrides rather than rewriting saved state or adding duplicate model pins solely for the display.

## Hermes Usage

The default profile uses **Astra (`gpt-6-astra`) through ChatGPT/Codex OAuth at `xhigh`**, with native `coding_context: auto`, local terminal execution, smart command approvals, memory, skill learning, curator and delegation. The harness does not replace Hermes's normal toolset with a coding allowlist. The `ha` selector in both siblings sends `hermes`; `hdw ha -c` sends `hermes -c`. Resume may restore a recorded working directory; use Hermes's `--in` option directly when you need to pin it.

Native memory and agent-created skills may evolve within their owned stores. Shared guidance and repository skills remain authoritative and require ordinary authorized source changes. Background review can use additional model calls; retaining it does not authorize new accounts, recurring jobs, sharing or remote access. Tool availability depends on installed dependencies and provider setup: a model login alone does not configure web search, browser, voice or image-generation services.

Restart Hermes after deployment. `SOUL.md` and project instruction files are subject to Hermes's own loading precedence; the stable shared-guidance hint also reaches native delegated/review agents. Version 0.19 does not discover project `.agents/skills` automatically: load a project-referenced `SKILL.md` through the native file tool. Shared global skills use the configured external library. Safe mode disables plugins, so it is not a managed-policy launch. Additional profiles need an explicit deployment/access review before being treated as EyrAgents-managed.

## Shared Workflows

Use [commit](../agents/.agents/skills/commit/SKILL.md), [publish](../agents/.agents/skills/publish/SKILL.md), and [spar](../agents/.agents/skills/spar/SKILL.md) for their canonical procedures. [eyrsync](../.agents/skills/eyrsync/SKILL.md) owns upstream/reference reconciliation. The [workstream rule](../agents/.agents/shared-guidance.md#workstream-checkpoints) owns local checkpoints and cross-host handoffs.

### Review Briefs

Commits are reviewed one at a time: one compact card with the change, file/hunk scope, full proposed message, checks and short candidate reference, immediately followed by its selector. Review the staged diff for that candidate before approving it. Pushes use one consolidated summary of the fixed ordered set, with destinations/audiences, reviewed commits, effects, checks and binding references, followed by one selector for the set. Grouping push approval preserves the separate commit history and diffs.

Full IDs, hashes, raw argv, execution context and detailed gate/scan evidence are available on request. Short references identify exact immutable records, not latest entries. Material exceptions and required inspections stay visible in the normal brief. Asking for details or copying a command is not approval. The skills own the exact fields and selector behavior, including individual push review when needed.

### Exact-Approved Publication

`publish-bind` prints the reviewed push argv, exact `publish-apply ID` invocation, repository and record-root context. Retain those details and present the compact set summary for H's contemporaneous approval. Preflight all listed bindings before the first attempt, then execute and verify each with separate tool invocations in order. Use its recorded repository context and the same `EYRAGENTS_RECORD_ROOT`; each helper accepts only the full ID. Stop on failure or drift and obtain fresh approval before continuing the unattempted remainder. Native execution authority remains required. Codex prepares review but hands execution and verification to a separately launched Claude Code, OpenCode or Hermes primary, which validates the saved context and obtains fresh set approval. Follow the [publish skill](../agents/.agents/skills/publish/SKILL.md); [access policy](access.md#codex) owns the unchanged protected-file and network restrictions.

The executor makes one noninteractive push attempt, preserves named-remote hooks/tracking and exact-base lease, and suppresses raw Git/hook/transport output. The push budget is 300 seconds. `executing` is written durably before launch; handled completion becomes `attempted` with execution/cleanup evidence. Even an error or timeout can follow a remote update. Observe with `publish-verify ID` rather than replaying or resetting the receipt. Verification is separate: bound endpoint, local tracking, trusted-worktree make/npm targets when defined, and hosted CI are distinct checks. Drift preserves attempted evidence. A surviving `executing` marker stays protected for H, including when endpoint equality is later observed; only eligible records enter the commit skill's deliberate exact-ID close-out.

HTTPS preflight checks Git's effective URL-matched redirect policy with the execution-time `http.followRedirects=false` override. A matching URL-scoped setting that still permits redirects, or an unparseable result, refuses before binding/execution or endpoint observation. Resolve that configuration locally before preparing a new publication; do not follow a redirect to substitute another endpoint.

GitHub normally uses HTTPS with the standard host-local `gh` credential helper. Follow the host repository's setup for login/storage choices and helper settings outside Stow sources. Tools need the normal trusted PATH and host login; restart them after relevant environment changes. Authentication readiness is separate from the exact Push approval, and credential access carries account permissions rather than read-only isolation. Existing SSH destinations retain normal host configuration and inherited `SSH_AUTH_SOCK`; changing transport requires its own review and a fresh binding. The publication helper does not inspect credentials or alter authentication setup. Preserve TLS validation, SSH host trust and the bound endpoint. [Pending host/native evidence](maintenance.md#publication-access) is separate from local fixtures. Clipboard copy remains optional and H-triggered, never approval or proof.

The client's noninteractive options do not control an independent credential provider's UI. A locked store or expired login is an H-local recovery condition, not routine Push authorization. The publication timeout bounds its Git/transport process group, not provider-owned dialogs. Report timeout/unknown outcomes honestly, preserve the binding and never replay a push automatically. A public `ls-remote` result can be anonymous; combine it with API/account and helper checks, while retaining actual approved-push evidence as a separate requirement.

## CI Reruns

Once H has approved the commits and their publication, necessary failed-CI reruns for those exact published repositories/commits are part of the authorized follow-up. The agent follows the [publish skill's CI rerun procedure](../agents/.agents/skills/publish/SKILL.md#ci-reruns): verify run/job ownership and the full SHA, inspect the failure, establish a retryable cause, retry the smallest affected job scope, and verify the new attempt. No additional approval prompt is needed for that same-scope retry.

For paired repositories, a twin job can fetch the earlier peer between sequential pushes. Confirm that both approved tips are now published before rerunning the failed twin job, then inspect the actual pair in the successful log. This does not call for another push or a new workflow dispatch. Repeated unchanged failures return to diagnosis; source fixes and additional deployment effects require their own approval.

OpenCode permits `gh run rerun`; the native wildcard rule enables the command, while the publication procedure supplies the approval/scope checks. Claude's classifier recognizes the same exception. Hermes keeps native review, and Codex's command-network restriction still requires the existing handoff. See [the access comparison](access.md#ci-reruns-after-publication) for these limits.

After deploying this permission change, quit and restart/resume OpenCode. A read-only `gh run rerun --help` checks that the old blanket deny is gone without creating a GitHub run. Exercise the real rerun only when an actual failed job satisfies the approved-publication conditions; do not create or replay work merely for a smoke test. Record pending activation or host evidence in [maintenance](maintenance.md#publication-access).

## OpenCode Read Approvals

After `make restow verify`, quit and restart OpenCode. The read adapter handles eligible **Read and Glob** requests for ordinary configuration, installed software/dependencies, and standing reference roots. It grants only the current request; write/shell prompts and explicit project/agent/session restrictions retain their existing meaning. Credential-bearing files and session stores remain excluded. The [access policy](access.md#read-approval-adapter) explains the boundary.

For post-restart acceptance, read one known non-secret application config and one installed package source file, then perform a filename Glob in the same source directory. Confirm they complete without your approval. In an owned disposable fixture, separately confirm an external native write still asks and leave it unapproved. Verify an explicit read restriction also remains effective. Test both a Git project and the usual non-Git family-directory launch. These are live acceptance checks, not reasons to inspect credentials or existing session history.

Unexpected or overly broad parent patterns stay interactive. Report the tool, non-secret target, and displayed pattern rather than approving an entire home/data tree. `opencode run` can reject outstanding requests before asynchronous adaptation completes; the headless canary's external-temp case remains skipped. The normal interactive workflow is the live acceptance target.

## Verify

After changing managed payloads:

```bash
make lint
make check
```

After stowing, `make verify` runs both and adds deployment checks. GitHub Actions runs `make lint` and `make check` on every push to `main` and every pull request. Restart OpenCode after changing its config or skills because they load at process startup.

CI uses the official `archlinux:base` container with a full signed-package upgrade, matching the Arch userspace of both supported hosts. `ubuntu-latest` supplies only GitHub's VM. Checks run as an unprivileged `ci` user with explicit Bash, a private temporary directory and container process reaping; checkout credentials are not persisted. CI does not perform or attest deployment to Omarchy or WSL.

`make canary` is separate live behavioral smoke testing, not a repository gate or independent permission-dispatch proof. It makes up to six calls per tool: skills, reported gate denial with unchanged HEAD, README read, system read, external temporary fixture read, and fixture-marker non-disclosure. OpenCode reads its own fixture README and the preapproved `/usr/lib/os-release`; only its general external-temp check requires interactive approval and stays explicitly skipped. Each performed assertion requires a successful, nonempty reply. Exit 1 means failure; exit 2 means skipped or unverified checks; exit 0 means all selected behavioral checks passed. Verify remaining prompts interactively rather than bypassing them for green output. A moved/unreadable fixture HEAD stops the probe without resetting it. Mocks and static checks do not establish live behavior.

Consult [`docs/maintenance.md`](maintenance.md) before major tool or plugin changes, permission or bridge changes, cross-host work, `/doctor`, or work on a listed limitation or deferred item.

### Installed Hermes And Live Checks

The offline installed-interface check is `HERMES_PYTHON -I -B tests/hermes-runtime.py`, where `HERMES_PYTHON` means the Python executable under the installed mise Hermes environment, not a shell variable to copy literally. It uses a fake HOME and no model calls, checking both hook helpers and full native dispatch with a backend-call witness. `make canary` uses `hermes --cli chat --source tool --quiet --query` for bounded requests with normal policy, refusing inherited bypass/customization-disable flags or an alternate profile. The source tag keeps automated probes out of ordinary `hermes -c` continuation selection. It never uses v0.19's approval-bypassing `--oneshot`. Grant/block smoke is separate from interactive approval evidence. Top-level delegation always runs in the background in v0.19, even if `background: false` is supplied; use a running interactive session to receive child results rather than treating one completed query as a joined delegation.

Two opt-in checks in `tests/hermes-live.py` are separate from CI/default tests:

- `python3 tests/hermes-live.py approval --hermes /absolute/path/to/installed/hermes` uses the real default profile in an owned PTY and attempts one synthetic external write. A test-only observer records the native approval callback's requested/denied events for that exact target, alongside the displayed prompt and timeout. It changes no callback arguments or decisions, supplies no approval answer, and requires the target to remain absent. Pass the executable inside the installed Hermes venv, not a lazy wrapper; the helper uses its sibling Python interpreter. The session is tagged `tool`.
- `python3 tests/hermes-live.py hdw --hdw /absolute/path/to/sibling/bash/.config/bash/functions/hdw` starts a uniquely named Herdr server with fake HOME/XDG/config and pane PTYs. A recording Hermes stub verifies `hdw ha -c` arguments, the new three-pane workspace and physical cwd without selecting an existing conversation. Real-client resume is checked separately with an explicitly owned session ID.

Both use private, synthetic `/tmp/eyragents-hermes-*` fixtures, close their own CLI/server and remove successful fixtures. Catchable termination signals unwind owned-process cleanup; SIGKILL cannot. A failed fixture is retained with its path for inspection, then removed once its issue is resolved. `tests/hermes-live-fixtures.py` checks narrative-only false positives and interrupted-server cleanup with synthetic subprocesses and PID-bound cleanup handles. Existing Herdr sessions and host configuration are not cleanup targets.
