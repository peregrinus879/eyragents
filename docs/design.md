# Design

`AGENTS.md` states the invariants. This note gives the reasons, so a reader can judge whether the same shape fits their own setup.

## Intent-led collaboration

H supplies direction, not an exhaustive specification. Global guidance's [Approach](../agents/.agents/global-agents.md#approach) makes broader reasoning an explicit step before choosing a solution: frame the goal and surrounding system, check missing counterparts and assumptions, and consider alternatives and downstream effects. Interpolation fills reasonable gaps; extrapolation tests related cases. The first example or existing configuration is evidence, not the boundary of the problem. This applies across all work, not only access planning or source references.

Broad reasoning does not authorize broad action. Surface useful omissions and material tradeoffs for H, while well-supported low-risk work proceeds within scope. Likewise, a command that relieves one symptom is not a durable fix when the workflow will require it repeatedly; explain that distinction and the underlying remedy. Keep the analysis proportionate rather than adding a mandatory essay or another approval ritual to trivial work.

## Native approvals

H approves each commit and each push at the tool's native permission prompt. The ship skill writes every card of a round in the chat before the first prompt, and each command names its repository and subject; publication additionally waits for H's go. Git history is the record; no receipt, binding or shell gate stands between the card and the prompt. Destructive or hard-to-reverse commands keep their own prompts.

Authentication is host-owned: GitHub uses HTTPS and the standard `gh` helper, and H controls login, storage and recovery. Credential access supplies capability, not approval. No broker, nested-client workaround or permission override is provided.

## Enforce, then instruct

Rules live at the lowest layer that can hold them. A sandbox constrains the surfaces it actually covers; a permission rule reaches only the subjects its tool checks; hooks see only dispatched calls. Scripts make a procedure repeatable across models and testable in CI; prose states intent and covers what lower layers cannot express. Native prompts hold approval; the skill owns the card that informs it.

## One trust model, two enforcement points

The [access policy](access.md) makes that distinction inspectable across tools: one outcome table for both, enforcement limits, implementation references and official semantics. It is the comparison owner, not another source of permission grants. `/eyrsync` reconciles intent, the access policy, implementation, upstream behavior and evidence together. Parity means equivalent authorized work and safety intent where enforceable, not weakening a stricter tool until the tables look identical.

The tools enforce the same intent to different depths. Claude Code combines deterministic rules with an auto-mode classifier; OpenCode has only static rules, so it asks where Claude Code's classifier would review. Both allow what does not expose H and gate the rest: secrets and personal folders are denied, and remote, destructive or configuration-changing commands ask. Neither is shell containment. The [access policy](access.md) owns the rules and their limits.

Reads are broad and secrets are denied by one finite inventory in both tools, so ordinary configuration, package metadata and diagnostics stay readable. A finite inventory cannot recognize a renamed secret; global guidance still binds there.

Persistent scratch (`~/Projects/eyrie/scrape`) is writable in both tools; OpenCode also writes its session scratch under `/tmp/opencode`. Persistent work there is preserved project work, not disposable by location.

## Independent review

A second opinion is worth most from a fresh context, and more from a different model family. Every reviewer, in-tool or cross-vendor, follows one [charter](../agents/.agents/agents/auditor.md): full context, a top-down review from goal and approach to presentation against global guidance, and read-only conduct. Reviewers have read, search, shell and web tools without edit tools, under the primary's rules, so they verify claims instead of trusting a curated brief. The drafter states what it already did, and the reviewer spends its effort on what was not covered. The bridges run the other tool's client under H's normal settings with the same reviewer tools, Claude Code by tool list and OpenCode through its `auditor` agent, with a hard timeout; a reply without the charter's verdict line fails. Review is recommended where it earns its cost, never mandatory.

Findings and their dispositions go in the plan file; the primary writes it, never a reviewer.

## One neutral source

Guidance and skills live once, under `~/.agents`, the home of the Agent Skills format. Both tools use native global-instruction symlinks to neutral `global-agents.md`: Claude Code's `CLAUDE.md` and OpenCode's `~/.config/opencode/AGENTS.md`. OpenCode does not append the same guidance through explicit `instructions`, so it loads once. Both tools read a project's `AGENTS.md` natively, so repositories carry no `CLAUDE.md` import. The guidance file avoids the name `AGENTS.md` because both tools also auto-load `AGENTS.md` files from subdirectories they read. Skill executables stay in each skill's standard `scripts/` directory; tool-specific discovery adapters do not transfer ownership out of EyrAgents.

## Configuration Ownership

The package directories mirror deployed paths, but not every managed endpoint is a leaf symlink:

| Component | Ownership and deployment |
| --- | --- |
| Global guidance and skills | `agents/.agents/` is canonical. Each skill directory is linked whole, so new skill files deploy without a restow; each client uses its native adapter. |
| Claude Code | `claude-code/.claude/` supplies linked instructions, settings, auditor, and status line; `make stow` links each skill directory into `~/.claude/skills`, the only skill location Claude Code reads. |
| OpenCode | `opencode/.config/opencode/` supplies linked instructions and configuration; its mise fragment supplies startup defaults. |
| Project instructions | Root `AGENTS.md` and `.agents/skills/eyrsync/`, linked for Claude Code as `.claude/skills/eyrsync`, apply to this repository; they are not global Stow payloads. |

Client-owned identity, learning, and session state remain outside the source packages. Credentials and schedules retain their separate authorization boundaries; a package does not install accounts or recurring jobs.

## Documentation Ownership

