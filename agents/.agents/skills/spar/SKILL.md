---
name: spar
description: Independent review of a plan, diff or decision, from concepts to details, by the in-tool auditor or a cross-vendor reviewer. Use at your discretion before a plan goes to H, after implementation, or wherever outside review could change the outcome.
---

# Spar

The session's model drafts; an independent reviewer challenges the work from a fresh context. Every reviewer follows the shared charter in `~/.agents/agents/auditor.md`: full context, read-only, global guidance as the standard. H rules on what stays open.

## When

At your discretion, whenever outside review can change the outcome, such as before a plan goes to H or after implementation before the cards; it is never mandatory. One review with at most one follow-up round is the default.

## Reviewer

- **In-tool** (default): the `auditor` agent.
- **Cross-vendor**, when a view from another model family is worth its extra time, such as for a consequential or security-relevant decision: from Claude Code, `~/.agents/skills/spar/scripts/spar-opencode`; from OpenCode, `~/.agents/skills/spar/scripts/spar-claude`. Each bridge runs the other tool's `auditor` agent.

H's named reviewer overrides this choice. Report which reviewer ran; an in-tool audit is never cross-vendor review.

## Request

Write the request so the reviewer starts where you stopped:

- what to review: paths, a diff range, a plan file or a decision;
- the goal, the constraints and where the decision record lives;
- what you already did: commands run with their results and sources checked.

Withhold your conclusions, the alternatives you weighed and your findings until the reviewer's first pass, so it judges the work on its own terms; share them in a follow-up round when useful. The reviewer reuses your evidence where it suffices and gathers everything else itself. Never narrow the scope to make a round pass.

## Run

Bridges run the other client under H's normal settings, which load project configuration, so use them only in trusted checkouts; in an untrusted checkout, use the in-tool auditor of the restricted session. Run `<bridge> review "<request>"` from inside the repository, plainly, with a shell timeout of at least the bridge's 1800 seconds. The reply arrives on stdout. Stderr carries `SPAR-BRIDGE ID:`; a follow-up round uses `<bridge> review --resume <id> "<request>"`. Exit 3 is a usage limit, 124 a timeout and 5 a reviewer failure; report them to H.

## Findings

Verify each blocking finding's ground, including how it fails. Fix confirmed issues, rebut disputed ones with evidence, and ask for the ground when one is missing. Relay objections in substance; never soften or drop them. Record each blocking finding with its disposition in the plan file: implemented, declined with the rationale shown to H, or open for H's ruling. Non-blocking findings are optional suggestions: present them as one list, which H closes with one disposition. For each open item, present the decision, both positions with evidence, and your recommendation labeled as judgment. A review authorizes nothing by itself.
