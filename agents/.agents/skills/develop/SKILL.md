---
name: develop
description: Take substantive work from goal clarification through planning, execution and verification, preserving essential state for resumption. Use when starting or resuming implementation, research, planning or review; hand verified repository changes to commit when appropriate.
---

# Develop

Own delivery from H's intent to a verified result. Global guidance owns professional standards and authority; this skill coordinates the work. A clear task needs efficient execution, not a compulsory brainstorming ceremony.

## Start Or Resume

- Establish the outcome, constraints and mode: discussion, research, plan, audit or implementation. Test consequential assumptions and suggest better approaches when they can improve the outcome. Resolve material uncertainty or changes to scope, effort, complexity, risk or agreed capabilities with H before proceeding.
- On resume or compaction, read the active [workstream state](references/workstream.md), its necessary artifacts and actual repository state before acting. Continue at the current step; preserve unrelated work and investigate material drift.
- Use relevant project instructions and specialist skills. When diagnosing third-party software, check upstream issue trackers and release notes.

## Plan And Execute

- Before substantial implementation or delegation, record independently valid atomic changes and commit boundaries where applicable. Include repository/file or hunk scope, ownership, dependencies and verification. Keep coupled code, configuration, tests and documentation together; plan companion changes across repositories when genuinely required. Update the map as findings or H's direction change it.
- Seek plan approval when H requests it or before hard-to-reverse work. Otherwise resolve the material decision directly and proceed within scope. Plan-only and audit-only work leave source and Git state unchanged; only the primary may maintain permitted workstream notes.
- Before long or unattended work, identify work/reference/scratch roots and resolve foreseeable access needs. Record blockers and continue independent authorized work where possible; otherwise pause. A skill or checkpoint supplies no new permission.
- Delegate bounded work with explicit ownership when useful; the primary retains synthesis and decisions. Use the available explorer/planner for appropriate bounded tasks and the read-only `auditor` or `spar` for valuable independent review. Review is recommended before consequential plan approval and after implementation, never mandatory; reviewer agreement authorizes no action.
- Verify throughout the work using the [verification contract](references/verification.md). Revisit the affected plan or implementation when evidence warrants it; do not restart the whole process for a local correction.
- Follow sound project conventions and flag weak ones. Discuss material tooling changes with H; add no formatter or linter without H's direction.

## Finish And Handoff

Before declaring implementation complete, achieve the agreed outcome, verify the deliverable, update affected documentation, reconcile the atomic map and account for remaining artifacts. Keep failures, skipped checks and pending host work explicit. Apply the workstream's automatic cleanup rules.

Research, discussion, audit, plan-only and no-change work can finish without Git preparation. An explicit pause instruction needs no preparation question. For verified implementation with intended uncommitted changes, check H's existing direction. A clear request to prepare commits, commit, finish the Git workflow or publish, a clear yes to preparation, or `Commit and resume` means proceed to the relevant Git skill without another preparation question. A vague acknowledgment is not that direction.

Otherwise present a concise outcome/change/verification summary, immediately followed by one **Next step** selector:

1. **Prepare commit reviews**: hand the existing map and evidence to `commit` for preflight, remaining gates, staging and individual candidate reviews.
2. **Pause here**: leave implementation uncommitted and the index untouched; retain only the compact state/artifacts needed for a concrete resumption and remove the rest.

Use the native selection tool when available, otherwise the same choices in chat. Ask once per completed workstream, not per repository or on resume when direction is clear. Preparation is not approval of a commit, publication or broader scope. `commit` and `publish` retain their exact approval boundaries and reuse the same workstream. Candidate-check defects return to targeted development and verification.
