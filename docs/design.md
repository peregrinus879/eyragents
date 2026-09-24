# Design

`AGENTS.md` states the invariants. This note gives the reasons, so a reader can judge whether the same shape fits their own setup.

## Intent-led collaboration

H supplies direction, not an exhaustive specification. Global guidance's [Approach](../agents/.agents/global-agents.md#approach) makes broader reasoning an explicit step before choosing a solution: frame the goal and surrounding system, check missing counterparts and assumptions, and consider alternatives and downstream effects. Interpolation fills reasonable gaps; extrapolation tests related cases. The first example or existing configuration is evidence, not the boundary of the problem. This applies across all work, not only access planning or source references.

Broad reasoning does not authorize broad action. Surface useful omissions and material tradeoffs for H, while well-supported low-risk work proceeds within scope. Likewise, a command that relieves one symptom is not a durable fix when the workflow will require it repeatedly; explain that distinction and the underlying remedy. Keep the analysis proportionate rather than adding a mandatory essay or another approval ritual to trivial work.

## Two approval boundaries

The normal trusted-repository workflow has two approval boundaries: H approves one exact staged candidate at a time, then separately approves a fixed ordered set of publication bindings. Individual commit cards preserve focused staged-diff review. One consolidated push summary and one selector cover the listed set, while the agent still invokes `publish-apply ID` and verification separately for each member. Multiple commits on one branch remain separate commits when pushed together. A later failure can leave earlier members published; the set stops, and continuing the unattempted remainder needs fresh approval. Destructive or hard-to-reverse targets retain separate exact-target approval.

Visible briefs are decision-oriented: changes, scope/destination and audience, commit messages where being approved, operational effects, checks and material exceptions. Full IDs, tree/base hashes, raw argv, execution context and detailed evidence remain in the technical records for inspection on request. Short references map unambiguously to full immutable IDs, never a replaceable latest entry. This separates readable presentation from technical verification without hiding failed/skipped checks, partial scans or required inspection. Optional copying is H-triggered and does not approve or verify anything; preparation and re-display leave the clipboard alone. Ordinary authorized edits remain autonomous.

Immutable candidate and publication receipts make those boundaries explicit rather than relying on a replaceable latest record. SHA-256 IDs bind the exact candidate or destination scope, while lifecycle status changes separately. Prepared-index recording preserves mixed hunks; whole-file staging is an explicit `--stage` choice. Apply uses a disposable index with normal hooks and checks the resulting commit. Compensation may compare-and-swap only its uniquely identified created commit back to the recorded sole parent; unexplained branch or checkout movement is preserved for H, never reset. Private permissions and cooperating-operation locks support governance, not same-user isolation. A receipt is neither approval nor evidence that worktree gates tested a different index tree.

Immutability protects a receipt while it is needed, not forever. At workflow close-out, the commit skill previews and disposes of exact selected receipt/status pairs through the locked helper. Publication ancestry is the normal completion evidence. For an explicitly local-only endpoint, a separate `--local-only` disposition validates the actual committed object and retires selected candidate records without a publication claim; the primary checks that no dependent workflow still needs them. Publication records cannot enter that mode. Active and ambiguous recovery records remain protected. H can explicitly accept unverified close-out of eligible publications after the unresolved issue has a canonical disposition. All selected records are checked before transient closing markers are written; payloads precede statuses during resumable deletion, and recovery retains the original disposition. Stable lockfiles remain; no permanent tombstones, age purge or directory sweep is needed.

Publication review covers raw new-commit metadata, explicit per-parent merge patches, the flat diff, and complete newly reachable text. Tip-only or addition-only scans miss merge resolutions and transient disclosures. Unscannable objects remain explicit, digest-bound human-inspection obligations rather than being silently accepted or making ordinary asset work impossible. Normal pre-push hooks remain enabled and fingerprinted for review. Sensitive/identity findings, unsafe hook sources, unsupported options/helpers and missing baselines still refuse. The executor shares its direct argv generator with the technical packet, preserving the configured remote name for tracking/hooks, immutable reviewed SHA, one destination ref, exact-base lease, and tag/submodule/redirect suppression. The common-directory lock spans recheck and push for cooperating operations; it cannot freeze hostile same-user configuration, hook dependencies, DNS or SSH state.

