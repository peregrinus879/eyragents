# AGENTS.md - EyrAgents

EyrAgents is a GNU Stow repository that deploys shared configuration for Claude Code and OpenCode. It is standalone: no host-dotfiles repository is required, and changes stay portable across Omarchy and Arch WSL unless a platform scope is explicit.

## Operating Principle

The harness lets Claude Code and OpenCode work at full capability without exposing H. A restriction earns its place only by preventing a named exposure: secrets and H's personal folders (denied), and remote, third-party, destructive or hard-to-reverse effects (native ask prompt). Everything else in the authorized scope runs without prompts, rituals or custom machinery, with the same outcome in both tools. Before adding a rule, hook, prompt or procedural step, name the exposure it prevents; remove any that prevents none.

## Loading

- Global guidance is `agents/.agents/global-agents.md`, reached through `~/.claude/CLAUDE.md` and `~/.config/opencode/AGENTS.md` symlinks. It is not named `AGENTS.md` because both tools also load `AGENTS.md` files from subdirectories they read.
- Both tools read this file natively as the project's `AGENTS.md`. Claude Code needs 2.1.277 or later and no `CLAUDE.md` in the repository, which would take precedence.
- Global skills live in `agents/.agents/skills/`; each skill directory is linked whole into `~/.agents/skills` and `~/.claude/skills`, since Claude Code reads only the latter. This repository's own skill, `eyrsync`, lives in `.agents/skills` with a `.claude/skills` directory link.

## Ownership

| Owner | Holds |
| --- | --- |
| This file | Invariants for agents changing the repository |
| [README](README.md) | Overview and navigation |
| [Setup](docs/setup.md) | Installation, deployment, moves and adaptation |
| [Operations](docs/operations.md) | Daily use, workflows and verification |
| [Access policy](docs/access.md) | The permission model, each tool's implementation and limits, restricted launches |
| [Design](docs/design.md) | Rationale |
| [Maintenance ledger](docs/maintenance.md) | Open work only: each item states what is open, why, and what closes it |
| Skills | Workflow procedures (`ship`, `spar`, `eyrsync`) |
| [Workspace guide source](docs/workspace-guide-src/README.md) | The offline guide's facts and build |
| Script headers, tests | Local constraints and the checked contracts |

State each fact once, at its owner, and link to it. Git history holds provenance.

## Invariants

- **Live configuration.** The packages are deployed as links, so an edit to a settings file, skill or bridge is live before any commit: for the next session of each tool, and at once in running Claude Code sessions. Work on this repository only in a session H is watching, and run mutation checks on a scratch copy, never on the packages in place.
- **Parity.** A permission change lands in both tools' configurations with the same outcome, or the difference is recorded in the access policy with its reason. [`tests/config-contracts.py`](tests/config-contracts.py) holds both to the same decisions and holds Claude Code's copy of the sparrer charter equal to its source; extend it with every rule change. Do not weaken a stricter boundary merely to match the other tool.
- **Protected paths.** Keep the protected-path inventory in the access policy and both configurations in step. Credentials, sign-in sessions and host state never enter Git; the tracked Claude settings are the one file the app rewrites, so review those rewrites rather than reverting them.
- **Native approvals.** Commits and pushes go through `ship` and each tool's native prompt; never launch a nested client, broker or override to get around a native boundary. The spar bridges are the one sanctioned cross-tool launch.
- **Untrusted checkouts.** Trusted-repository defaults are not an isolation boundary; use the [restricted launches](docs/access.md#untrusted-checkouts).
- **Cross-host changes.** A change to deployed state is deployed on the host where it is made, and the same commit adds an item to the ledger with the exact steps for the other host.
- **Review.** A change to either tool's permission configuration, a bridge, the sparrer charter or global guidance is where a spar review earns its cost; no review is mandatory.

## Checks

`make lint check` are the repository checks; `make restow verify` deploys and checks the current host. `ship` runs them on the staged state before a commit. Restart OpenCode after configuration or skill changes before claiming them live.
