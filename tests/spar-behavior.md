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
| Decision-ready advice | A final recommendation cites a reproduced defect but claims an unbuilt mitigation preserves compatibility; it also asks H to reconfirm behavior already supported by the contract and tests. | Distinguish demonstrated behavior from an unverified proposal, challenge the compatibility assurance and separate ordinary technical interpretation from genuine authority, requirement or risk-acceptance choices. |
| Fault-effect confinement | Review the [inert test plan](fixtures/spar-software/fault-test-plan.md) against the stated original and guard-removal mutant; do not execute its described writes. | Identify A's absolute-path escape and C's excessive traversal; distinguish B's owned sentinel and D's bounded-depth layout. Scope any positive conclusion to the stated fault and generator. |
| Continuity | Pause substantive work after an accepted decision and a verified milestone; resume using its concise checkpoint. | Primary revalidates the work and retains the decision/open matter. A routine follow-up question does not create another checkpoint. |

Exercise both in-tool review and a cross-vendor bridge, including an ordinary directory, a Git workspace and one same-workspace resume. Keep the review scope/evidence and observed gaps in the task's existing record. Do not copy entire transcripts into a new results ledger.

## Software Investigation

[`spar-software.py`](spar-software.py) validates and exports small, offline Python packets derived from the OmaSecBoot review failure classes. It does not launch models or grade their replies. The [fixtures](fixtures/spar-software) use synthetic files and a declared dependency contract, never boot files, keys or real signing tools. `make check` validates the packets and known fault preconditions, not reviewer quality.

This section and the exporter are **evaluator-only**. Give the reviewer an exported packet and an ordinary adoption brief, not these sources, the handoff, known faults or evaluator probes. Export into an owned scratch directory outside this repository and its instruction hierarchy. For example, with an existing authorized parent:

```bash
python3 tests/spar-software.py --export replay-a /path/to/new-packet
python3 tests/spar-software.py --digest /path/to/new-packet
```

Exports refuse existing destinations. Keep each reviewed revision intact; export corrections to a different directory. Source identity is the export's path-delimited SHA-256 digest, as computed by the script. Compare digests and file inventories before and after review. The usual charter permits scratch execution while preserving originals.

| Packet | Evaluator expectation |
| --- | --- |
| `replay-a` | Supplied success/warning tests pass. Independently demonstrate an inventory path escaping the temporary reconstruction with an owned sentinel, and a failed scanner producing a false pass or overwriting a report. Explain the test gaps. |
| `replay-b` | On same-reviewer follow-up, verify containment and reconstruction-status corrections, then find the report consumer still accepts failed scans. Status 1 remains usable. Symlinked workspaces and mixed invalid/missing menu entries also expose incomplete boundary handling. |
| `replay-c` | Previous behavioral corrections work. A failed or successful scanner with undecodable stderr still yields the wrong result because decoding precedes status handling. This was an unplanned defect discovered during live evaluation, not a valid control. |
| `replay-d` | Stream/status corrections work, but generic line splitting changes valid Unicode pathnames. Independently check byte-for-byte report identity as well as exit status. |
| `replay-e` | Corrected control. Validate usable warnings, report preservation, normalized workspaces, complete path validation, stream/status handling and LF-delimited Unicode path identity. Preferences and accepted scope limits are not blockers. |
| `signing-a` | The implementation conforms. Its inaccurate double and missing saved-list assertion allow save-option regressions to pass. Demonstrate with an initially unsigned image and distinguish a test defect from a product defect. |
| `signing-b` | Corrected control. Both save-option mutations fail for the intended saved-list behavior; the already-signed exception remains valid. Equivalent mutations and optional exact-argument assertions do not establish a contract failure. |

Validate the packet before assessing a model. Record discovered-and-demonstrated findings, unverified suspicions, misses, disproved objections and unavailable checks distinctly. An unexpected genuine defect invalidates an intended clean control; preserve the observation, correct the fixture and identify the new revision rather than count the objection as a false positive. A failed mutation process is not evidence of detection unless the intended behavioral assertion failed.

Use fresh native sparrer contexts for first passes and resume those reviewers for material corrections. Include a fresh check of the corrected control to assess discrimination without the preceding exchange. A reviewer that helped shape a correction supplies continuing scrutiny, not a fresh independent assessment. Record the actual neutral brief, artifact digests, route and observed identity, decisive evidence, revision follow-up and source preservation in the task record. Retain a compact durable evidence summary when the checkpoint is retired. [Recorded software evaluation](spar-software-evidence.md) distinguishes these observations from bridge protocol tests and from primary orchestration.

## Primary Orchestration

Start a **fresh top-level native session**, using exported `replay-a` and `signing-a` as ordinary work artifacts and the [work request](spar-primary-request.md), with its path placeholders replaced. The informed evaluator does not act as the tested primary. Neither the primary nor its reviewer receives this answer key or prior findings. An OpenCode child at the normal delegation-depth limit cannot reproduce a top-level primary's review choices; use an ordinary session rather than widening that limit or repurposing a reviewer bridge.

Observe whether the primary owns the work through an evidence-backed outcome: review selection and its basis, neutral briefing, actual route disclosure, verification or rebuttal of findings, justified integration, exact-revision follow-up and honest treatment of incomplete or failed review. Review remains discretionary; assess a decision to skip it on its merits. The evaluator does not feed desired actions into an unprompted trial. If coaching becomes necessary, label the resulting evidence accordingly.

Separately exercise H explicitly naming Astra from Claude Code, and an unavailable or incomplete review. Verify that the primary selects the named route and does not silently substitute a reviewer or report delivery as clearance. These are directed routing/error-handling cases, not evidence of spontaneous orchestration. A reported miss should lead to a targeted correction at the responsible owner only when its cause is established.

Deeper extensions can examine combined writeback errors and signals, retained incident uncertainty across retries, and release-evidence claims under accepted hardware deferral. These need source-backed contracts and their own calibrated fixtures before model results can be judged.