Only a ready publication can execute. File and directory fsync make the pre-spawn `executing` marker durable before a child is launched. The child runs noninteractively in its own process group, with all raw output suppressed and a 300-second push budget. Handled timeout/cancellation stops the group; completed cleanup permits `attempted` status with execution outcome. Failure after launch, including failure to persist a result, may have published. A surviving `executing` marker is conservative lost-result/cleanup evidence, never automatic retry permission or close-out eligibility. Independent endpoint verification can promote an `attempted` record to `verified` while retaining even a failed execution result. Drift preserves attempted evidence; observing an executing record cannot resolve its process cleanup. `publish-verify` may also execute trusted-worktree make/npm targets. Remote observation, local tracking, CI and deployment remain separate facts.

Authentication is host-owned: GitHub normally uses HTTPS and the standard `gh` helper, configured through each host's untracked Git include. H controls login, storage choices and recovery. Existing SSH support retains normal host configuration and inherited `SSH_AUTH_SOCK`; the executor preserves whichever reviewed transport is bound. Readiness is distinct from H's exact publication approval. Credential access is not read-only isolation, and client noninteractive flags do not suppress an independent provider's recovery UI. Process-group cleanup does not attest provider-dialog cleanup. Native execution authority must be arranged before an attempt exists. No broker, nested-client workaround or permission override is provided; the maintenance ledger owns version revalidation.

## Enforce, then instruct

Rules live at the lowest layer that can hold them. A sandbox constrains the surfaces it actually covers; a permission rule reaches only the subjects its tool checks; hooks see only dispatched calls. Scripts make a procedure repeatable across models and testable in CI; prose states intent and covers what lower layers cannot express. The commit gate rejects parsed commit-producing shell forms and ambiguous ff-only exemptions, but is not containment of arbitrary scripts or hostile repository configuration. The skill owns approval procedure, which a shell hook cannot observe.

## One trust model, two enforcement points

The [access policy](access.md) makes that distinction inspectable across tools: one outcome table for both, enforcement limits, implementation references and official semantics. It is the comparison owner, not another source of permission grants. `/eyrsync` reconciles intent, the access policy, implementation, upstream behavior and evidence together. Parity means equivalent authorized work and safety intent where enforceable, not weakening a stricter tool until the tables look identical.

The tools enforce the same intent to different depths. Claude Code combines deterministic rules with an auto-mode classifier; OpenCode has only static rules, so it asks where Claude Code's classifier would review. Both allow what does not expose H and gate the rest: secrets and personal folders are denied, and remote, destructive or configuration-changing commands ask. Neither is shell containment. The [access policy](access.md) owns the rules and their limits.

Reads are broad and secrets are denied by one finite inventory in both tools, so ordinary configuration, package metadata and diagnostics stay readable. A finite inventory cannot recognize a renamed secret; global guidance still binds there.

Persistent scratch (`~/Projects/eyrie/scrape`) is writable in both tools; OpenCode also writes its session scratch under `/tmp/opencode`. Persistent work there is preserved project work, not disposable by location.

## Independent review

A second opinion is worth most from a fresh context, and more from a different model family. Every reviewer, in-tool or cross-vendor, follows one [charter](../agents/.agents/agents/auditor.md): full context, a top-down review from goal and approach to presentation against global guidance, and read-only conduct. Reviewers have read, search, shell and web tools without edit tools, under the primary's rules, so they verify claims instead of trusting a curated brief. The drafter states what it already did, and the reviewer spends its effort on what was not covered. The bridges run the other tool's client under H's normal settings with the same reviewer tools, Claude Code by tool list and OpenCode through its `auditor` agent, with a hard timeout; a reply without the charter's verdict line fails. Review is recommended where it earns its cost, never mandatory.

