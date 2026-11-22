---
name: practice
description: >
  Track the user's own engineering judgment across their houseguest jobs: how often recon stopped a
  job, which decisions they steered, what they caught wrong in the change, where the agent didn't
  help, and what they threw away. Reads the oss-pr ledgers, flags drift, and says which skill to work
  on next. Triggers on "how am I doing," "am I on track," "what should I practice," "review my
  judgment," "am I just rubber-stamping the agent," "what skills should I build," and
  "log what I caught." Also runs a retro on any repo's recent bug fixes, clustering them by root
  cause and naming the design change that would have prevented each cluster: "look at the last
  week of bugfixes," "what do these fixes have in common," "if we started over," "retro."
  Read-only, except for judgment.md lines the user approves.
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

## Retro

The report grades the contributor; a retro grades the design. The prompt is the user's: "Look at the last week of bugfixes. If we were to start this project over from scratch, what architecture decisions or feature adjustments would totally obviate those problems?" A fix removes one bug. A retro looks for the cause that keeps producing them, so the next fix can remove the whole class (`../oss-pr/references/sweeps.md`).

```bash
bash "<skill-dir>/../oss-pr/scripts/retro.sh" --repo <the clone> --since <YYYY-MM-DD>
```

The default window is the last 7 days. Widen it until it holds at least 5 fixes, or tell the user there are too few to cluster. Then:

1. **Read every commit,** FIX-marked ones first. The mark is a word match: on houseguest's own history from 2026-11-08 to 2026-11-22 it caught all 6 real fixes and 5 features. Read the diff wherever the message doesn't say what broke.
2. **Cluster by root cause.** Two fixes share a cluster when one design change would have prevented both, even across files and weeks. A fix that matches nothing stays on its own; don't force it into a cluster.
3. **For each cluster, give:**
   - **Root cause,** in one sentence, with the commits that show it.
   - **From scratch:** the architecture decision or feature change that makes the class impossible, such as a type, a parser, a narrower interface, or a different owner for a fact.
   - **Today:** the cheapest step that stops new instances, in the codebase as it is (a lint rule, a type, a shared helper, a test). Stop the bleeding before planning the rewrite.
   - **Check:** the oracle that shows the class is gone (`../oss-pr/references/proof.md`).
   - **Sweep:** a catalog entry with its trigger, prompt, and check, or `NEW` with all three filled in.
4. **Gate each From-scratch answer** on the ambition gates: an oracle exists, the claim matches the evidence, and a reviewer can take it in. When one fails, say which, and keep only the Today step.

Order clusters by how many fixes they explain. End with the one change you'd make first and the number that would show it worked.

Where the report goes depends on the room (`../oss-pr/scripts/room.sh`). In the user's own repo, offer to record each decision where the repo keeps them, and to open the Today steps as separate PRs. In someone else's repo, a retro is evidence for an issue or a discussion, never a redesign PR (`../oss-pr/references/defaults.md`, "Scope of a contribution"). Offer each `NEW` sweep for the catalog (sweeps.md, "Handing them back").

## What it doesn't cover

Work in repos the user owns leaves no ledger, so it isn't counted. The sources in `craft.md` date from late 2026; when one is a year old, tell the user it may need rechecking.
