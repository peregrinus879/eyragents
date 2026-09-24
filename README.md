# EyrAgents

Global guidance, skills, and reviewed Git workflows for **Claude Code and OpenCode** on Omarchy and Arch WSL. [GNU Stow](https://www.gnu.org/software/stow/) deploys the tool adapters.

This is a standalone personal harness. It owns AI-client configuration, startup defaults and shared workflows, and uses ordinary installed tools without depending on a host-dotfiles repository.

## What Is Included

- One source for global guidance and reusable [Agent Skills](https://agentskills.io).
- Tool-specific access controls, with their differences documented in the [access policy](docs/access.md).
- Exact-candidate commit approval, exact-approved agent publication, and optional read-only review.
- Repeatable deployment checks and opt-in live smoke tests.
- One offline development-workspace guide covering the host environment and both AI clients.

## Tools And Layout

| Source | Deployed role |
| --- | --- |
| `agents/.agents/` | Global guidance, skills, reviewer bridges, and auditor charter. |
| `claude-code/.claude/` | Claude Code instructions, settings, skill links, auditor, and status line. |
| `opencode/.config/opencode/` | OpenCode instructions, models, permissions, TUI, commands, and the commit-gate plugin. |
| `scripts/`, `tests/`, `docs/` | Deployment helpers, verification, and documentation. |

The [architecture guide](docs/design.md#configuration-ownership) explains linked packages, whole skill-directory links, and the copied hook. The [Makefile](Makefile) owns deployment targets and the package list.

## Independence

Clone this repository wherever you keep projects. Setup, checks, reference maintenance and the [offline workspace guide](docs/workspace-guide.html) are owned here. Other projects inherit the stowed global harness through their AI client; they need no local import or EyrAgents-specific configuration.

## Setup

Start with the [setup guide](docs/setup.md): prerequisites, client installation and sign-in, conflict handling, deployment, and adaptation for another user.

**The deployed clone is live configuration.** Review personal guidance and permissions before adopting it; edits to linked files can take effect before a commit. Credentials and application history stay outside Git.

## Usage

Start an installed client in the project you want to work on. The [operations guide](docs/operations.md) covers continuation, model effort, shared workflows, and verification. The [offline workspace guide](docs/workspace-guide.html) combines `hdw`, Herdr, editor/shell controls and AI-client workflows, with an Omarchy/Arch WSL selector and saved favorites. Open it locally in a browser; on GitHub, download the raw HTML first. [Guide maintenance](docs/workspace-guide-src/README.md) explains ownership and rebuilding.

| Workflow | Canonical procedure |
| --- | --- |
| Develop a goal into a verified result | [develop](agents/.agents/skills/develop/SKILL.md) |
| Commit an atomic change | [commit](agents/.agents/skills/commit/SKILL.md) |
| Review and publish commits | [publish](agents/.agents/skills/publish/SKILL.md) |
| Obtain a second opinion | [spar](agents/.agents/skills/spar/SKILL.md) |
| Reconcile the harness with upstream tools | [eyrsync](.agents/skills/eyrsync/SKILL.md) |

The primary uses `develop` for substantive work from intake or resumption through verified delivery and lightweight continuity. It hands repository changes to `commit` when preparation is directed; H approves each exact candidate, then the reviewed publication set through `publish`. Research and plan-only work can finish without Git. Full technical records are available on request. Host-local authentication supplies capability, not approval; [setup](docs/setup.md#github-access) owns standalone onboarding.

## Verify

From the repository root, `make lint check` runs repository checks; `make restow verify` deploys and checks the current host. `make canary` is a separate live smoke test. See [verification and its limits](docs/operations.md#verify).

## Documentation

| Need | Read |
| --- | --- |
| Install, move, or adapt the harness | [Setup](docs/setup.md) |
| Use the tools and run checks | [Operations](docs/operations.md) |
| Find workspace and AI-client controls offline | [Workspace guide](docs/workspace-guide.html) |
| Understand configuration ownership and design | [Design](docs/design.md) |
| Compare permissions or inspect an untrusted checkout | [Access policy](docs/access.md) |
| Find unresolved issues or pending host work | [Maintenance ledger](docs/maintenance.md) |
| Change the repository with an agent | [AGENTS.md](AGENTS.md) |

## License

[MIT](LICENSE)
