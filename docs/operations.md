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
