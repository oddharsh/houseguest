# Contributing to someone else's open PR

Recon often ends here: an open PR already makes the change, so a second PR is wrong. Helping on that PR can be right. But the PR is its own small house inside the repo. Its author already chose names, a test style, a commit style, and an approach, and reviewers already shaped them. Work you add should read as if the author wrote it after taking the reviewers' notes.

## Read the PR's defaults first

```bash
bash "<skill-dir>/scripts/prdefaults.sh" --repo <owner/name> --pr <N> --save "$LEDGER/pr-defaults.md"
```

It reports:
- who may change the branch;
- the review decision, open threads, and what resolved threads settled;
- the branch's commit conventions;
- the changelog and test files the PR already carries;
- the style of its added lines;
- the CI checks failing now.

Then read the PR's full diff and every comment yourself; the script finds signals, and the thread holds the reasons.

## Precedence inside a PR

From strongest to weakest:

1. The repo's enforced tooling (formatter, linter, CI).
2. What maintainers asked for on this PR, in review threads and comments. Settled threads stay settled; don't reopen a choice a maintainer already made or accepted.
3. The repo's written rules.
4. The PR's own choices: the author's naming, helper placement, test assertions, fixture layout, comment density, and commit subjects.
5. The repo's neighboring code, then `deslop.md` and `defaults.md`.

The PR's choices outrank neighbors because consistency inside one diff is what a reviewer reads. A test you add next to the author's `toEqual` tests uses `toEqual`, even if the folder mostly snapshots, unless a maintainer asked this PR to snapshot. Then you snapshot, and you leave the author's tests to the author.

## Don't redo the author's work

- **Change only what your contribution needs.** Fixing the author's code because `defaults.md` or `deslop.md` would have written it differently is the guest-in-a-guest version of rewriting the host's kitchen. If you think something of theirs is wrong, say so in a review comment, with the reason.
- **Extend their structures.** Add a case to their table-driven test, a branch to their helper, a line to their changeset. Don't add a parallel helper, a second test file for the same function, or a second changelog entry (`prdefaults.sh` lists the one that exists).
- **Keep their approach.** If you'd solve it differently, leave a review comment for them to weigh.

## Pick the least intrusive way in

In order:

1. **A review comment, or a GitHub suggestion block** for anything under about 10 lines. The author applies it, so the history stays theirs. Use this whenever the author is active (`prdefaults.sh` shows when they last spoke).
2. **A PR into their branch** (`gh pr create -R <their fork> --base <their branch>`) for larger work, when the author is active but hasn't asked for pushes. They merge it or don't.
3. **Commits pushed to their branch,** only when the author or a maintainer invited it in the thread ("feel free to push") and you have access. Add commits on top. Never force-push, rebase, or squash someone else's branch, even if the branch's history shows the author does so.
4. **A new PR that supersedes theirs,** only when the author has been silent for weeks, a maintainer has said the PR is up for grabs (or the author abandoned it), and you credit them: keep their commits, or add `Co-authored-by:` for their work. Say in both threads what you did.

When the author hasn't invited help and you'd need option 3 or 4, ask first with a short comment: what you'd add, and whether they'd like you to push, open a PR into their branch, or leave it to them.

## Match the branch's conventions

- **Commit subjects:** follow the subjects already on the branch, which may differ from the repo's usual pattern (oxc#27235's are conventional, `fix(codegen): ...`; workers-sdk#15927 follows a `[codemods]` first commit with plain sentences like `Slim the Workflow migration changeset`). Match sign-off (`Signed-off-by`) if the branch's commits carry it.
- **Updating with the base:** if the branch merges `main` in, merge; if the author rebases, leave updates to them.
- **Checks:** run `housecheck.sh --base <the PR's head commit>` so it judges only your delta and treats the PR's own code as neighboring code. Prove your part with `prove.sh --base <the PR's head commit>`.

## Copy

- **Comments and suggestions** follow `pr-copy.md`'s review-reply rules: short, specific, one concrete reason.
- **The PR description belongs to its author.** Don't rewrite it; if your addition changes what the PR does, say so in a comment and let them update it.
- **Disclosure:** if the repo requires disclosing AI help, put it in your own comment or your PR into their branch; their description stays theirs.

## Ledger

Write `pr-defaults.md` (from the script) and record the decision in `recon.md` as `DECISION: JOIN <owner/repo#N> via <comment | PR into their branch | push (invited: link)>`. The PR gate accepts JOIN only when `pr-defaults.md` exists.
