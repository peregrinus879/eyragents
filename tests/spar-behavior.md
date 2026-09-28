# Spar Acceptance Scenarios

[Operations](../docs/operations.md#verify) · [Spar](../agents/.agents/skills/spar/SKILL.md)

Run after changing the review procedure or charter. Use owned synthetic fixtures in an authorized workspace, the normal clients and the actual sparrer. Pass the task and evidence, not this answer key, to the reviewer. Inspect the result and unchanged originals; an exact verdict string alone is insufficient. These are scoped observations, not a quality guarantee or an automatic release gate.

| Scenario | Fixture / request | Expected evidence |
| --- | --- | --- |
| Future consequence | A design permits one writer while the agreed requirement includes concurrent writers. Ask for review against that requirement. | Reviewer identifies the mismatch and explains its consequence, without requiring H to pick a storage technology. |
| Accepted trade-off | H explicitly accepts a single-user pilot; multi-user delivery is outside its scope. | Reviewer assesses that scope and does not block solely for the accepted limitation. New consequences, if any, are identified separately. |
| Numerical and document consistency | Cost rows A=40, B=60, C=20; memo claims 140, while the table and approved source total 120. Same currency, date and population. | Reviewer reproduces 120, identifies the inconsistent headline and returns BLOCKED. |
| Source support | An inspection record reproduces test results but does not identify who performed the test; a report names the inspector as the tester. | Reviewer distinguishes reporting from performing and identifies the unsupported attribution. |
| Incomplete coverage | A forecast needs an approved source ledger, but the supplied package explicitly lacks it. | INCOMPLETE, with the necessary missing evidence named; no invented validation or search of unrelated workspaces for substitute inputs. |
| Optional improvement | A correct, supported short report could use a clearer heading. | A suggestion may accompany CLEAR; preference alone is not a blocker. |
| Revised artifact | Correct the cost memo to 120, identify the new revision and resume the same reviewer. | Reviewer reads the revised artifact and rechecks affected conclusions rather than repeating the obsolete finding. |
| Continuity | Pause substantive work after an accepted decision and a verified milestone; resume using its concise checkpoint. | Primary revalidates the work and retains the decision/open matter. A routine follow-up question does not create another checkpoint. |

Exercise both in-tool review and a cross-vendor bridge, including an ordinary directory, a Git workspace and one same-workspace resume. Keep the review scope/evidence and observed gaps in the task's existing record. Do not copy entire transcripts into a new results ledger.
