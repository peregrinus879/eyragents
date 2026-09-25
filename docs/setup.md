# Setup

[Overview](../README.md) · [Operations](operations.md) · [Access policy](access.md)

## Prerequisites

- Git, GNU Make, GNU Stow, jq, Python 3, mise, and GNU coreutils and util-linux (`setsid`).
- ShellCheck 0.11.0 or newer, for `make lint`.
- Claude Code 2.1.277 or newer and OpenCode, installed through [mise](https://mise.jdx.dev).

On Arch Linux:

```bash
sudo pacman -Syu --needed git make stow jq python shellcheck util-linux mise
mise use --global claude@latest opencode@latest gh@latest
```

Activate mise for your shell ([mise activation](https://mise.jdx.dev/getting-started.html#activate-mise)) or use its shims. Launchers that run outside an activated shell use `mise exec -- claude` or `mise exec -- opencode`. The OpenCode package deploys `~/.config/mise/conf.d/eyragents-opencode.toml`, which supplies OpenCode's startup defaults through mise and keeps any value the caller sets explicitly; a binary started outside mise does not receive them.

Sign in to each client through its own interactive flow. Credentials stay with the clients, outside the repository.

## Deploy

```bash
git clone https://github.com/peregrinus879/eyragents.git ~/Projects/eyrie/eyragents
cd ~/Projects/eyrie/eyragents
make dry-run   # preview Stow's links
make stow      # clean up, link the packages and the skill directories
make verify    # repository and deployment checks
```

Resolve each conflict `make dry-run` reports before deploying; Stow never overwrites an existing file. Restart the clients afterwards, OpenCode in particular, since it loads configuration at startup.

How deployment behaves:

- **Real parent directories.** Stow runs with `--no-folding`, so `~/.claude`, `~/.config/opencode` and the other managed parents stay real directories the tools can write into; only files are links. Each skill directory is the exception: `~/.agents/skills/<name>` and `~/.claude/skills/<name>` are single links to the whole directory, so a file added to a skill deploys without a restow.
- **Clone guard.** Every target that writes to the host checks that the deployed links belong to this clone, and `make check-skills` checks every skill before any cleanup. A foreign file or link at a path this repository manages is refused unchanged rather than taken over; unrelated entries, such as the skills Omarchy installs beside these, are left alone.
- **Cleanup.** Preparation removes only dangling links it recognizes as this repository's, including those of retired files, and prunes managed directories they leave empty.
- **One invocation at a time.** Deployment goals in one Make invocation run serially, even under `make -j`. This is not a transaction against disk failure or a second concurrent deployment.

## Update, Move and Remove

- **Update:** pull, then `make restow verify`, then restart the clients.
- **Move the clone:** run `make unstow` in the old clone, then `make stow` in the new one. If the old clone is gone, preparation in the new one removes its dangling links.
- **Remove:** `make unstow`.

## GitHub Access

Publication uses HTTPS with the GitHub CLI's credential helper. Sign in and connect Git once, interactively:

```bash
gh auth login --hostname github.com --git-protocol https
gh auth setup-git
```

Set your commit identity to your GitHub no-reply address in your ordinary Git configuration; the [ship skill](../agents/.agents/skills/ship/SKILL.md) stops if either identity resolves elsewhere. Existing remotes are left as they are. The [GitHub CLI manual](https://cli.github.com/manual/gh_auth_login) covers storage and recovery.

## Reference Clones

[`references.txt`](../references.txt) declares the upstream repositories the harness is checked against: Claude Code's public release and support repository, and OpenCode's source. Clones live under `~/Projects/quarry`. `bash scripts/update-references.sh --dry-run` previews a refresh and `make refs` performs it; the updater refreshes existing clones only, preserves local work, and verifies each project's identity against its pinned GitHub node ID. Creating a clone is a separate, approved step. The [eyrsync skill](../.agents/skills/eyrsync/SKILL.md#reference-lifecycle) owns the full procedure.

## Adapt For Another User

The structure transfers as it is; a few facts are personal:

- **The addressee and profile.** Global guidance speaks to `H` and describes H's background. Replace the opening profile, and the name throughout global guidance, the skills and the sparrer charter.
- **Paths.** Persistent scratch is `~/Projects/eyrie/scrape`, with plan files in its `plans/` directory, and references live under `~/Projects/quarry`. They appear in guidance, both configurations, scripts, tests and docs; find every use with `git grep -n 'eyrie/scrape\|Projects/quarry'` and change them as one set.
- **Personal folders.** The denied folders are listed in global guidance, both configurations and the test.
- **Identity.** The ship skill expects a GitHub no-reply commit identity.
- **Models.** Claude Code's settings and the sparrer's frontmatter name Claude models; OpenCode's configuration names its primary and small models, with concrete IDs.
- **Platforms.** Omarchy and Arch WSL are the checked environments. Review filesystem, runtime and permission assumptions before adding another.
- **Packages.** `PACKAGES` in the [Makefile](../Makefile) lists what Stow deploys. A new client may need a native plugin or loader rather than a link tree.

After a change, run `make lint check`: the parity test catches a permission edit made in only one tool.
