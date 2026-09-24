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

The configured primary OpenCode model defaults to `xhigh`. In `/variants`, `Default` means use configured request defaults, not medium effort. An explicit named variant overrides that setting. OpenCode remembers choices separately for the base model and its Fast variant and can skip the follow-up effort dialog when a choice already exists; use `/variants` to inspect it. A missing effort badge is not evidence of a lower request effort. Keep deliberate overrides rather than rewriting saved state or adding duplicate model pins solely for the display.

## Shared Workflows

[ship](../agents/.agents/skills/ship/SKILL.md) commits and publishes: every card of a round comes first in the chat, then H approves each commit at the native prompt; publication waits for H's go, then each `git push` prompts too. [spar](../agents/.agents/skills/spar/SKILL.md) owns independent review and [eyrsync](../.agents/skills/eyrsync/SKILL.md) harness reconciliation. Work that spans several steps or sessions keeps one live plan file in `~/Projects/eyrie/scrape/plans/`, as global guidance's Continuity rule describes. All projects inherit the global skills; OpenCode also offers each skill as a slash command, such as `/ship`.

GitHub uses HTTPS with the host-local `gh` credential helper; follow [standalone setup](setup.md#github-access). Authentication supplies capability, not approval.

## CI Reruns

Failed CI after a push follows the [ship skill](../agents/.agents/skills/ship/SKILL.md#publish): read the failed job's logs, establish a retryable cause, and retry the smallest affected job scope. `gh run rerun` asks in both tools; state the run, job and cause, and H approves at the prompt.

For paired repositories, a twin job can fetch the earlier peer between sequential pushes. Confirm that both approved tips are now published before rerunning the failed twin job, then inspect the actual pair in the successful log. This does not call for another push or a new workflow dispatch. Repeated unchanged failures return to diagnosis; source fixes and additional deployment effects require their own approval.

## Permission Acceptance

OpenCode loads permissions at startup; after `make restow verify`, restart it before claiming a change is live. With owned, non-secret fixtures, confirm in each tool that a read outside the workspace (a system file, a dotfile) completes without a prompt, that a synthetic `.env` read is refused, and that a remote-changing command such as `gh issue comment` or a destructive one such as `git reset --hard` raises a native prompt, which you decline. In OpenCode, an edit outside the worktree and scratch also asks. [The access policy](access.md) owns the expected outcome for each case.

### Persistent Scratch

An implementation request includes in-scope work under `~/Projects/eyrie/scrape`; existing work there remains preserved project data. Use a unique owned child for disposable tests.

## Verify

After changing managed payloads:

```bash
make lint
make check
```

After stowing, `make verify` runs both and adds deployment checks. GitHub Actions runs `make lint` and `make check` on every push to `main` and every pull request. Restart OpenCode after changing its config or skills because they load at process startup.

CI uses the official `archlinux:base` container with a full signed-package upgrade, matching the Arch userspace of both supported hosts. `ubuntu-latest` supplies only GitHub's VM. Checks run as an unprivileged `ci` user with explicit Bash, a private temporary directory and container process reaping; checkout credentials are not persisted. CI does not perform or attest deployment to Omarchy or WSL.

`make canary` is separate live behavioral smoke testing, not a repository gate or independent permission-dispatch proof. Within six calls per tool, it checks skills, a commit stopped at the native prompt, README read plus ordinary workspace/persistent-scratch writes, system read, external temporary read and fixture-marker non-disclosure. Scratch uses only an exclusive child of the existing safe root, with identity-checked cleanup; root safety and identity checks include the intermediate `~/Projects/eyrie` directory. Drift is retained and reported. Fixture and client-side Git commands use process-local isolated Git configuration, preserving real HOME/client authentication and native permissions. Performed assertions require successful nonempty replies. Exit 1 means failure; 2 means skipped/unverified, including unavailable scratch or uncertain cleanup; 0 means all selected behavioral checks passed. A moved/unreadable fixture HEAD stops the probe without reset. Mocks and static checks do not establish live behavior.

Use `CANARY_TOOLS=claude CANARY_CHECKS=read make canary` for a focused retry of the combined README/workspace/scratch case. `CANARY_CHECKS` accepts unique names from `skills gate read system temp secret`; unset runs all. The output names a selected scope, and invalid selectors refuse before fixture creation. A focused pass covers only its selected cases. Failed README replies are displayed only up to 8 KB. Each client runs under an owned supervisor; verified termination precedes cleanup, while uncertain child termination preserves both work and scratch fixtures.

Cross-client canaries use the script's standard `/tmp` fixture layout. When the caller's `TMPDIR` names a tool-specific session root, use `env -u TMPDIR CANARY_TOOLS=claude make canary` for fresh shared-temp fixtures. Claude Code protects `/tmp/opencode` as foreign session material; placing their ordinary workspace/temp probes there tests that exclusion instead of normal access.

Consult [`docs/maintenance.md`](maintenance.md) before major tool or plugin changes, permission or bridge changes, cross-host work, `/doctor`, or work on a listed limitation or deferred item.

### Claude Compatibility Acceptance

After the 2.1.272 upgrade, use owned non-secret fixtures and the existing controls to check the [changed 2.1.271 interfaces](access.md#claude-code):

- Confirm global guidance and skill discovery in a fresh session using safe native listings and observed skill reads.
- Exercise Bash file operands following unrecognized options, wildcard expansion inside pattern/option values, and declaration-flag handling under an approved synthetic path policy, with an ordinary allowed-read control. Record native permission decisions. The optional external-read fence needs its own authorized fixture if tested; it is not enabled in the managed baseline.
- When reviewer execution is authorized, confirm the read-only auditor can return through the classifier-reviewed hand-back path under auto mode while retaining its guidance and tool caps.
- Switch between explicitly owned fixture conversations and check the resumed conversation's read-before-edit behavior. A successful reread alone does not prove stale tracking was rejected; record a native decision witness where the client exposes one.

Keep unavailable native evidence marked unverified and retain pending checks in the ledger. A model's refusal or assurance is not independent dispatch proof; do not force prohibited calls to manufacture evidence. Inline skill-shell permission handling needs a separate check if a managed skill later adopts it. These checks require no feature adoption, new service or wider permissions.
