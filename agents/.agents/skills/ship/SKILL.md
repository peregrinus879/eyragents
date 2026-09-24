---
name: ship
description: Commit verified work and publish it; all cards of a round come first in the chat, then H approves each commit and push at the tool's native prompt.
---

# Ship

H approves each commit and push at the tool's native permission prompt, after reading its card. H sees reply text but not the agent's reasoning, so every card of a round is written out in one reply message before the round's first prompt.

## Commit

1. Make one commit per independent change, with its tests and documentation. Stage only its paths, never `git add -A` or `git add .`, and keep credential-shaped paths out.
2. Check that `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` both show the GitHub no-reply address; if not, stop and tell H.
3. Run the repository's gates with the index equal to the working tree, so they test exactly what the commit holds, and record the staged tree with `git write-tree`. Report any failure; never commit around it.
4. Write every card of the round into one reply message before the first commit: repository and branch, what changed and why, files and size, the full message, gate results, and any review verdict or open finding.
5. Commit each repository with its own command, `git -C <repo> commit -F - <<'EOF'` with the full message, and a command description naming the repository and subject, so H can match each prompt to its card; one commit per prompt. A second commit in the same repository starts a new round, since its staged state is tested after the first. Then confirm that `git rev-parse HEAD^{tree}` equals the recorded tree and that `git log -1 --format='%an <%ae> | %cn <%ce>'` shows the no-reply address twice. On any difference, stop and report it; never amend or reset to repair it.

Message: `<type>[(scope)]: <subject>`, with type `feat`, `fix`, `docs`, `refactor`, `style`, `test` or `chore`, an imperative lowercase subject of at most 50 characters, an optional body, and the trailer `Co-Authored-By: <active model's display name> <provider no-reply address>` (`noreply@anthropic.com` for Anthropic; `OpenAI <display name> <noreply@openai.com>` for OpenAI).

## Publish

Never push unasked. When commits are ready:

1. `git fetch`, then resolve where the push goes: the remote's push URL (`git remote get-url --push <remote>`) and the destination branch.
2. Review everything that would leave: `git log --stat --format=fuller <remote>/<branch>..HEAD`, every commit rather than the tip, so a file added and later removed is still seen. A first publication covers the whole history. Stop on credential-shaped paths without reading them.
3. Stop and show the publication card: repository, push URL and branch, the commits with their authors, a diff summary, checks, and anything a public audience should not see. Push only after H says so.
4. Push each repository with its own command, `git -C <repo> push <remote> HEAD:<branch>`, whose description names the destination, each at its native prompt.
5. Confirm with `git ls-remote <remote> refs/heads/<branch>` that the remote holds the pushed commit, then find its CI run with `gh run list --commit <sha>` and watch it with `gh run watch`. Report the push, the remote check and CI separately; after an uncertain push, observe before proposing anything else.

A failed CI run gets one retry only after its logs show a retryable cause, such as a runner fault or a twin job that fetched its peer before the companion push landed. State the cause, then run `gh run rerun <run> --job <job>` for H to approve at its prompt. Source failures need a fix and a new commit.

When the work has shipped, delete its plan file.
