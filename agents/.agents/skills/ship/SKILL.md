---
name: ship
description: Commit verified work and publish it; every card of a round in the chat, then one native prompt for the round.
---

# Ship

H approves each round of commits, and each round of pushes, at one native permission prompt with every card directly above it. H sees reply text, not the agent's reasoning, and chat text written after a prompt may not show before the next one, so the cards go into one reply message and the round has a single prompt.

## Commit

1. Make one commit per independent change, with its tests and documentation. Stage only its paths, never `git add -A` or `git add .`, and keep credential-shaped paths out.
2. Check that `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` both show the GitHub no-reply address; if not, stop and tell H.
3. Build the round's commits in order. For each, stage its paths, run the repository's gates with the index equal to the working tree, so they test exactly what the commit holds, and record the staged tree with `git write-tree`. Report any failure; never commit around it. Commits in one repository must touch separate files; a change to a file that an earlier commit of the round also changes waits for a round in a later turn.
4. Write every card of the round into one reply message: repository and branch, what changed and why, files and size, the full message, gate results, and any review verdict or open finding.
5. Directly after the cards, run one command that makes the round, chained with `&&` so a failure stops the rest: in each repository, `git -C <repo> commit -F <message file> -- <paths>` for every commit but the last, which takes only those files, then `git -C <repo> commit -F <message file>`. Keep the message files in scratch, so the prompt stays short and the cards stay in view. Then confirm that each commit's tree (`git rev-parse <commit>^{tree}`) equals its recorded tree and that `git log --format='%an <%ae> | %cn <%ce>'` shows the no-reply address for each. On any difference, stop and report it; never amend or reset to repair it.

Message: `<type>[(scope)]: <subject>`, with type `feat`, `fix`, `docs`, `refactor`, `style`, `test` or `chore`, an imperative lowercase subject of at most 50 characters, an optional body, and the trailer `Co-Authored-By: <active model's display name> <provider no-reply address>` (`noreply@anthropic.com` for Anthropic; `OpenAI <display name> <noreply@openai.com>` for OpenAI).

## Publish

Never push unasked. When commits are ready:

1. `git fetch`, then resolve where the push goes: the remote's push URL (`git remote get-url --push <remote>`) and the destination branch.
2. Review everything that would leave: `git log --stat --format=fuller <remote>/<branch>..HEAD`, every commit rather than the tip, so a file added and later removed is still seen. A first publication covers the whole history. Stop on credential-shaped paths without reading them.
3. Stop and show the publication cards: each repository with its push URL and branch, the commits with their authors, a diff summary, checks, and anything a public audience should not see. Push only after H says so.
4. Then run one command that pushes each repository in turn, `git -C <repo> push <remote> HEAD:<branch>` chained with `&&`, at one native prompt.
5. Confirm with `git ls-remote <remote> refs/heads/<branch>` that the remote holds the pushed commit, then find its CI run with `gh run list --commit <sha>` and watch it with `gh run watch`. Report the push, the remote check and CI separately; after an uncertain push, observe before proposing anything else.

A failed CI run gets one retry only after its logs show a retryable cause, such as a runner fault or a twin job that fetched its peer before the companion push landed. State the cause, then run `gh run rerun <run> --job <job>` for H to approve at its prompt. Source failures need a fix and a new commit.

When the work has shipped, delete its plan file.
