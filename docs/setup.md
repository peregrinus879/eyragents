# Setup

[Overview](../README.md) · [Operations](operations.md)

## Prerequisites

- Git, GNU Make, and GNU Stow
- jq, Python, Node.js, mise, and ripgrep (`rg`)
- ShellCheck 0.11.0 or newer
- GNU coreutils and util-linux (`flock`, `setsid`)
- Claude Code and OpenCode installed through [mise](https://mise.jdx.dev); provider sign-in remains interactive.

On Arch Linux:

```bash
sudo pacman -Syu --needed git make stow jq python nodejs shellcheck util-linux mise ripgrep
```

## Client Installation And Sign-In

Install the clients before harness deployment. Existing mise installations can be used directly; no other dotfiles checkout or wrapper is required.

```bash
mise use --global claude@latest opencode@latest gh@latest
```

Keep existing mise trust and release-cooldown preferences; this setup does not lower them.

Follow [mise activation](https://mise.jdx.dev/getting-started.html#activate-mise) for your shell, or use mise shims. Non-interactive launchers can run `mise exec -- claude` or `mise exec -- opencode` with normal client arguments. Only trust project mise configuration you have reviewed.

The OpenCode package stows `~/.config/mise/conf.d/eyragents-opencode.toml`. Mise supplies its skill-discovery and web-search startup defaults without host shell exports, preserving explicit caller values. A direct binary launched outside mise activation/shims does not receive that fragment; use `mise exec` for that launch.

Claude Code and OpenCode use their native interactive sign-in flows. Client support for a model ID does not establish account entitlement. Keep provider credentials outside the repository and complete a successful live reply separately from installation checks.

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
make stow      # guarded cleanup, links, and hook installation
make verify    # repository and deployment checks
```

Stow runs without directory folding, so `~/.claude`, `~/.config/opencode`, and the other managed parents stay real directories that tools may write into. The one exception is each `~/.agents/skills/<name>`, linked whole by `make stow` so files added to a skill deploy without a restow. Stow reports any conflicting regular file without changing it; reconcile it explicitly.

Every host-writing Make target checks deployed-clone ownership, including cleanup and gate installation. `make check-skills` preflights every selected skill before cleanup or link conversion; foreign files or links cause unchanged refusal rather than partial conversion. Deployment goals are serialized within one Make invocation, including `make -j`; this is not a transaction against I/O failure or independent concurrent deployments. `make dry-run` previews Stow, not cleanup or gate installation.

`make stow` and `make restow` also install `templates/hooks/commit-gate` as a real file under `~/.agents/hooks`, outside every workspace, so workspace edits cannot change it.

For later updates, use `make restow verify`. `make unstow` removes package links. When moving clones, unstow from the old clone before stowing the new one. If the old clone is unavailable, guarded preparation removes only recognized dangling links, including those of retired packages. Restart the affected clients after deployment, especially OpenCode.

The publication skill deploys executable `publish-bind`, `publish-apply`, `publish-verify` and `publish-clip` under `~/.agents/skills/publish/scripts`, with Claude's matching leaf symlinks. `make verify` checks those executables and deployed paths. Restart clients to load changed skills; source edits do not replace a running session's loaded instructions. Deployment does not establish authenticated publication.

### GitHub Access

H handles login, storage selection and recovery locally. For GitHub, use HTTPS and the host-local gh credential helper; existing working authentication needs no replacement.

```bash
gh auth login --hostname github.com --git-protocol https
gh auth setup-git
```

These are interactive onboarding steps, separate from Stow and agent publication approval. Configure a GitHub no-reply commit identity through your ordinary Git setup. Existing remotes are not changed automatically. Follow the [GitHub CLI documentation](https://cli.github.com/manual/gh_auth_login) for storage and recovery; never print or copy credentials into this repository. [Operations](operations.md#exact-approved-publication) owns publication usage and its evidence boundaries.

### Reference Clones

`references.txt` declares this repository's references. GitHub rows contain `<directory> <URL> github:<reviewed-node-id>`; other endpoints use the first two fields. Bootstrap missing clones only after approving each URL/destination under `~/Projects/quarry` and recording identity from official GitHub metadata. Existing GitHub refreshes require `gh` metadata access. Preview with `bash scripts/update-references.sh --dry-run`; run `make refs`, or pass the same declared names. The updater preserves local work and tags and reconciles verified same-project canonical URL moves in origin and this manifest. It retains explicit push destinations and stops on unknown identity or unsafe inputs. New/different projects and destructive resolution remain separate decisions; [eyrsync](../.agents/skills/eyrsync/SKILL.md#reference-lifecycle) owns the complete procedure.

## Adapt For Another User

The harness is personal, and forking it means replacing a few facts rather than the structure:

- The addressee. The guidance and skills speak to `H`; the commit skill's identity check expects a GitHub no-reply address.
- The platforms. Omarchy and Arch WSL are the checked environments. Review filesystem, runtime and native-permission assumptions before adding another platform; the deployed-clone guard is independent of checkout location.
- The models. Review Claude Code settings and OpenCode's primary/small-model settings. Update the corresponding model contracts in `tests/config-contracts.py` when deliberately choosing different defaults.
- The packages. `PACKAGES` in the Makefile names what Stow deploys. A new client may need links or a native plugin; use its supported loading mechanism rather than assuming every adapter is a symlink tree.
- The credential list. It lives in the native configurations, OpenCode's shared path helper, bridges and scanner. The configuration tests check the relevant path boundaries.

The [design guide](design.md) explains the shared workflow and deployment choices. Review those choices before adopting the harness for a different environment.
