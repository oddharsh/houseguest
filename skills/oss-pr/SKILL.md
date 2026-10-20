---
name: oss-pr
description: >
  Make a pull request or issue on someone else's open-source repo that maintainers want to merge:
  recon before code (CONTRIBUTING, AI policy, duplicates, rejected attempts, already-fixed-upstream),
  match the repo's own style and tests first, deslop the contribution across languages, prove the fix
  with a red-green check, and write PR/issue/commit copy grounded in real test output. Use this whenever
  the user is contributing to a repo they don't own: fixing a bug in a library, "open a PR on X",
  "file an issue upstream", "send a patch", "contribute this fix back", working in a fork, writing a
  PR description or reply to a maintainer's review, or checking whether an existing PR of theirs is
  sloppy. Also use it when the user asks whether an issue is already fixed or already has a PR.
---

# oss-pr

Maintainers of popular repos now triage a flood of low-effort, AI-shaped PRs. They close most of them on sight, for 3 reasons:

- The PR duplicates or contradicts something already decided.
- The code doesn't look like the rest of the codebase.
- The description claims things nobody verified.

Each phase below removes one of those reasons. The phases run in order because the cheap ones can end the job before any code gets written.

**Precedence.** Every phase leans on this order. The repo's own enforced tooling beats its written rules, which beat its observed conventions, which beat deslop principles, which beat your defaults. A contribution that looks native and slightly imperfect gets merged more often than one that is "better" but foreign.

## The ledger

Each phase writes a short note to the ledger, a directory inside `.git` so it can never be committed to the upstream repo:

```bash
LEDGER="$(git rev-parse --git-dir)/houseguest/$(git branch --show-current)"
mkdir -p "$LEDGER"
```

Files: `recon.md`, `codex.md` (from `codex.sh`), `style.md`, `house.md` (from `housecheck.sh`, including the lean size checks), `proof.md`, and `pr-defaults.md` when joining an existing PR. The plugin's hook reads them before `gh pr create` runs and blocks the PR when one is missing. Keep each note short and concrete (paths, links, commands, exit codes); they also feed the PR description later.

The helper scripts live in `scripts/` next to this file. Wherever a reference says `<skill-dir>`, substitute the base directory shown when this skill loaded.

Recon runs before you clone, and so does an issue. Until a clone exists, keep notes in `${TMPDIR:-/tmp}/houseguest/<owner>/<repo>/<topic>/` and move them into the ledger once the branch exists.

## Phases

Work out where the user is and start there. Someone asking "write the PR description" with a finished branch still needs the ledger checked, but not a redo of everything.

| # | Phase | Read | Writes | Can stop the job? |
|---|-------|------|--------|-------------------|
| 1 | Recon | `references/recon.md` | `recon.md` | Yes: duplicate, already fixed (on head, beta, or canary too, per `channels.sh`), won't-fix, AI ban, discussion-first |
| 2 | Style fingerprint | `references/style.md`, `references/languages.md` | `codex.md` (from `codex.sh`), `style.md` (from `house.sh`) | No, but it shapes everything after |
| 3 | Write the change | `references/lean.md` first, then `references/style.md`, `references/deslop.md`, `references/defaults.md` | the smallest diff that fully solves the issue | No, but a PR that does two things becomes two PRs |
| 4 | Proof | `references/proof.md` | `proof.md` | Yes: if red-green fails, the fix or the test is wrong |
| 5 | Copy and review | `references/pr-copy.md`, then `references/lrs.md` | PR/issue/commit text | Yes: if the maintainer-reviewer pass finds a closing reason |

Adding to someone else's open PR (recon's `DECISION: JOIN`, or the user asks to help on a PR) runs every phase through `references/existing-pr.md`: the PR's own choices and its reviewers' asks outrank the repo's neighbors, and the least intrusive way in wins. Issues and feature requests only need phase 1 and the issue section of phase 5. When recon says ASK, the job ends with the comment draft described in `recon.md`. Docs or typo PRs skip phase 4; say so in `proof.md` (`STATUS: N/A (docs-only)`), and don't invent a test.

## After posting

Contributions die quietly when a maintainer asks something and nobody answers; a stale bot closes the thread a few weeks later. Run this whenever the user asks what's waiting on them, and offer it after any session that opened a PR or issue:

```bash
bash "<skill-dir>/scripts/followup.sh" --days 2
```

It lists the user's open PRs and issues on others' repos where a human other than the user spoke last, longest wait last. For each, read the thread and draft a reply following "Replies to review comments" in `pr-copy.md`, or say plainly that no reply is needed (a "we'll ping you" note needs none). Never post the replies yourself.

## Things that are always outward-facing

Opening a PR or issue, pushing to a fork, and replying on GitHub publish text under the user's name to strangers. Show the final text and the exact command, and wait for a clear yes each time. Draft replies to reviewers; never auto-post them, because an AI-written reply to a maintainer's review is the single fastest way to lose their goodwill.

## When recon says stop

Report the reason with links and stop. Offer the useful alternative where one exists. Comment on the existing PR, ask in the issue whether a PR is welcome, or file the repro as an issue. Don't look for a way around a repo's AI policy.
