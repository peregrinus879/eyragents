# Setup

[Overview](../README.md) · [Operations](operations.md)

## Prerequisites

- Git, GNU Make, and GNU Stow
- jq, Python with PyYAML, and Node.js (required for EyrAgents verification, not the EyrWSL baseline)
- ShellCheck 0.11.0 or newer
- GNU coreutils and util-linux (`flock`, `setsid`)
- Claude Code, Codex, OpenCode, and Hermes Agent installed through [mise](https://mise.jdx.dev) under `~/.local/share/mise`, where the Codex sandbox can execute them: Omarchy's own wrappers on the desktop, EyrWSL's `mise` package on WSL. Hermes uses a private Python 3.13 runtime; provider sign-in remains interactive.

On Arch Linux:

```bash
sudo pacman -Syu --needed git make stow jq python python-yaml nodejs shellcheck util-linux
```

### WSL Account Check

On WSL, run `id -u` as the normal Linux user before deploying this harness. The current Codex profile names `/tmp/claude-1000` literally and therefore assumes UID **1000**. If the result differs, stop for a harness-policy review; do not renumber an existing account or weaken permissions to proceed. This restriction belongs to the current EyrAgents profile, not EyrWSL itself. The [WSL host pass](maintenance.md#wsl-host-pass) owns the remaining checks.

## Client Installation And Sign-In

Install the clients before harness deployment:

- **Omarchy:** use the upstream-owned client installers and wrappers, with [host installation notes](https://github.com/peregrinus879/eyrarchy/blob/main/docs/setup.md#ai-clients).
- **WSL:** follow [EyrWSL's wrapper bootstrap](https://github.com/peregrinus879/eyrwsl/blob/main/docs/setup.md#9-stow).

The tools themselves are installed through [mise](https://mise.jdx.dev). Hermes uses the pipx backend with a private Python 3.13 runtime and uv. Follow Omarchy's PyPI release channel, with Hermes 0.19.0 as this harness's compatibility baseline, rather than substituting a newer Git checkout.

Claude Code, Codex, and OpenCode use their native interactive sign-in flows. For Hermes, run `hermes model` and choose **ChatGPT or Codex Subscription**, then Astra if the account catalog offers it. Client support for a model ID does not establish account entitlement. Keep provider credentials outside the repository and complete a successful live reply separately from installation checks.

## Clone

```bash
mkdir -p ~/Projects/eyrie
git clone https://github.com/peregrinus879/eyragents.git ~/Projects/eyrie/eyragents
cd ~/Projects/eyrie/eyragents
```

## Deploy

After installing the clients and reviewing the personal guidance, run from the repository root. Preview first and resolve each reported conflict before deployment:

```bash
make dry-run   # preview Stow actions before resolving conflicts
make stow      # guarded cleanup, links, hook installation, and private config reconciliation
make verify    # repository and deployment checks
```

Stow runs without directory folding, so `~/.claude`, `~/.config/opencode`, and the other managed parents stay real directories that tools may write into. The one exception is each `~/.agents/skills/<name>`, linked whole by `make stow`, because Codex's skill loader follows directory links and skips file links. Stow reports any conflicting regular file without changing it; reconcile it explicitly.

Every host-writing Make target checks deployed-clone ownership, including cleanup, gate installation, and Codex/Hermes reconciliation. `make check-skills` preflights every selected skill before cleanup or link conversion; foreign files or links cause unchanged refusal rather than partial conversion. Deployment goals are serialized within one Make invocation, including `make -j`; this is not a transaction against I/O failure or independent concurrent deployments. `make dry-run` previews Stow, not all reconciliation effects.

`make stow` and `make restow` also install `templates/hooks/commit-gate` as a real file under `~/.agents/hooks`, outside every workspace because the hooks run it outside the Codex sandbox, and install `~/.codex/config.toml` from `templates/codex/config.toml` as a host-local file. The template owns the effort, review, feature, and permission settings; host-only tables, `hooks.state`, and the root `service_tier` a `/fast` choice writes are preserved across reconciliations, the latter unless the host root is still exactly a committed template's, which is residue. Reconciliation parses TOML boundaries and checks preserved semantics before emitting replacement bytes; unsupported layouts, including inline/dotted `hooks.state`, refuse rather than discard state. Stop for deliberate host-local repair, without printing configuration values.

For later updates, use `make restow verify`. `make unstow` removes package links. When moving clones, unstow from the old clone before stowing the new one. If the old clone is unavailable, guarded preparation removes only recognized dangling links. Restart the affected clients after deployment, especially OpenCode.

The publication skill deploys executable `publish-bind`, `publish-apply`, `publish-verify` and `publish-clip` under `~/.agents/skills/publish/scripts`, with Claude's matching leaf symlinks. `make verify` checks those executables and deployed paths. Codex keeps its protected-file and network restrictions and follows the [separate-primary publication handoff](../agents/.agents/skills/publish/SKILL.md). Restart clients to load changed skills; source edits do not replace a running session's loaded instructions. Deployment does not establish authenticated publication.

GitHub authentication setup belongs to the host repositories: follow [EyrArcHy](https://github.com/peregrinus879/eyrarchy/blob/main/docs/setup.md#github-access) or [EyrWSL](https://github.com/peregrinus879/eyrwsl/blob/main/docs/setup.md#github-access) for standard `gh` login, host-local helper configuration and HTTPS origins. H performs login, storage selection and recovery locally. Complete the appropriate fresh-client and reboot checks before claiming routine readiness. Credential inspection and global-auth configuration are not part of harness deployment. The [maintenance ledger](maintenance.md#publication-access) owns pending evidence; [operations](operations.md#exact-approved-publication) owns usage.

## Hermes Configuration

`make restow` composes the canonical guidance into `agent.environment_hint` and merges the template's explicit leaves into a private, real `~/.hermes/config.yaml`. External skill directories and enabled plugins are additive. Other settings and project trust are preserved by parsed value; YAML comments/formatting are application-owned. Hermes's model wizard may retain the canonical Codex `base_url`; that endpoint and an agreeing model-name alias are preserved. Duplicate keys, YAML aliases, unsafe files, explicit disabling of the managed plugin, inline model credentials, or conflicting provider selectors refuse unchanged. Do not inspect or dump host configuration to diagnose a refusal; it can contain provider/MCP credentials. `make dry-run` previews Stow links, not this configuration merge.

## Adapt For Another User

The harness is personal, and forking it means replacing a few facts rather than the structure:

- The addressee. The guidance and skills speak to `H`; the commit skill's identity check expects a GitHub no-reply address.
- The hosts. Omarchy and WSL are named in the guidance, the Makefile guards, and the ledger's host pass items; the `require-host` guards in the sibling repositories encode which machine runs which targets.
- The models. Review Claude Code settings, the Codex template, OpenCode's primary/small-model settings, and the Hermes template. Update the corresponding model contracts in `tests/config-contracts.py` and `tests/hermes.py` when deliberately choosing different defaults.
- The packages. `PACKAGES` in the Makefile names what Stow deploys. A new client may need links, a native plugin, or private configuration reconciliation; use its supported loading mechanism rather than assuming every adapter is a symlink tree.
- The credential list. It lives in the native configurations, Hermes guard, bridges and scanner. Configuration and Hermes tests check the relevant path boundaries.

The [design guide](design.md) explains the shared workflow and deployment choices. Review those choices before adopting the harness for a different environment.
