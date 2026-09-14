# AI Guide

Open `../agent-guide.html` in a browser. It is an offline, self-contained reference for Claude Code, Codex, OpenCode and Hermes Agent, with search, client filters, saved keys, source notes, theme selection and printing. Source links use the network only when selected.

## Ownership

- `reference.json` owns the curated controls, workflow links and evidence baselines.
- `template.html` owns the interface. It has no host-repository imports or synchronization contract.
- `build.py` validates the data and generates `../agent-guide.html` using the Python standard library.
- Skills own workflow procedure; the guide links to them.

Run `make agent-guide` after changing source. `make check` rejects stale output. Updating a client control or workflow includes reviewing its guide entry against current documentation, version-matched source or live help. Keep evidence qualifications and unverified behavior explicit; generation does not establish that a key works in a running client.

## Saved Keys

Saved keys and theme are browser-local. Export/import transfers recognized action IDs explicitly. The guide accepts the legacy `hdw-guide-saved-v1` export format and preserves the AI action IDs; it exports `eyragents-guide-saved-v1`. Existing browser profiles are never inspected or migrated automatically.

For interface changes, check search, client/category filters, Daily/All/Saved, disclosures, saved-key import/export, theme, printing, narrow layouts and operation with browser storage unavailable, using an isolated profile.
