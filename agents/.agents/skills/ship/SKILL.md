---
name: ship
description: Commit verified work and publish it; the round's cards end a turn, then H's reply brings one native prompt for the round. Use when H asks to commit, push, publish or ship.
---

# Ship

H approves each round of commits, and each round of pushes, at one native permission prompt, after reading every card of the round in the chat. Text written in the same message as a tool call can stay in the agent's hidden reasoning and never reach H, while a reply that ends the turn always does; so the cards end a turn, and the prompt opens the next. The cards are for commits and pushes the agent composes: when H's own message gives the exact command, it needs no cards, but the identity check and the Publish checks still run first, and a failure stops it before the prompt.

## Commit

1. Make one commit per independent change, with its tests and documentation. Stage only its paths, never `git add -A` or `git add .`, and keep credential-shaped paths out.
2. Check that `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` both show the GitHub no-reply address; if not, stop and tell H.
3. Build the round's commits in order, finishing, staging and gating each change before making the next, so every gate sees exactly its commit; changes already made together that cannot be tested apart form one commit. For each, stage its paths, run the repository's gates with the index equal to the working tree, so they test exactly what the commit holds, and record the staged tree with `git write-tree`. Report any failure; never commit around it. Commits in one repository must touch separate files; a commit that changes a file an earlier commit of the round changes, or depends on one landing, goes to a later round.
4. End the turn with every card of the round in one message, and no tool call after it: repository and branch, what changed and why, files and size, the full message, gate results, and any review verdict or open finding.
5. When H replies, revise and show new cards if H asks for a change. Otherwise open the turn with one command that makes the round, chained with `&&` so a failure stops the rest: in each repository, `git -C <repo> commit -F <message file> -- <paths>` for every commit but the last, which takes only those files, then `git -C <repo> commit -F <message file>`. Keep the message files in the tool's session scratch, as global guidance's Continuity rule says, so the prompt stays short. Then confirm that each commit's tree (`git rev-parse <commit>^{tree}`) equals its recorded tree and that `git log --format='%an <%ae> | %cn <%ce>'` shows the no-reply address for each. On any difference, stop and report it; never amend or reset to repair it.

Message: `<type>[(scope)]: <subject>`, with type `feat`, `fix`, `docs`, `refactor`, `style`, `test` or `chore`, an imperative lowercase subject of at most 50 characters, an optional body, and the trailer `Co-Authored-By: <active model's display name> <provider no-reply address>` (`noreply@anthropic.com` for Anthropic; `OpenAI <display name> <noreply@openai.com>` for OpenAI).

## Publish

Never push unasked. When commits are ready:

1. `git fetch`, then resolve where the push goes: every push URL (`git remote get-url --push --all <remote>`) and the destination branch. Stop if the remote has more than one push URL, or if its push URL differs from its fetch URL (`git remote get-url <remote>`), since the review below would then describe another repository.
2. Review everything that would leave: `git log --stat --format=fuller <remote>/<branch>..HEAD`, every commit rather than the tip, so a file added and later removed is still seen. A first publication covers the whole history. Stop on credential-shaped paths without reading them.
3. End the turn with the publication cards: each repository with its push URL and branch, the commits with their authors, a diff summary, checks, and anything a public audience should not see. Push only after H says so.
4. When H says so, open the turn with one command that pushes each repository in turn, `git -C <repo> push <remote> HEAD:<branch>` chained with `&&`, at one native prompt.
5. Confirm with `git ls-remote <push URL> refs/heads/<branch>` that the destination holds the pushed commit, then find its CI run with `gh run list --commit <sha>` and watch it with `gh run watch`. Report the push, the remote check and CI separately; a custom SSH transport can make the remote check unobservable, which is an unknown result, not a failure. After an uncertain push, observe before proposing anything else.

A failed CI run gets one retry only after its logs show a retryable cause, such as a runner fault or a twin job that fetched its peer before the companion push landed. State the cause and end the turn; on H's reply, run `gh run rerun <run> --job <job>` for H to approve at its prompt. Source failures need a fix and a new commit.

When the work has shipped, delete its plan file.
