---
name: spar
description: Independent review of a plan, diff or decision, from concepts to details, by the in-tool auditor or a cross-vendor reviewer.
---

# Spar

The session's model drafts; an independent reviewer challenges the work from a fresh context. Every reviewer follows the shared charter in `~/.agents/agents/auditor.md`: full context, read-only, shared guidance as the standard. H rules on what stays open.

## When

Review before a plan goes to H for approval, after implementation before the commit card, and wherever outside review can change the outcome. It is never mandatory. One review with at most one follow-up round is the default.

## Reviewer

- **Cross-vendor**, for an independent view from another model family: from Claude Code, `~/.agents/skills/spar/scripts/spar-opencode`; from OpenCode, `~/.agents/skills/spar/scripts/spar-claude`.
- **In-tool**: the `auditor` agent, when a same-tool follow-up is more useful or the other vendor is unavailable.

H's named reviewer overrides this choice. Report which reviewer ran; an in-tool audit is never cross-vendor review.

## Request

Write the request so the reviewer starts where you stopped:

- what to review: paths, a diff range, a plan file or a decision;
- the goal, the constraints and where the decision record lives;
- what you already did: commands run with their results, sources checked, alternatives weighed and findings so far.

The reviewer tests these as claims and gathers everything else itself. Never narrow the scope to make a round pass.

## Run

Bridges run the other client under H's normal settings, which load project configuration, so use them only in trusted checkouts; in an untrusted checkout, use the in-tool auditor of the restricted session. Run `<bridge> review "<request>"` from inside the repository, plainly, with a shell timeout of at least the bridge's 1800 seconds. The reply arrives on stdout. Stderr carries `SPAR-BRIDGE ID:`; a follow-up round uses `<bridge> review --resume <id> "<request>"`. Exit 3 is a usage limit, 124 a timeout and 5 a reviewer failure; report them to H.

## Findings

Verify each finding's ground. Fix confirmed issues, rebut disputed ones with evidence, and ask for the ground when one is missing. Relay objections in substance; never soften or drop them. Record each finding in the workstream register with its disposition: implemented, declined with the rationale shown to H, or open for H's ruling. For each open item, present the decision, both positions with evidence, and your recommendation labeled as judgment. A review authorizes nothing by itself.

Keep requests and replies that later steps need under `.eyr-plans/<workstream>/spar/` (cross-vendor) or `audit/` (in-tool), following the [workstream contract](../develop/references/workstream.md), and remove them once no step needs them.
