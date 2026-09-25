# Operations

[Overview](../README.md) · [Setup](setup.md) · [Access policy](access.md)

Client commands run from the project you are working on; `make` targets run from the EyrAgents root.

## Start and Continue

| Client | Start | Continue the last session |
| --- | --- | --- |
| Claude Code | `claude` | `claude -c` |
| OpenCode | `opencode` | `opencode -c` |

[Setup](setup.md#prerequisites) covers launching through mise. For an untrusted checkout, use the [restricted launches](access.md#untrusted-checkouts). The [offline workspace guide](workspace-guide.html) collects these controls with the terminal, editor and host references for Omarchy and Arch WSL.

## Workflows

Every project inherits the global skills; OpenCode also offers each as a slash command, such as `/ship`.

- **Commit and publish:** [ship](../agents/.agents/skills/ship/SKILL.md). The agent builds and gates a round of commits, then ends its turn with a card for each; your reply brings one native prompt that makes the round. Publication works the same way: cards, your go, one push prompt. A failed CI run gets one retry after its logs show a retryable cause.
- **Independent review:** [spar](../agents/.agents/skills/spar/SKILL.md). The read-only `sparrer` reviews in rounds, from the same model family by default or from the other tool's through a bridge. The agent uses it when a second opinion could change a consequential decision, without being asked.
- **Harness reconciliation:** [eyrsync](../.agents/skills/eyrsync/SKILL.md) compares this harness with each tool's current documentation, releases and source.
- **Long work:** a live plan file in `~/Projects/eyrie/scrape/plans/` carries the goal, H's decisions, what remains and the next step, as global guidance's Continuity rule describes; it is deleted when the work is done.

## Model Effort

- **Claude Code:** the `effortLevel` setting is `xhigh`; `/effort` changes it for a session. The sparrer's frontmatter sets its own `xhigh`.
- **OpenCode:** the primary model's configured effort is `xhigh`. In `/variants`, `Default` keeps that configured value, and a named variant overrides it. OpenCode remembers a choice per model, separately for a model and its Fast variant, and may skip the dialog when one exists. The effort badge shows the selection, not the request actually sent.

## Verify

```bash
make lint check      # repository checks
make restow verify   # deploy, then check the deployment
```

GitHub Actions runs `make lint check` on every push to `main` and every pull request, in an `archlinux:base` container as an unprivileged user. It does not deploy to or attest a host.

### Canary

`make canary` is a live smoke test through the real clients, not a repository gate. Within six calls per tool it checks that the shared skills are listed, a commit stops at the native prompt, a README read and ordinary workspace and persistent-scratch writes succeed, a system file and a temporary file can be read, and a credential-shaped fixture is not disclosed. It checks the fixture repository's HEAD after every call and stops, without resetting, if it moved.

| Exit | Meaning |
| --- | --- |
| 0 | Every selected check passed (behavior, not proof of permission dispatch) |
| 1 | A check failed |
| 2 | A check was skipped or unverified |

`CANARY_TOOLS` selects clients (default `claude opencode`) and `CANARY_CHECKS` selects checks from `skills gate read system temp secret`; for example, `CANARY_TOOLS=claude CANARY_CHECKS=read make canary`. Each client runs under a supervisor that stops all its processes before fixtures are cleaned up; when that cannot be confirmed, fixtures are kept. If `TMPDIR` points into a client's session directory, run `env -u TMPDIR make canary`.

### Permission Acceptance

After a permission change, `make restow verify` and restart OpenCode, then confirm in each tool with owned, non-secret fixtures:

1. a read outside the project (a system file, a dotfile) runs without a prompt;
2. a synthetic `.env` read is refused;
3. a remote-changing command (`gh issue comment`) and a destructive one (`git reset --hard`) raise a native prompt, which you decline;
4. in OpenCode, an edit outside the project and scratch asks, and a recursive `rm` asks;
5. after a real change, one `ship` round ends its turn with the cards, and your reply brings a single commit prompt; the same holds for one push.

The [access policy](access.md) owns the expected outcome of each case. Persistent scratch at `~/Projects/eyrie/scrape` is preserved project work; use a uniquely named child for disposable tests.
