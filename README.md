# EyrAgents

Shared guidance, skills, and reviewed Git workflows for **Claude Code, Codex, OpenCode, and Hermes Agent** on Omarchy and Arch WSL. [GNU Stow](https://www.gnu.org/software/stow/) deploys the tool adapters; private host configuration is reconciled from templates.

This is a personal harness. Omarchy owns desktop client installation and EyrWSL owns the WSL launchers; EyrAgents owns client configuration and shared workflows.

## What Is Included

- One source for shared guidance and reusable [Agent Skills](https://agentskills.io).
- Tool-specific access controls, with their differences documented in the [access policy](docs/access.md).
- Exact-candidate commit approval, exact-approved agent publication, and optional read-only review.
- Repeatable deployment checks and opt-in live smoke tests.

## Tools And Layout

| Source | Deployed role |
| --- | --- |
| `agents/.agents/` | Shared guidance, skills, reviewer bridges, and auditor charter. |
| `claude-code/.claude/` | Claude Code instructions, settings, skill links, auditor, and status line. |
| `codex/.codex/` + `templates/codex/` | Codex instructions and the template for its private host-local configuration. |
| `opencode/.config/opencode/` | OpenCode instructions, models, permissions, TUI, commands, and plugins. |
| `hermes/.hermes/` + `templates/hermes/` | Hermes plugin and the template for its private host-local configuration. |
| `scripts/`, `tests/`, `docs/` | Deployment helpers, verification, and documentation. |

The [architecture guide](docs/design.md#configuration-ownership) explains linked packages, whole skill-directory links, copied hooks, and reconciled files. The [Makefile](Makefile) owns deployment targets and the package list.

## Repository Family

The three repositories share the `Eyr` prefix and normally live under `~/Projects/eyrie/`.

| Repository | Purpose |
| --- | --- |
| [EyrAgents](https://github.com/peregrinus879/eyragents) | Shared guidance, skills, and reviewed Git workflows for Claude Code, Codex, OpenCode, and Hermes Agent. |
| [EyrArcHy](https://github.com/peregrinus879/eyrarchy) | Personal shell, desktop, and editor customizations for an existing Omarchy installation. |
| [EyrWSL](https://github.com/peregrinus879/eyrwsl) | A self-contained Arch WSL terminal environment with Windows integration and mise-managed AI tools. |

## Setup

Start with the [setup guide](docs/setup.md): prerequisites, client installation and sign-in, conflict handling, deployment, and adaptation for another user.

**The deployed clone is live configuration.** Review personal guidance and permissions before adopting it; edits to linked files can take effect before a commit. Credentials and application history stay outside Git.

## Usage

Start an installed client in the project you want to work on. The [operations guide](docs/operations.md) covers continuation, model effort, native learning, and verification.

| Workflow | Canonical procedure |
| --- | --- |
| Commit an atomic change | [commit](agents/.agents/skills/commit/SKILL.md) |
| Review and publish commits | [publish](agents/.agents/skills/publish/SKILL.md) |
| Obtain a second opinion | [spar](agents/.agents/skills/spar/SKILL.md) |
| Reconcile the harness with upstream tools | [eyrsync](.agents/skills/eyrsync/SKILL.md) |

Ordinary authorized implementation proceeds autonomously. H separately approves the exact commit candidate and exact publication binding. The agent runs one guarded `publish-apply ID` attempt, then verifies the bound endpoint and published state separately. Host-local authentication, normally `gh`/HTTPS for GitHub, supplies capability, not approval; [setup](docs/setup.md) links the host-owned onboarding. The skills own the detailed procedures.

## Verify

From the repository root, `make lint check` runs repository checks; `make restow verify` deploys and checks the current host. `make canary` is a separate live smoke test. See [verification and its limits](docs/operations.md#verify).

## Documentation

| Need | Read |
| --- | --- |
| Install, move, or adapt the harness | [Setup](docs/setup.md) |
| Use the tools and run checks | [Operations](docs/operations.md) |
| Understand configuration ownership and design | [Design](docs/design.md) |
| Compare permissions or inspect an untrusted checkout | [Access policy](docs/access.md) |
| Find unresolved issues or pending host work | [Maintenance ledger](docs/maintenance.md) |
| Change the repository with an agent | [AGENTS.md](AGENTS.md) |

## License

[MIT](LICENSE)
