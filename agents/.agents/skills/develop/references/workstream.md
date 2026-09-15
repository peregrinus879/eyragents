# Workstream Memory

Keep the minimum current state needed to resume, verify or finish the work. This is temporary task memory, not an activity log. Simple tasks and standalone audits need no empty checkpoint or directory scaffolding.

## Store

Use one private, owned, gitignored `.eyr-plans/<workstream>/` with real parents. Verify exclusion with `git check-ignore` before writing; never stage its contents. `governance` is reserved for separate approval records. Implementation may add `/.eyr-plans/` to the root ignore file; plan/audit-only work may not. If exclusion or native access is unavailable, use authorized private execution scratch and report the limitation, without bypassing permissions.

The primary owns the checkpoint and review artifacts. Reviewers return findings and never write these files. Keep in-tool audit material under `audit/`, cross-vendor material under `spar/`, and create those directories only when needed. Keep a full working draft or detailed evidence in its own artifact; link it rather than copying it into the checkpoint.

Use only the fields the task needs:

- **Outcome and scope:** goal, constraints, current mode, repositories and relevant host/access limits.
- **Plan and state:** current revisions, relevant uncommitted work, remaining atomic changes, file/hunk ownership, dependencies and verification. Include companion changes where required.
- **Decisions:** current material choices, brief necessary rationale, important failed approaches and unresolved questions. Local feedback does not automatically become global policy or personal memory.
- **Evidence and artifacts:** pointers to the exact working draft, checked state/results and any still-needed review or execution material.
- **Next action:** what resumes next, blockers and what must be resolved or verified before proceeding.

## Save And Resume

State the checkpoint path when work starts. Save material decisions before dependent actions, after meaningful milestones, and before long operations, pauses or handoffs. Update the affected state; do not append a transcript or routinely rewrite unchanged sections. Keep committed work summarized only as needed by remaining steps.

On resume, compaction or handoff, re-read the checkpoint and required artifacts, inspect actual Git/work state and reconcile drift. If the path is lost, discover active `.eyr-plans/*/checkpoint.md` files in the scoped repositories; ask only when selection or scope is materially ambiguous. Re-read any input the next step depends on. A checkpoint transfers neither commit/publication approval nor host attestation. No save can preserve a decision lost before it was written.

## Execution Scratch And Cleanup

H authorizes session-owned files under `/tmp` or `$TMPDIR` for this workflow, subject to shared protected-material and native-permission rules. Use one caller-owned private execution root with named subdirectories; OpenCode uses a unique child of `/tmp/opencode`. State its path. Disposable tests use fake HOME/XDG/history (`HISTFILE=/dev/null`) and bounded cleanup of their own processes. Actual-host deployment/verification keeps the real target context. Reuse maintained helpers.

Automatically remove workflow-owned scratch once its useful results are retained and no step needs it. Retain checkpoint/draft/evidence only for active work, a concrete pause, pending commit/publication/CI or recovery. Use the same state through those workflows. When its final dependency ends, remove the owned files and empty directories without an extra routine approval question. Promote lasting rules and unresolved issues to their canonical owners first; a generic deferred issue does not justify a completed-work archive.

Preserve user/unknown files, other sessions' artifacts, reference clones, persistent project work and approved retention commitments. A pathname under `~/Projects/scratch/` does not make its contents disposable. Governance receipts use the commit skill's exact-ID close-out, never a directory or age sweep. Report anything retained with its concrete next use and removal condition.

## Cross-Host Handoff

Ignored state survives app restarts but does not travel through Git. Create tracked `docs/handoff.md` only for concrete work remaining on another host: direction, baseline/dependencies, pending actions, acceptance checks and blockers, with links to canonical procedures. Include no credentials, transcripts or local approval records. The receiver verifies host/Git state, then deletes or updates it in the normal approved completion change. Keep no empty or completed handoff template.