Retained requests and replies belong to a workstream's `spar/` (cross-vendor) or `audit/` (in-tool) directory; the primary writes them, never a reviewer.

## One neutral source

Guidance and skills live once, under `~/.agents`, the home of the Agent Skills format. Both tools use native global-instruction symlinks to neutral `global-agents.md`: Claude Code's `CLAUDE.md` and OpenCode's `~/.config/opencode/AGENTS.md`. OpenCode does not append the same guidance through explicit `instructions`, so it loads once. Both tools read a project's `AGENTS.md` natively, so repositories carry no `CLAUDE.md` import. The guidance file avoids the name `AGENTS.md` because both tools also auto-load `AGENTS.md` files from subdirectories they read. Skill executables stay in each skill's standard `scripts/` directory; tool-specific discovery adapters do not transfer ownership out of EyrAgents.

## Configuration Ownership

The package directories mirror deployed paths, but not every managed endpoint is a leaf symlink:

| Component | Ownership and deployment |
| --- | --- |
| Global guidance and skills | `agents/.agents/` is canonical. Each skill directory is linked whole, so new skill files deploy without a restow; each client uses its native adapter. |
| Claude Code | `claude-code/.claude/` supplies linked instructions, settings, skills, auditor, and status line. |
| OpenCode | `opencode/.config/opencode/` supplies linked instructions, configuration, commands and the commit-gate plugin; its mise fragment supplies startup defaults. |
| Commit gate | `templates/hooks/commit-gate` is copied to a checked regular file at `~/.agents/hooks/commit-gate`, outside editable workspaces. |
| Project instructions | Root `AGENTS.md` and `.agents/skills/eyrsync/` apply to this repository; they are not global Stow payloads. |

Client-owned identity, learning, and session state remain outside the source packages. Credentials and schedules retain their separate authorization boundaries; a package does not install accounts or recurring jobs.

## Documentation Ownership

The README is the overview and navigation entry point. [Setup](setup.md) owns installation, deployment, migration, and adaptation; [operations](operations.md) owns daily use and verification. This guide explains architecture and rationale; [access](access.md) owns the security comparison and restricted launches. Skills own executable workflow procedures, `AGENTS.md` owns agent invariants, and the [maintenance ledger](maintenance.md) holds only unresolved work and live revalidation evidence. Link to those owners instead of copying their detailed procedures into the README.

The [workspace guide](workspace-guide.html) has one authoring/build owner here because the development workflow spans host applications and AI clients. Its [maintenance contract](workspace-guide-src/README.md) keeps host facts with EyrArcHy/EyrWSL configuration work and `/omasync`, and client facts with EyrAgents and `/eyrsync`. Both host profiles and all client controls are embedded in one offline file. EyrArcHy and EyrWSL retain their implementation-twin contract; EyrAgents remains independent. Cross-repository fact review creates a documentation companion when relevant, while building or deploying any repository uses its own sources.

## Reference coverage

The same maintenance questions apply to every tool, but their evidence is not interchangeable. OpenCode publishes client source; Claude Code's official public repository supplies versioned release/plugin/support material, not its proprietary CLI engine. Keeping both declared references makes omissions and release changes visible without pretending equal implementation visibility. Version-matched source, official interface documentation, changelogs and controlled runtime observations answer different questions; disagreements remain explicit rather than being resolved by assumption. Hosted behavior and model internals are not proved by a client clone.

