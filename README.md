# EyrAgents

One harness for **Claude Code** and **OpenCode**: shared global guidance, reusable [Agent Skills](https://agentskills.io), and a permission policy that gives both tools the same outcome. [GNU Stow](https://www.gnu.org/software/stow/) deploys it into your home directory; other projects inherit it without any local setup.

The governing idea: an agent works at full capability and prompts only where a real exposure exists. Secrets and personal folders are denied, remote, destructive and hard-to-reverse actions ask at the tool's native prompt, and everything else runs.

## What You Get

| Part | What it does |
| --- | --- |
| [Global guidance](agents/.agents/global-agents.md) | One instruction file both tools load: approach, style, safety and workflow rules. |
| [`ship`](agents/.agents/skills/ship/SKILL.md) | Commits and publishes verified work. The agent ends a turn with a card for each commit; your reply brings one native approval prompt for the round. |
| [`spar`](agents/.agents/skills/spar/SKILL.md) | Independent review in rounds by a read-only reviewer, the `sparrer`, from the same model family or, through a bridge, from the other tool's. |
| [Access policy](docs/access.md) | The permission model, what each tool enforces, and where the tools differ. |
| Tests | A parity test that holds both tools' permissions to the same decisions, bridge and deployment tests, and an opt-in live canary. |
| [Workspace guide](docs/workspace-guide.html) | One offline page of terminal, editor and AI-client controls for Omarchy and Arch WSL; on GitHub, download the raw file and open it in a browser. |

## Requirements

Linux with Git, GNU Make, GNU Stow, jq, Python 3, ShellCheck and mise; Claude Code and OpenCode installed through mise. The checked hosts are [Omarchy](https://omarchy.org) and Arch Linux on WSL 2. [Setup](docs/setup.md) lists exact packages.

## Quick Start

```bash
git clone https://github.com/peregrinus879/eyragents.git ~/Projects/eyrie/eyragents
cd ~/Projects/eyrie/eyragents
make dry-run   # preview the links; resolve any reported conflict first
make stow      # deploy
make verify    # repository and deployment checks
```

Read [global guidance](agents/.agents/global-agents.md) and the [access policy](docs/access.md) before deploying: the guidance addresses its owner as **H**, and the deployed clone is live configuration, so an edit takes effect before it is committed. [Adapt for another user](docs/setup.md#adapt-for-another-user) lists what to change.

## Documentation

| Need | Read |
| --- | --- |
| Install, update, move or adapt | [Setup](docs/setup.md) |
| Daily use, workflows and checks | [Operations](docs/operations.md) |
| Permissions and their limits | [Access policy](docs/access.md) |
| Why it is built this way | [Design](docs/design.md) |
| Open work and pending host checks | [Maintenance ledger](docs/maintenance.md) |
| Rules for agents changing this repository | [AGENTS.md](AGENTS.md) |

Companion repositories: [EyrArcHy](https://github.com/peregrinus879/eyrarchy) (Omarchy dotfiles) and [EyrWSL](https://github.com/peregrinus879/eyrwsl) (an Omarchy-like Arch WSL environment).

## License

[MIT](LICENSE)
