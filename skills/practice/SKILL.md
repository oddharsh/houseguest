---
name: practice
description: >
  Track the user's own engineering judgment across their houseguest jobs: how often recon stopped a
  job, which decisions they steered, what they caught that the agent got wrong, where the agent didn't
  help, and what they threw away. Reads the oss-pr ledgers, flags drift, and says which skill to work
  on next. Triggers on "how am I doing," "am I on track," "what should I practice," "review my
  judgment," "am I just rubber-stamping the agent," "what skills should I build," and
  "log what I caught." Read-only, except for judgment.md lines the user approves.
---

# practice

oss-pr grades each contribution on its own. This skill grades the contributor across jobs, on the skills employers now hire for once code is cheap: choosing what to build, verifying what got built, steering the agent, knowing where it doesn't help, throwing work away, and measuring outcomes. `references/craft.md` names each one, its source, and the ledger evidence it leaves.

The scripts live in the oss-pr skill beside this one. Wherever a path below starts with `<skill-dir>`, substitute the base directory shown when this skill loaded.

## The report

```bash
bash "<skill-dir>/../oss-pr/scripts/practice.sh" --root <the directory the user's clones live in>
```

It prints one row per job and totals over the last 10 finished jobs, then a `DRIFT:` line for each pattern worth the user's attention. When the user doesn't say where their clones live, look at the cwd's parent and ask once; the script won't walk the whole home directory. Then run `outcomes.sh` (`../followup/SKILL.md`) for tokens per merged PR.

Read the report to the user in a few sentences, in this order:

1. **One skill to work on next,** picked from the DRIFT lines, or from the weakest column when there are none. Name the source in `craft.md` that makes it matter, in one clause.
2. **One job to look at,** the row that shows it best, with its ledger path. Read that ledger yourself first, so you quote what happened instead of the count.
3. **The number to watch** next time: the column or the DRIFT line that should move.

A count is a prompt to read the ledger, never a score. Never rank the user against other people, and don't praise or scold; say what the ledger shows.

## Logging judgment

`judgment.md` holds what the ledger can't show on its own: what the user caught, where the agent didn't help, and what they threw away. The format is in `craft.md`.

When a job finishes (a PR opens, an issue posts, or recon stops it), oss-pr asks the user for these lines. Here, when the user asks to log one, or the report flags jobs without them:

- Offer drafts from the job's `rounds.md` and `decisions.md`: a finding the user overruled with evidence, a decision that cites "the user decided," a reversal.
- Write a line only after the user says it's true, in their words. A judgment log the agent wrote for the user trains nothing.
- A job with nothing to record gets no file. Don't invent a line to clear a DRIFT.

## What it doesn't cover

Work in repos the user owns leaves no ledger, so it isn't counted. The sources in `craft.md` date from late 2026; when one is a year old, tell the user it may need rechecking.
