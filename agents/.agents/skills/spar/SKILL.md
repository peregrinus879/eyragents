---
name: spar
description: Independent review of code, plans, decisions and professional deliverables by the sparrer, in-tool or cross-vendor. Use when a second opinion could change a consequential judgment.
---

# Spar

The primary owns the work and its integration; the sparrer independently investigates and challenges it under the [shared charter](../../agents/sparrer.md). Use review where it can change a consequential judgment, including before committing to an approach. It is discretionary, not a gate on every task.

## Reviewer

- **In-tool** (default): invoke `sparrer` through this skill. Resume the same reviewer for follow-up: message its agent in Claude Code or pass its `task_id` in OpenCode.
- **Cross-vendor**, when a view from another model family is worth its extra time, such as for a consequential or security-relevant decision: from Claude Code, `~/.agents/skills/spar/scripts/spar-opencode`; from OpenCode, `~/.agents/skills/spar/scripts/spar-claude`. Each bridge runs the other tool's `sparrer` agent.

H's named reviewer overrides this choice. Report which reviewer ran. Model-family diversity can help; it does not replace independent evidence and methods.

## Brief

Put the brief in the request, using existing records rather than creating another form:

- intended outcome, audience and acceptance conditions;
- H's settled decisions, constraints and material assumptions, distinguished from proposed technical choices;
- the exact artifacts and revisions to review, governing sources and where to find the evidence;
- checks already performed, their results and known limits.

Preserve H's meaning. Withhold your preferred conclusion, advocacy and findings on the first pass, not the factual context or settled decisions. The reviewer can gather its own evidence and challenge the whole system the work touches. Use [review methods](references/review-methods.md) where helpful. Each tool's private scratch is inaccessible to the other; pass needed evidence inline or through an authorized shared location.

## Run

Bridges load the other client's normal settings and project configuration. Use them only in trusted workspaces; for untrusted material use the in-tool sparrer in a restricted session. Run `<bridge> review "<request>"` from the repository or ordinary working directory. The bridge uses the Git root when present, otherwise the physical working directory. Its configurable `SPAR_BRIDGE_TIMEOUT` defaults to 1800 seconds; the calling tool's timeout must allow at least that long.

The reply is on stdout; stderr reports the workspace and `SPAR-BRIDGE ID:`. Pass that whole handle to `<bridge> review --resume <handle> "<request>"` from the same workspace. It binds the native session to the tool and workspace, not to an artifact revision; name changed artifacts in the follow-up. Exit 0 means a valid review arrived, including BLOCKED or INCOMPLETE, not approval. Exit 3 is a usage limit, 124 a timeout and 5 a reviewer failure. Report failures without substituting a different reviewer silently.

## Resolve

Verify consequential findings and proposed corrections. Integrate justified changes, rebut unsupported objections with evidence and resolve ordinary technical suggestions yourself. Preserve material disagreements and dispositions in the existing task record; global guidance owns whether a checkpoint is needed. Bring H only unresolved choices that need H's priorities, authority or judgment, with the evidence and your recommendation. A primary's decision to proceed does not rewrite the reviewer's result or authorize issue, publication or other external action.

After the independent pass, exchange rationale, alternatives and evidence freely. Resume when a material amendment, new evidence or a resolvable question warrants another pass; identify what changed and recheck affected conclusions. Stop when resolved, when necessary evidence is unavailable or when further discussion repeats positions. Do not review-shop for agreement or narrow the scope to obtain CLEAR. If the reviewer helped shape the solution, later rounds are continuing scrutiny; use a fresh targeted check only when the consequences justify it. Arrange focused specialist checks through the primary when useful.
