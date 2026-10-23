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

Files: `intent.md`, `recon.md`, `codex.md` (from `codex.sh`), `style.md`, `house.md` (from `housecheck.sh`, including the lean size checks), `proof.md`, and `pr-defaults.md` when joining an existing PR. The plugin's hook reads them before `gh pr create` runs and blocks the PR when one is missing. Keep each note short and concrete (paths, links, commands, exit codes); they also feed the PR description later.

The helper scripts live in `scripts/` next to this file. Wherever a reference says `<skill-dir>`, substitute the base directory shown when this skill loaded.

Recon runs before you clone, and so does an issue. Until a clone exists, keep notes in `${TMPDIR:-/tmp}/houseguest/<owner>/<repo>/<topic>/` and move them into the ledger once the branch exists.

## Each phase runs in its own subagent

A phase that runs in the same context as the one before it inherits that phase's conclusions. The agent that wrote the fix grades its own proof, and the agent that's sure there's a bug reads the docs looking for confirmation. So you, the session the user talks to, don't run phases. You launch each one as a fresh subagent with the Agent tool, and the phases share nothing but the ledger.

Your job between phases:

- **Launch** each phase with its reference file, `<skill-dir>`, the absolute ledger path, and the inputs in the table below. Pass facts (repo, issue number, paths, the user's words), never your own reading of them: no "the bug is probably in X," no summary of an earlier phase. A phase that needs an earlier phase's conclusions reads them from the ledger.
- **Read** the note each phase writes, tell the user the result in a line or two, and decide whether the next phase runs. A STOP or ASK ends the job the same way it did before.
- **Relay questions.** A subagent can't ask the user anything. It writes `[ASK USER: <question>]` in its note and stops; you ask, then launch the phase again with the answer.

| # | Phase | Read | Writes | Give the subagent | Keep from it | Can stop the job? |
|---|-------|------|--------|-------------------|--------------|-------------------|
| 0 | Intent check | `agents/intent-check.md` | `intent.md` | The repo, a neutral statement of the behavior (below), and the files or symbols it lives in | The issue, the user's request, the proposed fix, and every other ledger note | No, but recon decides from it |
| 1 | Recon | `references/recon.md` | `recon.md` | The user's request, the repo, the issue | Nothing | Yes: duplicate, already fixed (on head, beta, or canary too, per `channels.sh`), won't-fix, AI ban, discussion-first, behavior the project chose on purpose |
| 2 | Style fingerprint | `references/style.md`, `references/languages.md` | `codex.md` (from `codex.sh`), `style.md` (from `house.sh`) | The clone and the files it will touch | Nothing | No, but it shapes everything after |
| 3 | Write the change | `references/lean.md` first, then `references/style.md`, `references/deslop.md`, `references/defaults.md` | the smallest diff that fully solves the issue, committed, then `house.md` | The user's request and the clone | Nothing | No, but a PR that does two things becomes two PRs |
| 4 | Proof | `references/proof.md` | `proof.md` | The clone, the base ref, and the commit | How the change was written: it gets the diff, not the account of it | Yes: if red-green fails, the fix or the test is wrong |
| 5 | Copy | `references/pr-copy.md`, then `references/lrs.md` | `pr-title.txt`, `pr-body.md`, or the issue or reply text | The clone and the user's answers to its questions | The conversation: it writes only what the ledger and the diff show | No |
| 6 | Maintainer review | `agents/maintainer-review.md` | findings, returned to you | What "Maintainer-reviewer pass" in `pr-copy.md` lists | How the change and the text were made | Yes: if it finds a closing reason |

The intent check and the maintainer reviewer ship as agents with this plugin (`houseguest:intent-check`, `houseguest:maintainer-review`); their files are in `agents/` at the plugin root, two levels above `<skill-dir>`. If the agents aren't listed, launch a general-purpose agent with the agent file's body as its prompt. The other phases run as general-purpose agents told to follow their reference file. A subagent can't launch another one, so you run phase 6 yourself and send its findings back to the phase that owns them: code findings to a fresh phase 3 (then 4 and 5 again), text findings to a fresh phase 5, each with the findings quoted in full. A closing reason recon missed sends the job back to phase 1.

**The neutral statement** for the intent check is one or two sentences of what the code does, with the inputs that make it happen: "With `--max-width 40`, a line of Japanese text wraps after 13 characters." Leave out every word that carries a verdict: bug, broken, wrong, should, expected, fix, regression, issue, and the issue number. Also leave out who hit it and why it matters. Write the statement down for the user before launching, so they can see it carries no verdict.

Run the intent check first, before recon writes anything to the ledger, so there's nothing there to bias it. It runs for any change to existing behavior, including a feature request that changes a default. When the change alters no existing behavior (docs, typos, a new option that changes no default), skip it and write `VERDICT: N/A (<reason>)` to `intent.md` yourself.

Work out where the user is and start there. Someone asking "write the PR description" with a finished branch still needs the ledger checked, but not a redo of everything.

Adding to someone else's open PR (recon's `DECISION: JOIN`, or the user asks to help on a PR) runs every phase through `references/existing-pr.md`: the PR's own choices and its reviewers' asks outrank the repo's neighbors, and the least intrusive way in wins. Issues and feature requests only need phases 0 and 1 and the issue section of phase 5. When recon says ASK, the job ends with the comment draft described in `recon.md`. Docs or typo PRs skip phase 4; say so in `proof.md` (`STATUS: N/A (docs-only)`), and don't invent a test.

## After posting

Contributions die quietly when a maintainer asks something and nobody answers; a stale bot closes the thread a few weeks later. Run this whenever the user asks what's waiting on them, and offer it after any session that opened a PR or issue:

```bash
bash "<skill-dir>/scripts/followup.sh" --days 2
```

It lists the user's open PRs and issues on others' repos where a human other than the user spoke last, longest wait last. For each, read the thread and draft a reply following "Replies to review comments" in `pr-copy.md`, or say plainly that no reply is needed (a "we'll ping you" note needs none). Never post the replies yourself.

When `preview.md` says FORKS GET ONE, open the preview once its link posts on the new PR. Trust only a link a GitHub App posted (its author ends in `[bot]`) or a check run reported; anyone can paste a preview-looking link into a comment. Check that the bot built the PR's HEAD (it usually names the commit) and that the repro from `recon.md` behaves as fixed there. A preview that shows the old behavior, or fails to build because of the change, is a problem to fix before a reviewer finds it. A preview that fails for a reason the change can't cause (a missing deploy secret on fork PRs) needs nothing from the user.

## Things that are always outward-facing

Opening a PR or issue, pushing to a fork, and replying on GitHub publish text under the user's name to strangers. Show the final text and the exact command, and wait for a clear yes each time. Draft replies to reviewers; never auto-post them, because an AI-written reply to a maintainer's review is the single fastest way to lose their goodwill.

## When recon says stop

Report the reason with links and stop. Offer the useful alternative where one exists. Comment on the existing PR, ask in the issue whether a PR is welcome, or file the repro as an issue. Don't look for a way around a repo's AI policy.
