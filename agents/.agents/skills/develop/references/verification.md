# Verification Contract

Define acceptance checks during planning, use targeted checks while working, and verify the delivered result before completion. State what the evidence establishes. Fix in-scope failures and report external blockers and failed, skipped or unverified checks.

## Repository And Host Gates

A clear implementation request authorizes the repository's prescribed gates, including guarded deployment/reconciliation and their managed link changes under HOME. Read-only reviewer calls inside the trusted repository are also permitted. This does not authorize unrelated host changes, credential inspection or bypassing native restrictions.

Run `make lint` and `make check` when defined, else `npm run check`; then `make restow` and `make verify` when defined, else `npm run verify`. Elsewhere use documented checks. Combine compatible Make targets in one invocation to avoid repeating prerequisites. Rerun affected checks after fixes. Wrong-host or wrong-clone refusals are explicit skips with their reason, never bypassed. Verify deployed state after deployment; an earlier host pass does not cover changed links or configuration. Use reviewed opaque host checks rather than dumping potentially credential-bearing configuration.

## Evidence And Reuse

Record actual commands/results, source or candidate identity and relevant runtime/host inputs in the checkpoint. Keep detailed evidence as a linked artifact when needed. Configuration inspection, source inspection, synthetic tests, native dispatch and model-reported behavior are different evidence levels.

Reuse same-workstream results only after re-reading the original passing evidence and establishing that its exact tested contents and relevant inputs/context are unchanged. A receipt or tracked-file equality alone is insufficient. Unknown inputs, untracked contents, unverified symlink targets or source changes forbid reuse. Recheck at handoff rather than rerunning merely because the conversation changed turns.

Commit preparation must establish coverage of the exact staged candidate. A different working tree is not a superset or attestation of the index. Validate the staged snapshot in an appropriate disposable context without deploying it, or defer a mixed candidate. Coordinated repository changes need the exact final pair, not a check against an earlier peer.

Publication keeps endpoint, tracking, CI and deployment verification distinct under its own skill. Pending or unknown results do not establish success, and reviewer agreement supplies no authority.
