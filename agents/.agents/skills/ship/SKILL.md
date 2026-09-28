---
name: ship
description: Commit, push and post to GitHub; each round runs as one command that carries its full content, so the native prompt is the card and H's one approval. Use when H asks to commit, push, publish or ship, or to create, comment on, review, edit or close a GitHub issue, pull request, release or discussion.
---

# Ship

H approves every commit, push and GitHub post at the tool's native permission prompt, and the prompt is the card: one command whose text carries everything it writes, so what H approves is on the prompt itself. Text written in the same message as a tool call can stay in the agent's hidden reasoning and never reach H; the command in a prompt always does. The checks below run before the prompt; a failure, or anything that needs H's judgment, ends the turn with a report instead of a prompt. When H's own message gives the exact command, run it as given after the same checks.

The command holds only the writes, never setup or checks, and reads as a card:

- Messages and bodies go inline as a quoted here-document inside a command substitution, `"$(cat <<'EOF'` … `EOF` then `)"`, the shape both tools' shell parsers read; never as a file the prompt cannot show. No line of the text may equal the delimiter.
- Plain `git` in the session's repository; `git -C <repo>` only for another one.
- Message lines of at most 72 characters; paths after the message, wrapped with `\` when long.

In Claude Code, the command's description adds a one-line summary under it, such as the branch, gate results and size. OpenCode shows only the command, in a box that ctrl+f expands, so the command alone must carry everything H approves.

## Commit

1. Make one commit per independent change, with its tests and documentation. Ship a topic when it completes, before the next topic starts in the same repository, so later topics never entangle its files; when topics have already accumulated, split them into rounds by rebuilding each topic's state from HEAD rather than merging them. Stage only its paths, never `git add -A` or `git add .`, and keep credential-shaped paths out.
2. Check that `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` both show the GitHub no-reply address; if not, stop and tell H.
3. Build the round's commits in order, finishing, staging and gating each change before making the next, so every gate sees exactly its commit; one commit holds several topics only when they are inseparable in substance, never because they share files. For each, stage its paths, run the repository's gates with the index equal to the working tree, so they test exactly what the commit holds, and record the staged tree with `git write-tree`. When the working tree holds more than the commit, gate an export of the index in session scratch instead: `git checkout-index -a --prefix=<dir>/`, then `git -C <dir> init -q` and `git -C <dir> add -A`, and the gates with `-C <dir>` forms rather than `cd`. Gates read the index, not a commit, so never commit in the export. Report any failure; never commit around it. Commits in one repository must touch separate files; a commit that changes a file an earlier commit of the round changes, or depends on one landing, goes to a later round.
4. Make the round with one command, chained with `&&` so a failure stops the rest, each commit carrying its full message and naming its paths:

   ```bash
   git commit -m "$(cat <<'EOF'
   <message>
   EOF
   )" -- <paths> &&
   git commit -m "$(cat <<'EOF'
   <message>
   EOF
   )" -- <paths>
   ```

   The description summarizes the round: repository and branch, gate results, files and size, and any review verdict.
5. Confirm that each commit's tree (`git rev-parse <commit>^{tree}`) equals its recorded tree and that `git log --format='%an <%ae> | %cn <%ce>'` shows the no-reply address for each. On any difference, stop and report it; never amend or reset to repair it.

Message: `<type>[(scope)]: <subject>`, with type `feat`, `fix`, `docs`, `refactor`, `style`, `test` or `chore`, an imperative lowercase subject of at most 50 characters, an optional body saying what changed and why, and the commit trailer from [Attribution](#attribution).

## Publish

Push only when H has asked to push, publish or ship.

1. `git fetch`, then resolve where the push goes: every push URL (`git remote get-url --push --all <remote>`) and the destination branch. Stop if the remote has more than one push URL, or if its push URL differs from its fetch URL (`git remote get-url <remote>`), since the review below would then describe another repository.
2. Review everything that would leave: `git log --stat --format=fuller <remote>/<branch>..HEAD`, every commit rather than the tip, so a file added and later removed is still seen. A first publication covers the whole history. Stop on credential-shaped paths without reading them, or on anything a public audience should not see.
3. Push in one command, `git push <remote> <sha>:refs/heads/<branch>` for each repository, chained with `&&`, naming the exact commit and destination. The description gives the commit range and the push URL.
4. Confirm with `git ls-remote <push URL> refs/heads/<branch>` that the destination holds the pushed commit, then find its CI run with `gh run list --commit <sha>` and watch it with `gh run watch`. Report the push, the remote check and CI separately; a custom SSH transport can make the remote check unobservable, which is an unknown result, not a failure. After an uncertain push, observe before proposing anything else.

A failed CI run gets one retry only after its logs show a retryable cause, such as a runner fault or a twin job that fetched its peer before the companion push landed; run `gh run rerun <run> --job <job>` with the cause in its description. Source failures need a fix and a new commit.

## GitHub Posts

Issues, pull requests, comments, reviews, releases and discussions are public writes under H's account. Check the text as for a push: nothing credential-shaped, nothing a public audience should not see. Run each post as one command with its title and full body inline, such as `gh pr create --title "<title>" --body "$(cat <<'EOF'` … `EOF` then `)"`, and `--notes` for release notes. A change without a body (close, merge, label) runs as its bare command.

## Attribution

Everything the agent writes for Git or GitHub ends with one line naming the active model:

- a commit: the trailer `Co-Authored-By: <model> <address>`, the form GitHub reads to credit a co-author;
- a GitHub post: the last line `Co-Authored-By: <model>`.

`<model>` comes from the exact model ID the client states, without its provider prefix, bracketed suffix or date: Anthropic IDs read `Claude <Family> <version>` with the version's hyphens as dots (`claude-opus-5-5` is `Claude Opus 5.5`), with `noreply@anthropic.com`; OpenAI IDs read `OpenAI GPT-<version>` followed by the remaining words capitalized (`gpt-6-astra` is `OpenAI GPT-6 Astra`), with `noreply@openai.com`. Any other ID takes the provider's published model name. OpenCode adds no attribution of its own. Claude Code's default attribution yields to this rule, so its settings leave `attribution.commit` and `attribution.pr` unset: an empty value makes Claude Code forbid attribution lines even where guidance asks for them.
