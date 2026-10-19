# Phase 5: Copy and review

Maintainers read PR text to answer 3 questions fast: what broke, why this fix, and how do I know it works. Text that makes them dig for those answers, or that pads them with confident filler, gets the PR read with suspicion. The ledger already holds the answers, so this phase mostly arranges them.

## Author mode: when the repo wants your words

Some repos require the person opening the PR or issue to write its description and comments themselves (WPT, image-rs). Recon's AI policy line says when this applies. In author mode, houseguest writes nothing the maintainer will read as the user's own words. Instead it hands the user:

1. **The facts to cover,** as a terse list: what broke, the evidence, the lineage link, what the change does, what was verified, and the limits. These are notes, not sentences to paste.
2. **The repo's calibration:** the length baseline, the template, and the heading convention.
3. **A review of the user's draft** once they've written it, using the draft check in `lrs.md` and this file's tells. Point to the sentence and the problem; let the user rewrite it.

If the policy allows LLM text in a marked form (image-rs wants it in a quote block with its relevance explained; WPT wants it labeled inside `<details>`), offer supporting material only in that form, and only when it adds something the user's text doesn't. The disclosure line follows the repo's rule; when the repo specifies none, use "AI-assisted: recon and review by houseguest; text written by me."

## Calibrate to the repo first

- **Text the repo mandates wins, verbatim.** If the template or a workflow requires headings, checkboxes, a disclosure block, or exact wording, keep them as written, even when they break a rule in this file (an em dash in their disclosure line, a "This PR" heading, "please don't delete the checkboxes"). Your rules govern only the sentences you write. Tick only the boxes you actually did.
- **Length is measured on your own prose.** Count the sentences you wrote. Leave out template headings and boilerplate, checkboxes, the disclosure line, and the collapsed proof block. Then pick the budget by the PR's function (see `lrs.md` section 2):
  - **Inform or fix a recognized problem:** aim for the dump's pre-LLM median, and treat its outside-contributor median as a ceiling. The floor is what the reviewer must know to merge without asking: for a dependency or security bump, the advisory or changelog link plus one sentence for each fact a reviewer would otherwise ask about (why this version, what happened to the lockfile, which tests ran). When the baseline is shorter than that floor, the floor wins. Across 12 well-run repos, outside contributors' PR bodies roughly tripled after LLMs arrived (median 207 characters before Dec 2022, 671 since mid-2025; see `research/pre-llm-prs.md` in the plugin repo).
  - **Pose a new problem, or argue a contested change:** skip the baseline. Give each move one or two sentences instead: the instability, the cost, the change, the warrant, and the acknowledgment. A contested change that argues properly in 6 sentences beats a short one that skips its warrant.
- **Headings:** use them when the template does, or when this repo's own contributors do. If 2 or more of the pre-LLM exemplars use the same headings (`## Before / ## After`), that's a convention. Otherwise write plain paragraphs, which is how most pre-LLM PRs in untemplated repos read.
- **Commits:** use the commit format in `style.md`, or the commit subjects in the gather dump if there's no `style.md` yet. The PR title has its own section below.
- **Draft or ready:** follow what recent merged PRs did.

Read the exemplars in the gather dump before drafting. They show this repo's human voice better than any rule here.

Then read `lrs.md`. It covers the reader model, the one-sentence problem statement, and where the point goes, and it ends with a draft check. Run that check on every draft before the maintainer-reviewer pass.

## The title

The title is the first thing a maintainer reads, and the first place a PR looks foreign. Learn the house style from titles other people got merged, not from your own past titles:

```bash
bash "<skill-dir>/scripts/title.sh" --repo <owner/name> --save "$LEDGER/titles.json" "<your title>"
```

It reports the repo's title conventions (prefix, length, examples) and flags anything in your title the repo's titles rarely do. The usual offenders:
- **Several clauses** joined by commas or semicolons. One title, one change.
- **Comparisons to other products** ("as in Arc", "as quickly as Dia's"). Say what this project now does, in its own terms.
- **"as ..." and ", not X" clauses.** "Kept while away, not built anew on every peek" is a sentence about a sentence; "The folded column is kept while away" is the change.
- **Length past the repo's 90th percentile.** If it doesn't fit, the PR is probably two PRs.

Match the house *form* exactly: `[package] Verb ...` in workers-sdk, `fix(scope): ...` in a Conventional Commits repo, a plain behavior statement where that's the norm (driceroland/Search titles read like "⌘N in full screen opens a window in full screen of its own"). Then make it plain inside that form: concrete nouns from the codebase, one verb, no flourish.

Write the final title to `$LEDGER/pr-title.txt`. The PR gate rechecks `--title` against `titles.json` and blocks on any flag, unless `$LEDGER/title-ack.md` explains why the title is right for this repo.

## How human contributors wrote (2019 to 2022)

