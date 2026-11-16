---
name: pr-copy
description: >
  Write PR titles and bodies, issue titles and bodies, and replies to review comments that read like
  the repo's own contributors wrote them: opened on the current behavior, sized to the repo's pre-LLM
  baseline, proof folded into a collapsed block, no tells. Use this for PR or issue text outside an
  oss-pr job: in a repo the user owns, on a teammate's PR, or for a quick reply to a reviewer.
  Triggers on "write the PR description," "draft the PR body," "title this PR," "write up this issue,"
  "reply to this review comment," "answer the CodeRabbit comments," or "this PR body is stale, rewrite it."
  In a repo the user doesn't own, or on a branch with a houseguest ledger, oss-pr's phase 5 owns the copy.
---

# pr-copy

The rules live in `../oss-pr/references/pr-copy.md`, which oss-pr's copy phase also reads. This skill is the way in for a PR or issue that has no oss-pr job behind it, so it says which parts of that file apply and what stands in for the ledger.

Wherever a path below starts with `<skill-dir>`, substitute the base directory shown when this skill loaded.

## Route first

```bash
git rev-parse --git-dir >/dev/null 2>&1 && ls "$(git rev-parse --git-dir)/houseguest/$(git branch --show-current)" 2>/dev/null
```

- **The branch has a ledger,** or the target repo belongs to someone else and the user is contributing a change: stop here and use the `houseguest:oss-pr` skill. Its copy phase runs blind to the conversation and feeds the PR gate, and this skill does neither.
- **Anything else** (the user's own repo, a teammate's PR, text for a PR that's already open): carry on below.

## What stands in for the ledger

oss-pr's phase 5 reads its facts from ledger notes. Here they come from the repo and the conversation, and each one is stated, never guessed:

| pr-copy.md reads | Here, use |
|---|---|
| The gather dump's exemplars and length medians | 10 recent merged PRs by people other than the author: `gh pr list -R <owner/name> --state merged --limit 30 --json number,title,body,author`. With fewer than 5 such PRs (a solo repo), the repo's own commit bodies set the form, and the budget is the user's CLAUDE.md or plain "a few sentences" |
| `style.md`'s commit format | `git log -20 --no-merges --format='%s%n%b%n----'` on the target branch |
| `proof.md` | Only output that's in this conversation or that you run now. With none, follow "Without `proof.md`" in pr-copy.md: say in prose exactly what ran, or ask |
| `final.md`, `holdout.md`, `recon.md`'s `Reproduces on:` | The limits sentence names what you didn't run, from what you know ran. Never claim a platform or build you didn't see |
| `decisions.md`, `rounds.md` | The review thread itself |

For the title check, save the conventions to scratch instead of a ledger:

```bash
bash "<skill-dir>/../oss-pr/scripts/title.sh" --repo <owner/name> --save "${TMPDIR:-/tmp}/houseguest-titles.json" "<your title>"
```

It learns from merged PRs by other people, so in a solo repo it has little to read; when it says so, match the form of the repo's own recent titles instead.

## Which sections apply

Read `../oss-pr/references/pr-copy.md`, then `../oss-pr/references/lrs.md` for the reader model and the draft check.

- **Apply as written:** "Calibrate to the repo first," "The title," "How human contributors wrote," "Tells from recent PRs," "PR body," "Long-form PRs," "On Gerrit," "Issue title," "Issue body," "Replies to review comments," and "Automated reviewers."
- **Author mode** applies when the repo's AI policy (CONTRIBUTING, `AGENTS.md`, the PR template) asks for human-written text. Check before drafting; `bash "<skill-dir>/../oss-pr/scripts/policy.sh" --repo <owner/name>` reads it wherever it lives.
- **The disclosure line** credits houseguest for phases that ran, and none did. Follow the repo's own rule when it has one; otherwise leave the line out in the user's own repo, and ask before adding one elsewhere.
- **Skip:** "Maintainer-reviewer pass," "Recheck upstream," "Ship," and "The revert sentence." They belong to the oss-pr job and its gate.

A reviewer's read is still worth having on a long or contested PR. Offer it, and on a yes launch the `houseguest:maintainer-review` agent with the repo, the diff (`git diff <base>...HEAD`), and the drafted body, and nothing about how either was made. Its instructions expect a ledger, so the prompt says there is none and that the repo's CONTRIBUTING, `AGENTS.md`, and review guides are its rules to read.

## Hand-off

Show the user the title, the body, and the exact command. Opening a PR or issue and posting a reply publish text under the user's name, so each one waits for a clear yes; replies to reviewers are drafts the user posts.
