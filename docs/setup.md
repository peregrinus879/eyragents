# Setup

[Overview](../README.md) · [Operations](operations.md)

## Prerequisites

- Git, GNU Make, and GNU Stow
- jq, Python with PyYAML, Node.js, and mise
- ShellCheck 0.11.0 or newer
- GNU coreutils and util-linux (`flock`, `setsid`)
- Claude Code, Codex, OpenCode, and Hermes Agent installed through [mise](https://mise.jdx.dev) under `~/.local/share/mise`, where the Codex sandbox can execute them. Hermes uses a private Python 3.13 runtime; provider sign-in remains interactive.

On Arch Linux:

```bash
sudo pacman -Syu --needed git make stow jq python python-yaml nodejs shellcheck util-linux mise
```

### WSL Account Check

On WSL, run `id -u` as the normal Linux user before deploying this harness. The current Codex profile names `/tmp/claude-1000` literally and therefore assumes UID **1000**. If the result differs, stop for a harness-policy review; do not renumber an existing account or weaken permissions to proceed. The [WSL host pass](maintenance.md#wsl-host-pass) owns the remaining checks.

## Client Installation And Sign-In

Install the clients before harness deployment. Existing mise installations can be used directly; no other dotfiles checkout or wrapper is required.

```bash
mise use --global claude@latest codex@latest opencode@latest uv@latest gh@latest
mise use --global --fuzzy 'pipx:hermes-agent[extras=all,uvx_args="--python 3.13",pipx_args="--python 3.13"]'
```

Hermes uses the PyPI/pipx channel with a private Python 3.13 runtime and uv; 0.19.0 is the compatibility baseline. A newer Git checkout is a separate compatibility decision. Keep existing mise trust and release-cooldown preferences; this setup does not lower them.

Follow [mise activation](https://mise.jdx.dev/getting-started.html#activate-mise) for your shell, or use mise shims. Non-interactive launchers can run `mise exec -- claude`, `mise exec -- codex`, `mise exec -- opencode`, or `mise exec -- hermes` with normal client arguments. Only trust project mise configuration you have reviewed.

The OpenCode package stows `~/.config/mise/conf.d/eyragents-opencode.toml`. Mise supplies its skill-discovery and web-search startup defaults without host shell exports, preserving explicit caller values. A direct binary launched outside mise activation/shims does not receive that fragment; use `mise exec` for that launch.

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

### GitHub Access

H handles login, storage selection and recovery locally. For GitHub, use HTTPS and the host-local gh credential helper; existing working authentication needs no replacement.

```bash
gh auth login --hostname github.com --git-protocol https
gh auth setup-git
```

These are interactive onboarding steps, separate from Stow and agent publication approval. Configure a GitHub no-reply commit identity through your ordinary Git setup. Existing remotes are not changed automatically. Follow the [GitHub CLI documentation](https://cli.github.com/manual/gh_auth_login) for storage and recovery; never print or copy credentials into this repository. [Operations](operations.md#exact-approved-publication) owns publication usage and its evidence boundaries.

### Reference Clones

`references.txt` declares this repository's references. GitHub rows contain `<directory> <URL> github:<reviewed-node-id>`; other endpoints use the first two fields. Bootstrap missing clones only after approving each URL/destination under `~/Projects/quarry` and recording identity from official GitHub metadata. Existing GitHub refreshes require `gh` metadata access. Preview with `bash scripts/update-references.sh --dry-run`; run `make refs`, or pass the same declared names. The updater preserves local work and tags and reconciles verified same-project canonical URL moves in origin and this manifest. It retains explicit push destinations and stops on unknown identity or unsafe inputs. New/different projects and destructive resolution remain separate decisions; [eyrsync](../.agents/skills/eyrsync/SKILL.md#reference-lifecycle) owns the complete procedure.

## Hermes Configuration

`make restow` composes the canonical guidance into `agent.environment_hint` and merges the template's explicit leaves into a private, real `~/.hermes/config.yaml`. External skill directories and enabled plugins are additive. Other settings and project trust are preserved by parsed value; YAML comments/formatting are application-owned. Hermes's model wizard may retain the canonical Codex `base_url`; that endpoint and an agreeing model-name alias are preserved. Duplicate keys, YAML aliases, unsafe files, explicit disabling of the managed plugin, inline model credentials, or conflicting provider selectors refuse unchanged. Do not inspect or dump host configuration to diagnose a refusal; it can contain provider/MCP credentials. `make dry-run` previews Stow links, not this configuration merge.

## Adapt For Another User

The harness is personal, and forking it means replacing a few facts rather than the structure:

- The addressee. The guidance and skills speak to `H`; the commit skill's identity check expects a GitHub no-reply address.
- The platforms. Omarchy and Arch WSL are the checked environments. Review filesystem, runtime and native-permission assumptions before adding another platform; the deployed-clone guard is independent of checkout location.
- The models. Review Claude Code settings, the Codex template, OpenCode's primary/small-model settings, and the Hermes template. Update the corresponding model contracts in `tests/config-contracts.py` and `tests/hermes.py` when deliberately choosing different defaults.
- The packages. `PACKAGES` in the Makefile names what Stow deploys. A new client may need links, a native plugin, or private configuration reconciliation; use its supported loading mechanism rather than assuming every adapter is a symlink tree.
- The credential list. It lives in the native configurations, Hermes guard, bridges and scanner. Configuration and Hermes tests check the relevant path boundaries.

The [design guide](design.md) explains the shared workflow and deployment choices. Review those choices before adopting the harness for a different environment.