These moves showed up again and again in pre-LLM PRs that got merged. Each one tells the maintainer something a generated PR usually can't.

1. **Open on the current behavior or the evidence.** "Currently, X does Y," or the compiler warning pasted as-is. No headline, no bold thesis sentence, no "This PR."
2. **Say in one sentence how you ran into it.** A real stake is the strongest human signal in a PR. It has to be true, so ask the user how they hit it; never invent one. If the agent found it, say that plainly ("Found while reading `foo.c`"). Describe the context generically ("on a personal site," "in a downstream CLI"); naming or linking the user's own projects reads as promotion.
3. **Link the lineage.** The commit, issue, or PR that introduced the bug or tried to fix it before ("Regression from abc1234," "Builds on #812, which was reverted in #840").
4. **Name one alternative and why you passed on it,** in one sentence, when there was an obvious one.
5. **Verify in one sentence, with a number** when there is one ("binary size went from 2,544 KB to 2,084 KB"). The full output goes in a collapsed block below. When the evidence is a matrix (behavior across browsers, platforms, or versions), a small table says it faster than prose.
6. **State the limits of what you checked** ("only tested on Linux," "I mostly relied on the existing tests").
7. **Hand the maintainer a specific choice** ("Happy to drop the README change if you'd rather keep this to code"). A generic "open to feedback" adds nothing.
8. **Credit people:** whoever reported it, whoever suggested the approach.

## Tells from recent PRs

These cluster in 2025 to 2026 PRs, and maintainers have learned to spot them:

- A bold thesis line opening the body.
- "Context & Purpose," "Value," "Scope philosophy," or "Root Cause" sections on a 20-line fix.
- "Test plan" bullets listing trivial checks, "All existing tests pass," "No behavioral changes."
- Arrows and labels inside code blocks (`<- BUG`), or prose labels like "Honest scope:".
- Inventories of `file:line` sites the PR doesn't change.
- Bullet-by-bullet narration of a diff the reviewer can read.
- "Revised <date>" or "Update:" blocks narrating how the PR changed during review, and paragraph-per-test walkthroughs of what each new test asserts.
- Promotion of the author's other projects. (The disclosure line is one line, at the end, about this PR only.)
- The negate-then-correct sentence: "This isn't just a cleanup, it's a fix for X." State the positive claim and delete the negation.
- Em dashes and scattered bold. Em dashes appeared in 0% of pre-2023 bodies in the corpus and 7% of recent ones.
- Plain words matter too. Cut: comprehensive, robust, seamless, leverage, utilize, enhance, streamline, delve, "this PR aims to," "it's worth noting."

If a `writing-style` skill is installed, apply it as well.

## PR body (when there's no template)

````markdown
<Current behavior or evidence, 1 to 2 sentences.> <How you ran into it, 1 sentence.>

<What the change does and why this way, 1 to 3 sentences, with a lineage link if there is one. One alternative, if there was an obvious one.>

<One verification sentence with a number.> <Limits of testing, if any.> Fixes #<N>.

<details><summary>Red-green output</summary>

```
<from proof.md: the red failure line, the green pass line, the commands and SHAs>
```
</details>

<disclosure line>
````

The collapsed block is how the proof stays complete while the prose stays at the repo's baseline length. Leave out anything that would be empty. A typo fix is one sentence and the disclosure line.

**Without `proof.md`:** when there's no red-green run (docs, dependency bumps, or a phase you skipped), drop the collapsed block and state in prose exactly what was run and what it showed. Never write a result that isn't in front of you; use `[ASK USER: did X pass?]` instead.

**Dependency and security bumps:** one or two sentences. Name the advisory or changelog entry that motivates it, the version change, and what you checked (lockfile regenerated, tests run). Skip the stake sentence unless there's a real one.

An invented example of the target shape, for a fictional formatter:

> Currently `--max-width` counts bytes, so lines of CJK text wrap at about a third of the requested width. I hit this formatting a Japanese docs folder.
>
> This counts display width with the same `unicode-width` call the renderer already uses for alignment. Counting chars would be simpler but still wrong for wide glyphs.
>
> Added a test that wraps at 13 columns before this change and 40 after. Only checked on Linux. Fixes #1234.

## The disclosure line

Every PR and issue gets one, placed at the end of the body (never in commit messages). It credits the tooling by name, with no link, and claims only what houseguest actually did in this run:

> AI-assisted. Recon, red-green check, and PR text by houseguest.

Build it from the phases that ran: "recon" if phase 1 ran, "red-green check" only if `prove.sh` produced `proof.md`, "benchmarks" only if you ran them, "PR text" if this phase wrote the body. A docs fix whose text you drafted reads "AI-assisted. Recon and PR text by houseguest."