The README is the overview and navigation entry point. [Setup](setup.md) owns installation, deployment, migration, and adaptation; [operations](operations.md) owns daily use and verification. This guide explains architecture and rationale; [access](access.md) owns the security comparison and restricted launches. Skills own executable workflow procedures, `AGENTS.md` owns agent invariants, and the [maintenance ledger](maintenance.md) holds only unresolved work and live revalidation evidence. Link to those owners instead of copying their detailed procedures into the README.

The [workspace guide](workspace-guide.html) has one authoring/build owner here because the development workflow spans host applications and AI clients. Its [maintenance contract](workspace-guide-src/README.md) keeps host facts with EyrArcHy/EyrWSL configuration work and `/omasync`, and client facts with EyrAgents and `/eyrsync`. Both host profiles and all client controls are embedded in one offline file. EyrArcHy and EyrWSL retain their implementation-twin contract; EyrAgents remains independent. Cross-repository fact review creates a documentation companion when relevant, while building or deploying any repository uses its own sources.

## Reference coverage

The same maintenance questions apply to every tool, but their evidence is not interchangeable. OpenCode publishes client source; Claude Code's official public repository supplies versioned release/plugin/support material, not its proprietary CLI engine. Keeping both declared references makes omissions and release changes visible without pretending equal implementation visibility. Version-matched source, official interface documentation, changelogs and controlled runtime observations answer different questions; disagreements remain explicit rather than being resolved by assumption. Hosted behavior and model internals are not proved by a client clone.

The [eyrsync source table and lifecycle](../.agents/skills/eyrsync/SKILL.md#sources) own coverage and freshness. New references need a concrete dependency and approved destination. The standalone Bash entrypoint delegates structured identity/manifest handling to a Python standard-library helper. GitHub node IDs pin the intended projects across canonical URL moves; `gh` resolves declared and actual origin endpoints to that identity before fetching. Non-forced atomic fetches, guarded fast-forwards and rechecks precede fetch-URL/manifest reconciliation. Explicit push URLs and unrelated configuration survive. Source comments/mode survive atomic manifest replacement, but the clone/manifest pair is not a transaction; failure can leave safe partial progress. Unknown identities, local conflicts or drifting inputs refuse without rollback. Reference maintenance has no neighboring-repository dependency.

GitHub documents [rename redirects](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository), including their loss when an old name is reused, and recommends persisting [global node IDs](https://docs.github.com/en/graphql/guides/using-global-node-ids) for object references. A redirect or shared Git ancestry alone is therefore insufficient identity evidence. The updater never replaces its reviewed ID pins automatically. Pins establish object continuity, not trust in arbitrary new sources or approval to publish.

## Gates

`lint` and `check` are repository checks, `restow` and `verify` host verification. A repository declares its gates through these targets; host-bound targets refuse on the wrong host or clone. The ship skill runs them on the staged state before each commit.

## Standalone deployment

The harness deploys with GNU Stow without directory folding, so managed parents stay real directories and only leaves are links; each skill directory is linked whole into both skill roots so new skill files deploy without a restow. Clone guards and complete selected-skill preflight prevent cleanup or migration from silently taking over another clone or foreign entry. One Make invocation is serialized, not made transactional against disk failure or independent host edits.

EyrAgents owns its configuration, startup requirements, setup and workspace-guide build independently of host dotfiles. Ordinary installed tools and mise are explicit prerequisites. OpenCode's mise fragment provides defaults while preserving caller overrides; no shell-export import or host launcher source is required. Live Stow configuration remains the deployment model. Deployment-affecting changes retain exact other-machine acceptance steps in the ledger until completed there.

Fixtures exercise interfaces under mocks. `make canary` adds up to six live calls per tool, requiring successful nonempty replies and preserving its fixture HEAD. Canary replies are behavior, not independent dispatch proof. Node.js and mise belong to this repository's verification prerequisites.

## The repository is the record

Durable decisions live in `AGENTS.md`, unresolved ones in the maintenance ledger, and provenance in Git history. Native memory can retain useful non-secret preferences, context and learned procedures, but remains a revisable local cache. Consequential facts are checked against their sources; learning becomes shared policy or a maintained workflow only through the appropriate repository. Tool-owned memory and learned skills may evolve automatically, while credentials, managed guidance, access controls and repository-owned skills retain their existing boundaries. Local memory neither travels through Git nor establishes another host's state.

Work that spans several steps or sessions keeps one live plan file in `~/Projects/eyrie/scrape/plans/`, as global guidance's Continuity rule describes: the goal, H's decisions, what remains and the next step, current rather than historical, and deleted once the work ships. Simple tasks need none. It lives outside the repositories, so no ignore entry is needed and cross-repository work has one home.

Plan files survive application restarts but not a change of host. A conditional tracked `docs/handoff.md` supplies the next host's pending actions and acceptance checks, linking canonical procedures. The receiver revalidates its host and repository and deletes or updates the handoff through the normal commit workflow. Neither record transfers approval or host attestation; no empty handoff file or second synchronized state store is needed.

## Effort and models

Each tool's configuration and the reviewer scripts own model choices; the contracts check only the configured `xhigh` effort, and global guidance carries no duplicate flag or override recipe. One owner per choice means a `/model` switch or catalog bump changes one file, not a test and three documents. The policy favors the most capable primary models, with small models for tool-managed lightweight tasks. Moving aliases or catalog defaults follow their provider's selection, whose strongest-model status needs revalidation; concrete IDs carry an update trigger in the ledger. Configured preferences and observed runtime provenance remain distinct.
