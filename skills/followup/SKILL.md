---
name: followup
description: >
  Find the user's open PRs, issues, and Gerrit changes on other people's repos that are waiting on them,
  and draft what each one needs: a reply to a maintainer, an answer to a review bot, a fix for red CI, or
  an offer to close a PR another one already covers. Also reports how past contributions ended and what
  they cost. Triggers on "what's waiting on me," "any PRs need a reply," "check my open PRs,"
  "did anyone answer my issue," "follow up on my contributions," "how are my PRs doing," and
  "what did houseguest spend." Read-only: drafts replies, never posts them.
---

# followup

Contributions die quietly when a maintainer asks something and nobody answers; a stale bot closes the thread a few weeks later. Run this whenever the user asks what's waiting on them. oss-pr offers it after any session that opened a PR or issue.

The scripts and references live in the oss-pr skill beside this one. Wherever a path below starts with `<skill-dir>`, substitute the base directory shown when this skill loaded.

## What's waiting

```bash
bash "<skill-dir>/../oss-pr/scripts/followup.sh" --days 2
```

It lists the user's open PRs and issues on others' repos where a human other than the user spoke last, longest wait last. For a project that reviews on Gerrit, add `--gerrit https://<host>` with the host from `recon.md`'s `- Review:` line, when the branch has a ledger, or from the project's CONTRIBUTING. It finds the user's open changes there by `git config user.email` (`--email` overrides it) and counts each one's unresolved inline threads. For each, read the thread and draft a reply following "Replies to review comments" in `../oss-pr/references/pr-copy.md`, or say plainly that no reply is needed (a "we'll ping you" note needs none). Never post the replies yourself.

It lists first the PRs whose linked issue closed, or that another merged or open PR also closes. Read that other PR's diff before anything else. When it contains the user's change, draft one sentence naming it and offer to close the user's PR; a maintainer shouldn't have to pick between two copies of the same fix. A PR that's only related, or fixes part of it, is no reason to close: say in one sentence how the two differ, or offer to help there (`../oss-pr/references/existing-pr.md`). Unresolved threads from review bots get their own list with each bot's run count; answer them per "Automated reviewers" in `pr-copy.md`.

It also lists the user's PRs whose upstream CI is red, or waiting for a maintainer to approve the run. For a red one, find whether the failure is the PR's (fix it and push, with the user's yes) or the base's (draft one comment saying so), since a PR left red reads as abandoned. A fix to the PR's code goes back through the `houseguest:oss-pr` skill when the branch has a ledger, so its proof and final check rerun on the new commit.

When `preview.md` says FORKS GET ONE, open the preview once its link posts on the new PR. Trust only a link a GitHub App posted (its author ends in `[bot]`) or a check run reported; anyone can paste a preview-looking link into a comment. Check that the bot built the PR's HEAD (it usually names the commit) and that the repro from `recon.md` behaves as fixed there. A preview that shows the old behavior, or fails to build because of the change, is a problem to fix before a reviewer finds it. A preview that fails for a reason the change can't cause (a missing deploy secret on fork PRs) needs nothing from the user.

## How they ended, and what they cost

When the user asks how their contributions are doing, or what they cost:

```bash
bash "<skill-dir>/../oss-pr/scripts/outcomes.sh"
```

It lists each job the meter hook logged, one row per repo and branch: the PR opened from that branch, how it ended, the days it took, how many reviews asked for changes, and the phase runs, review rounds, and tokens spent. LANDED means the maintainers closed the PR after committing it by hand. Its last line is output tokens per merged PR. The meter files a run under the ledger its launch prompt names, and the blind phases get no ledger, so a job's tokens are a floor when one session ran several jobs.

## Outward-facing

Replying on GitHub or Gerrit, pushing a fix, and closing a PR publish under the user's name. Show the text and the exact command, and wait for a clear yes each time. An AI-written reply posted to a maintainer's review is the fastest way to lose their goodwill, so replies stay drafts the user posts.