The [eyrsync source table and lifecycle](../.agents/skills/eyrsync/SKILL.md#sources) own coverage and freshness. New references need a concrete dependency and approved destination. The standalone Bash entrypoint delegates structured identity/manifest handling to a Python standard-library helper. GitHub node IDs pin the intended projects across canonical URL moves; `gh` resolves declared and actual origin endpoints to that identity before fetching. Non-forced atomic fetches, guarded fast-forwards and rechecks precede fetch-URL/manifest reconciliation. Explicit push URLs and unrelated configuration survive. Source comments/mode survive atomic manifest replacement, but the clone/manifest pair is not a transaction; failure can leave safe partial progress. Unknown identities, local conflicts or drifting inputs refuse without rollback. Reference maintenance has no neighboring-repository dependency.

GitHub documents [rename redirects](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository), including their loss when an old name is reused, and recommends persisting [global node IDs](https://docs.github.com/en/graphql/guides/using-global-node-ids) for object references. A redirect or shared Git ancestry alone is therefore insufficient identity evidence. The updater never replaces its reviewed ID pins automatically. Pins establish object continuity, not trust in arbitrary new sources or approval to publish.

## The gate contract

Develop, commit and publish share one [verification contract](../agents/.agents/skills/develop/references/verification.md): `lint` and `check` are repository checks, `restow` and `verify` host verification, and `verify-published` the post-push check. A repository declares gates through its targets; host-bound targets refuse on the wrong host or clone. Develop establishes implementation evidence, commit checks the exact staged candidate, and publish checks the reviewed publication. Valid evidence is reused only for unchanged tested contents and context.

## Standalone deployment

The harness deploys with GNU Stow without directory folding, so managed parents stay real directories and only leaves are links; each skill directory is linked whole so new skill files deploy without a restow. Clone guards and complete selected-skill preflight prevent cleanup or migration from silently taking over another clone or foreign entry. The installed commit gate has one fixed canonical endpoint outside Git workspaces, `~/.agents/hooks/commit-gate`: linked/folded parents, endpoint symlinks/hardlinks, and relocation through `GATE` refuse before installation. A real file under a folded parent would still expose the supposedly external hook through the workspace. One Make invocation is serialized, not made transactional against disk failure or independent host edits.

EyrAgents owns its configuration, startup requirements, setup and workspace-guide build independently of host dotfiles. Ordinary installed tools and mise are explicit prerequisites. OpenCode's mise fragment provides defaults while preserving caller overrides; no shell-export import or host launcher source is required. Live Stow configuration remains the deployment model. Deployment-affecting changes retain exact other-machine acceptance steps in the ledger until completed there.

Fixtures exercise interfaces under mocks. `make canary` adds up to six live calls per tool, requiring successful nonempty replies and preserving its fixture HEAD. Canary replies are behavior, not independent dispatch proof. Node.js and mise belong to this repository's verification prerequisites.

## The repository is the record

Durable decisions live in `AGENTS.md`, unresolved ones in the maintenance ledger, and provenance in Git history. Native memory can retain useful non-secret preferences, context and learned procedures, but remains a revisable local cache. Consequential facts are checked against their sources; learning becomes shared policy or a maintained workflow only through the appropriate repository. Tool-owned memory and learned skills may evolve automatically, while credentials, managed guidance, access controls and repository-owned skills retain their existing boundaries. Local memory neither travels through Git nor establishes another host's state.

Develop owns the [workstream memory contract](../agents/.agents/skills/develop/references/workstream.md). The primary keeps compact current state and links full drafts/evidence at their owners, saving material decisions before dependent actions rather than documenting every turn. Atomic planning precedes substantial implementation/delegation. The same workstream continues through commit and publish, with independent candidate verification and dependency-aware cleanup. Simple tasks need no scaffold. User/unknown files and governance receipts retain their own boundaries; no completed-work archive or background state daemon is introduced.

Repo-local ignored state survives application restarts but not push/pull. A conditional tracked `docs/handoff.md` supplies the next host's pending actions and acceptance checks, linking canonical procedures. The receiver revalidates its host and repository and deletes or updates the handoff through the normal commit workflow. Neither record transfers approval or host attestation; no empty handoff file or second synchronized state store is needed.

## Effort and models

Each tool's configuration and the reviewer scripts own model choices; the contracts check only the configured `xhigh` effort, and global guidance carries no duplicate flag or override recipe. One owner per choice means a `/model` switch or catalog bump changes one file, not a test and three documents. The policy favors the most capable primary models, with small models for tool-managed lightweight tasks. Moving aliases or catalog defaults follow their provider's selection, whose strongest-model status needs revalidation; concrete IDs carry an update trigger in the ledger. Configured preferences and observed runtime provenance remain distinct.
