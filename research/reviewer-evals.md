# Scoring the maintainer reviewer

Replayed against 23 public PRs, the maintainer reviewer named the maintainer's real reason on all 12 that were rejected. On the first run (2026-10-26) it also held the merge on 8 of the 11 that maintainers merged as they stood. After the 2026-10-31 prompt change it held 5 of the 11, and 4 of those 5 findings hold up against what happened on GitHub.

Recall is saturated on this set, so it can't tell two prompt versions apart. Noise is where prompt changes get scored.

This page exists because houseguest can't learn from itself. Its ledger lives in `.git/houseguest/<branch>/` and is deleted with the clone, so nothing records whether the reviewer was right. Anthropic scores its own code reviewer daily against PRs that caused incidents (recall) and PRs known to be clean (noise), and rescores on every prompt or model change. This is the offline version: a corpus built from public history, a harness that replays it, and a first score.

## Method

- **Repos:** ripgrep, bat, flask, and black, 4 of the 12 in `pre-llm-prs.md`. Their maintainers say why they close a PR, in a comment a script can find, and flask and black get a steady stream of agent-written PRs.
- **Recall set (`evals/recall.jsonl`):** 12 PRs from outside contributors, created after 2025-06-01, closed unmerged or sent back with changes requested. Each row carries the maintainer's reason, quoted with a link. `evals/candidates.sh recall <repo>` lists candidates using `gather.sh`'s heuristic for rejected attempts: the last thing a maintainer (OWNER, MEMBER, or COLLABORATOR, not a bot) said. The set keeps only reasons a reviewer could reach from the code and the repo as they stood: duplicates of an existing flag, a reversed decision recorded in the changelog, broken behavior, out-of-scope features, a written inclusion rule. It leaves out stale closes, "fixed by #N" closes, closes where the maintainer merged the work by hand, and closes whose reason lived in an issue thread the reviewer can't read (black's `ruff: ignore` pragma PRs, all closed with a pointer to #5260).
- **Noise set (`evals/noise.jsonl`):** 11 PRs from outside contributors, merged with no changes-requested review, from the same repos and window. `candidates.sh noise <repo>` lists them.
- **Agent authorship:** flagged where the PR says so (a `codex/` branch, a "Generated with Claude Code" line, a maintainer's "AI junk" label). 3 of the recall PRs and 3 of the noise PRs carry a flag. Most PRs that are agent-written don't say so, so this undercounts.
- **Replay:** `evals/run.sh prep` rebuilds each PR as the reviewer would have met it. It makes a fresh repo at the PR's merge base with 50 commits of history, puts the PR's final tree on top as one commit, and removes the remote. It runs `policy.sh --as-of` the moment the PR opened, so the reviewer gets the CONTRIBUTING and AI policy of that day. The title is the one the PR opened with: flask's maintainers rename rejected PRs to "AI junk" or "[rejected AI] ...", and the first replay of two flask PRs handed the reviewer that verdict through the title.
- **Review:** `agents/maintainer-review.md`, unchanged, gets the repo, the body, the diff, and the policy dump, with no ledger, because these PRs weren't made with houseguest. It runs offline. Anything on GitHub after the PR opened would leak the outcome, so `run.sh review` gives `claude -p` no WebFetch and allows only read-only git and file commands.
- **Judge:** a second model reads only the review and the real outcome (`evals/judge.md`). It splits the review into findings and marks each one blocking (a maintainer who agreed would hold the merge) or nit. For the recall set, it says whether one finding states the maintainer's reason in substance.
- **Scores:** recall is hits over recall PRs. Noise is the share of clean PRs that got at least one blocking finding, plus blocking findings per clean PR.
- **Rerun after a prompt change:** `rm <out>/*/{review.md,checks.json,judge.json}`, then `./evals/run.sh all <out>`. Each case records the hash of the reviewer prompt it ran, so scores from two prompt versions can't be mixed by accident.
- **Reproduce:** `cd research && ./evals/run.sh all <out-dir>` needs `gh` and a logged-in `claude` CLI, then `./evals/run.sh archive <out-dir> evals/results/<date>`. A session without the CLI can run `prep`, write each `review.md` from `system.md` plus `prompt.md` and each `judge.json` from `judge.md` plus `judge-prompt.md`, then run `score`. That's how this baseline was made (see the caveats).

## First scores

| | 2026-10-26 baseline |
|---|---|
| Recall: maintainer's reason named | 12/12 |
| Named as the first finding | 7/12 (worst: 8th) |
| Recall verdicts | 9 close, 3 request changes |
| Noise: clean PRs with a blocking finding | 8/11 |
| Blocking findings per clean PR | 1.0 |
| Noise PRs called mergeable | 2/11 |

The run used reviewer prompt `2aba6a090a98` (`agents/maintainer-review.md` at `0de988a`) on Opus 5.5, graded by Sonnet 5.5. Every review and grade is in `evals/results/2026-10-26/`, one directory per PR.

## Reading the noise number

The noise score counts disagreement with the maintainer, and some of that disagreement goes in the reviewer's favor. Three of the 11 blocking findings were checked against GitHub and hold up:

- **bat#4076:** the changelog line ends `see #XXXX`, which fails bat's required changelog check. The placeholder is still in bat's `CHANGELOG.md` on master today.
- **flask#6096:** no `CHANGES.rst` entry, which the PR template asks for. The line landed in a later commit on main, not from the PR.
- **black#5583:** the body's first example, `b'{"name": "é"}'` with a literal `é`, is a SyntaxError rather than the crash it claims to show. The body on GitHub has the literal character.

These maintainers fix a changelog line in 30 seconds and merge. A guest can't count on that, so for houseguest's own drafts a finding like these is cheap and worth having.

The rest are mostly claims about code that a test run would settle: double-wrapped error depth in ripgrep#3464, environment leaking between tests in flask#6095, an unfixed root cause in black#5521. None of the reviewers could build offline, so none of these were run. One looks wrong. The ripgrep#3557 review called two of BurntSushi's commits unmerged PRs because their subjects lack a `(#NNNN)` suffix, yet both PRs had merged before #3557 opened.

So 8/11 overstates the false-positive rate, though not by enough to dismiss it. The reviewer held a merge on 8 PRs that real maintainers took, and on 9 it said "request changes" where they said "thanks."

## What the recall set shows, and what it can't

- **12/12 is a ceiling.** The curation kept only reasons visible in the code and repo, so the set measures whether the reviewer finds a reason it could see. It doesn't test reasons maintainers carry in their heads. Black's `ruff: ignore` PRs, closed over a discussion in issue #5260, are the kind it would miss, and they were left out.
- **Rank is the stricter test.** The real reason came first 7 times. On ripgrep#3239 the duplicate of `--no-messages` came 5th, behind the AI prompt file the PR committed to the repo root (also a fair close reason). On black#5222, "no clear focus" came 8th, after 7 findings on specific hunks. A maintainer reading top-down meets the real reason late.
- **Two flask hits rest on the AI policy,** which the maintainer also cited. On flask#6124 the reviewer's second finding was the mechanism too: pushing and popping the context on every chunk.
- **A leak, caught.** The first replay of flask#6124 and #6145 used their current titles, "AI junk" and "[rejected AI] ...", which davidism set after closing. Both reviews cited the title. Prep now recovers the title each PR opened with from its rename events, and both cases still hit on the rerun.

## Rescore with the finding check (2026-10-31)

PR #26 changed the reviewer prompt and added a finding check, both adapted from Anthropic's code-review plugin. The prompt now leaves out things that are true but aren't findings (what a linter catches, code silenced on purpose, hardening no rule asks for), quotes a rule before citing it, and writes each Important finding so it can be checked alone. The check is `agents/finding-check.md`, one run per Important finding, blind to the rest of the review.

| | 2026-10-26 | 2026-10-31 |
|---|---|---|
| Recall: maintainer's reason named | 12/12 | 12/12 |
| Named as the first finding | 7/12 | 10/12 |
| Noise: clean PRs with a blocking finding | 8/11 | 5/11 |
| Blocking findings per clean PR | 1.0 | 0.5 |
| Noise PRs called mergeable | 2/11 | 6/11 |
| Finding checks run / refuted | none | 17 / 0 |

Reviewer prompt `9937d5f4cc5d` on Opus 5.5, checker prompt `bbc393b497f6` on Opus 5.5, graded by Sonnet 5.5. Every review, check, and grade is in `evals/results/2026-10-31/`.

**The prompt did the work, and the check refuted nothing.** The reviews alone scored the numbers above, before any check ran. The check then confirmed all 5 noise findings. That was the right call, judged against GitHub:

- **ripgrep#3464:** the PR gave depth to 3 of 4 cfg twins in `walk.rs`. The Windows `metadata_internal` still drops it on master today.
- **bat#4076:** the `#XXXX` changelog placeholder is still in bat's `CHANGELOG.md`.
- **black#5583:** the body's first repro is a SyntaxError (as on 2026-10-26).
- **flask#6096:** Pallets' CONTRIBUTING sends bug fixes to `stable`, and the PR targeted `main`. The rule is real; the maintainers waived it and merged.
- **black#5521:** a style change bolted onto the crash fix, reaching the default line length. Settling it needs a Black run, which the offline replay can't do.

So at most 1 of the 11 clean PRs drew a blocking finding that's wrong, against roughly 5 on the first run. This set leaves the check nothing false to refute, which means it shows the check doesn't cost real findings. It can't show the check catches false ones.

**The control.** Each recall case's hit finding was checked too: 11 CONFIRMED, 1 UNSURE. bat#3431's hit says nothing shows RPMSpec clears bat's 10,000-download bar for new syntaxes. The checker found the rule but couldn't see the download count offline. Under the skill an UNSURE finding goes to the user with what would settle it, so the reason still reaches someone; it just doesn't start a round on its own.

**What this run left out:**

- **Recall findings other than the hit (25 of 37) weren't checked,** to keep the run to 17 checks. The noise score is complete. The recall rank after checks isn't measured.
- **Grades are from before the checks.** With nothing refuted and the one UNSURE being a recall hit (still a hit as a nit), regrading would change no score.
- **Offline checks are weaker than real ones.** The skill's check runs the finding's input. Here it could only read, and 4 of the 5 noise checks said so.
- **The runner differs from the baseline's.** Reviews ran as general-purpose subagents told to follow `system.md`, because the installed `houseguest:maintainer-review` agent still carried the old prompt. An audit of all 423 tool calls across reviews, checks, and grades found no network use. Two reviewers read ripgrep's dependencies from the local cargo registry, outside the case directory.

## What to try next

- **Calibrate "blocking."** The 2026-10-31 prompt cut noise from 8/11 to 5/11, and 4 of the 5 left are real. Most of what's left is "fix before you send" (a changelog line, a branch target), which a guest should hear. Separating that from "blocks the merge" is now a reporting question more than a noise one.
- **Give the check something to refute.** A set of reviews with known-false findings (the 2026-10-26 ripgrep#3557 "unmerged PRs" claim is one) would test whether the check catches them.
- **Give it the ledger.** The real flow hands the reviewer recon's notes, including issue threads and earlier rejected attempts. A recall set that includes thread-only reasons would test that path.
- **Run each case 3 times.** One run per PR can't separate a real change from sampling noise.

## Caveats

- 23 PRs, 4 repos, and one run each make a directional sample. One flipped PR moves recall by 8 points and noise by 9.
- The `claude` CLI on this machine wasn't logged in, so `run.sh review` and `run.sh judge` haven't run end to end. This baseline used the same prompt files through Claude Code subagents: the `houseguest:maintainer-review` agent for reviews, and a Sonnet agent for each batch of grades. Those reviewers had network tools. Their prompt forbade network use, and an audit of all 281 tool calls found no network call (`review.meta.json` in each case).
- The reviewer gets no ledger, since these PRs weren't made with houseguest. In real use it gets recon, the intent check, and the proof. Those would help with "this already exists" reasons, and would likely change some noise findings.
- The grader is a model grading a model. For the recall set it sees the maintainer's reason and counts a match "in substance." Its blocking-or-nit call is a judgment, and it flagged the close ones in its notes (ripgrep#3557's benchmark finding, for one).
- One person curated the corpus and wrote each `expect` line. A different curator would pick different PRs, and probably harder ones.
- The body is the PR's final body. Authors edited 4 of the 23 after opening, 3 of them within 80 minutes and black#5521 12 days later; nobody else edited any. An edit made in answer to review would leak, and black#5521's might be one.