When the repo requires its own disclosure form, fill in theirs and skip this line; their form already tells the maintainer what they need. Policies like Ghostty's require stating the **extent** of AI help, which only the user knows. Ask once: "Which parts did you write or review line by line yourself?" Then write it plainly, e.g. "AI-assisted: Claude Code drafted the fix and test; I reviewed every line and reproduced the bug by hand." Never overstate the human part. When a form applies only in some cases (for example, "if an agent opened this PR without human supervision"), decide honestly whether the case applies.

When the rule requires a human to be present and accountable without giving a form (libjxl: "A human must evaluate, understand, and actively submit changes"), the default line reads as "no human checked this," because it credits the tool for everything. Name the tool in a few words and give the rest of the line to what the user did, using only claims the user confirms:

> AI-assisted (Claude Code). I reproduced the numbers above locally and reviewed the change before submitting.

Ask the user which of those they actually did, and cut any they didn't.

## Issue body

```markdown
<One sentence: what happens, in which version or commit.>

**Repro**
1. <minimal steps, or a script>

**Expected:** <...>  **Actual:** <... exact error text in a code block>

**Environment:** <OS, relevant config>. Reproduces on <prod version> and <each build channels.sh sent you to, with its commit>; <builds it skipped and why, in a few words>.

Searched for duplicates: <the terms you searched, and closest matches with links, if any.>

<If the repo welcomes PRs: "Happy to send a fix if that's welcome.">

<disclosure line>
```

Don't guess at causes you haven't verified; a wrong diagnosis in an issue costs a maintainer more time than none. Use the repo's issue form when it has one, field for field.

**Feature requests** replace Repro/Expected/Actual with: what you're trying to do, what blocks it today (the closest current workaround, and why it falls short), and the smallest change that would unblock you. Ask whether it fits the project before offering a PR.

**Length:** an issue is read by someone deciding whether it's real and whether it's theirs. The repro and the exact error carry it; everything else is a sentence at most. The gather dump gives a median for outsiders' issues that maintainers acted on.

**Cut guesses, keep observations.** Remove causes you haven't verified. Keep short side observations you have confirmed (a size difference, a second symptom), marked as separate from the main bug in one sentence each. Maintainers often answer them, and they're cheap to read.

## Replies to review comments

Draft them for the user to post; never post them. Keep each reply short. Concede plainly when the reviewer is right, push the change, and reply with what changed and the commit (`Done in abc1234, moved the check into prune()`). When you disagree, use the acknowledge-pivot-defer move in `lrs.md` section 7: concede what's right in the request, give one concrete reason for your approach, and defer to their call. Skip openers like "Great catch!" and "You're absolutely right"; reviewers recognize them as machine text immediately.

After any push made in response to review, reread the PR body against the current diff and rewrite it as if the current diff were the first version: what the PR does and why, at the repo's length budget. Never append "Revised <date>" or "Update:" sections, and never narrate what earlier versions did. That history already lives in the commits and the review thread, and the maintainer reading the body wants the PR as it stands. A workers-sdk maintainer asked for exactly this on a PR whose body had grown 2 dated revision blocks: "We don't need to know the history of changes to the PR." A description of the first version sitting on top of the third version is the most common stale-PR smell, and a changelog of all 3 is the second.

## Maintainer-reviewer pass

Before showing the final PR to the user, run a fresh-context review with the Agent tool, so the reviewer hasn't absorbed your reasoning. Give it the paths to whichever of `recon.md`, `style.md`, and `proof.md` exist, CONTRIBUTING and any AI policy, the diff (`git diff <base>...HEAD`), and the drafted body. Prompt:

> You maintain <repo>. You've read hundreds of low-effort and AI-generated PRs and you close most within a minute. Review this PR as you would on a busy day. List every reason you'd close it or request changes, most likely first: rule violations from CONTRIBUTING or the AI policy, duplicated or already-rejected work, code that doesn't match how this codebase does things (cite the file that does it differently), tests that wouldn't catch a regression, claims in the description the proof doesn't support, and any line that reads as machine-written. Be specific and cite lines. Say "would merge" only if you'd actually merge it.

Fix every finding that a written rule, a repo tool, or a direct conflict with neighboring code requires, or write down why it doesn't apply. Findings face the same bar as style revisions in `style.md`: "this could be cleaner" or "the repo has a helper for this" permits a change without requiring it. Moving code between files, renaming, or swapping in a helper needs a rule or a maintainer comment behind it, and a reviewer's "import X from Y" means leave X where it is. If the reviewer found a closing reason recon missed, go back to recon.

## Ship

Write the final body to `$LEDGER/pr-body.md`. Show the user the title, the body, and the exact command:

```bash
gh pr create -R <upstream> --head <fork-owner>:<branch> --title "$(cat <ledger>/pr-title.txt)" --body-file "<ledger>/pr-body.md"
```

Run it only after a clear yes.
