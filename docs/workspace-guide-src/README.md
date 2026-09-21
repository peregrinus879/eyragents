# Workspace Guide

Open [`../workspace-guide.html`](../workspace-guide.html) in a modern browser and select **Omarchy** or **Arch WSL**. On GitHub, download the raw HTML first. The single file works offline, including search, host/layer/task filters, saved keys, launcher recipes, theme and printing. Source links use the network only when selected.

The guide covers `hdw <cc|cx|oc|ha> [-c]`, Herdr, Claude Code, Codex, OpenCode, Hermes Agent, shared agent workflows, Neovim/LazyVim, Neo-tree, Git review, vault notes, Bash tools, Yazi and both outer terminals. Each application's help owns its full evolving catalog.

## Use

- **Daily** is the quick-start set; **All** shows every action for the selected host; **Saved** shows its favorites.
- Press `/` to search actions, shortcuts, commands, modes and context. Searching from Daily expands to All; layer, task and Saved filters remain explicit.
- Expand **Context & source** for modes, effects, routing notes and evidence.
- **Workspace launcher** generates copyable Bash commands. `~` and `~/` expand to HOME; other directory input is quoted literally. Relative paths start with `./` to avoid `CDPATH` and Bash's special `-` destination. Copying never executes anything.
- **Workflow & host notes** connects the panes and AI workflows. **Sources & live help** records evidence and inspection routes.
- **Print view** prints the selected view, including filtered actions and expanded context, then restores disclosure state.
- The host selector is explicit, with Omarchy as the initial default. `?host=eyrarchy` or `?host=eyrwsl` selects a host when opening a link. Selection is retained in browser-local storage when available.

One keybinding is a shortcut; a keymap is the collection. Counts measure reference entries, which may group controls, rather than comparable totals of application capabilities.

## Ownership and rebuild

EyrAgents owns the full guide and builds it independently. EyrArcHy and EyrWSL own the host configuration and remain twins for their declared implementation files. Guide reconciliation is a documentation dependency, not a deployment or build dependency between repositories.

| File | Purpose / evidence owner |
| --- | --- |
| `host-reference.json` | Host actions, launcher recipes, workflows, sources and both profiles. Host configuration work and each host's `/omasync` supply the facts. |
| `client-reference.json` | Portable AI-client actions, workflows, sources and usage notes. EyrAgents and `/eyrsync` supply the facts. Its `eyragents` scope expands to both host profiles during generation. |
| `template.html` | The offline interface, styles and JavaScript. |
| `build.py` | Python standard-library composition, structural validation and staleness checks. Reads only this directory. |
| `../workspace-guide.html` | Generated, tracked single-file deliverable containing both profiles and all client controls. |

From the EyrAgents root:

```bash
make workspace-guide
make lint check
```

The generator rejects duplicate IDs/apps/sources, invalid host/source references, missing application coverage and incomplete launcher selectors. `make check` compares the generated HTML without writing. Skills own workflow procedures; the guide links to those owners.

## Change-coupled maintenance

The author changing a control or adopting an update owns its guide reconciliation in the same workstream. This includes additions, changes, removals and inherited defaults changed by an application/plugin update even when personal configuration did not change.

1. Review the affected entries against the owning configuration, version-matched source and current help. Include arguments, modes, prefixes, clipboard behavior, key interception and enabled plugins. Actual host key delivery requires actual-host evidence.
2. Edit the affected reference file in EyrAgents. Update related recipes, workflows, routing notes and sources together. Keep IDs stable for the same action; remove obsolete actions, retaining retired IDs only when useful for saved-key compatibility.
3. Keep each component's checked date/ref and evidence scope. Moving or rebuilding the guide does not refresh its facts or establish live behavior. Record unchanged behavior in the change review rather than making cosmetic baseline edits.
4. Regenerate and check EyrAgents, then inspect the affected rendered entries for both profiles. Run the affected host repositories' checks; `make twins` protects their remaining implementation twins. A client-only guide change needs only EyrAgents.
5. If EyrAgents companion edits are outside the current authorization, request that scope. If a required checkout, source or actual host is unavailable, record the exact pending reconciliation/check in the change owner's `docs/maintenance.md` and report it incomplete. Link to the existing owner rather than creating another ledger.

`/omasync` owns host/default and `hdw` review; `/eyrsync` owns AI-client controls and workflows. A change to `hdw` arguments or continuation must reconcile the host recipes with client behavior. Each workflow updates this single guide within its authorized scope.

Generation validates file consistency. It does not monitor upstream releases, parse running keymaps, or prove live key delivery. Interface changes should exercise both hosts, search and filters, disclosures, saved-key import/export, all eight launcher combinations, quoted directory input, clipboard fallback, theme, print, narrow/wide layouts and unavailable browser storage in an isolated profile.

## Saved keys

Action IDs and the `eyragents-guide-v1` browser-storage namespace are stable compatibility identifiers. Favorites include recognized IDs from both hosts and all clients; switching host filters their display without discarding them. Export/import transfers favorites explicitly between files or machines.

The guide accepts both `hdw-guide-saved-v1` and `eyragents-guide-saved-v1` exports and exports the latter. Before discarding an old local guide copy, export its saved keys, then import that file here. File-URL storage can differ after a move or rename; existing browser profiles are never inspected or migrated automatically. With storage restricted, the interface and in-tab favorites still work.

The interface adapts H's Keymap dashboard and the starting reference comes from H's Keybind Atlas. The maintained guide is self-contained.
