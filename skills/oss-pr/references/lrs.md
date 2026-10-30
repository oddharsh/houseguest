# LRS for PR text

The University of Chicago's Little Red Schoolhouse (LRS), built on Joseph Williams and Gregory Colomb's work, teaches writing from the reader's side. Prose reads as clear when readers can quickly find who is acting and what they're doing. It reads as important when it addresses a problem they already care about. This file paraphrases the parts that matter at PR scale and maps each one to a PR, issue, commit, or review reply.

Most LRS material targets papers and memos. A PR body is usually 1 to 3 short paragraphs, so the ideas apply in miniature: one sentence can carry a whole introduction.

## 1. The reader, answered before drafting

LRS asks 5 questions before any draft: who reads it, why, what they know, what they'll do with it, and what makes them skeptical. For a PR, most answers are fixed:

- **Who:** a maintainer who knows the code far better than you and your environment not at all.
- **Why reading:** triage. They're deciding to merge, request changes, or close, often in under a minute.
- **What they'll do:** decide whether this change is worth their review time and the maintenance it adds.
- **Skepticism:** this varies per repo, and recon already collected it. The maintainer reasons for closing earlier PRs are this reader's documented doubts. Address the one that most likely applies to yours, explicitly.

## 2. Does the reader already care? That sets the length

LRS separates **background** from **motivation**. A reader who already cares about a subject (a *pre-motivated* reader) needs only the instability: the thing that's new, broken, or changed. Piling background on top can make them less motivated, because it delays the one thing they wanted to know.

A maintainer is pre-motivated about bugs in their own code. For a fix to a confirmed bug, the instability is the whole introduction: "`parse()` returns `None` on empty input."

Explaining what `parse()` is, or why parsing matters, spends their attention on things they know better than you.

LRS also sorts texts by function, and the function decides how much argument the text needs:

| Function | PR equivalent | What it needs |
|---|---|---|
| Inform | Docs fix, typo, dependency bump | The change, and one line of why if it isn't obvious |
| Solve a recognized problem | Fix for a confirmed issue | Instability, fix, evidence |
| Pose a problem, then solve it | Fix for something nobody reported; a behavior change | Add the cost: why leaving it costs the maintainer something |
| Argue against doubt | A feature, a reversal of an earlier decision, "works as designed" pushback | Add reasons, a stated warrant, and acknowledgment (sections 6 and 7) |

Cases that sit between rows, from the replays:

- **Your own issue, filed shortly before the PR with no maintainer reply:** pose-and-solve. Filing it doesn't make the problem recognized; a maintainer agreeing does.
- **A sub-gap inside someone else's confirmed issue:** solve-recognized, with a lineage sentence linking the issue and saying which part this covers.
- **Optimizations and size or speed wins with no bug:** pose-and-solve. The cost is the number you're improving.
- **Dependency and security bumps:** inform. Link the advisory or changelog.
- **Anything that reverses a deliberate earlier choice:** argue, whatever its size.

**When you need the cost,** an LRS problem is a destabilizing condition plus a cost the reader recognizes. State the cost in one clause, in the maintainer's terms: their users hit it, it regressed in a named release, it breaks CI 1 run in 20. Run the "so what?" test from their side, and keep asking until the answer lands on something they own. "I needed it" isn't their cost.

**Drama fails.** LRS warns that extreme consequences backfire, because readers suspect overselling. Cut "critical," "severe," and "major" unless a number stands behind them.

**Lineage answers "why wasn't this caught?"** Skeptical readers wonder why a problem persists if people already looked. One lineage sentence ("regressed in abc1234 when the parser went streaming") explains it and shows you read the history.

## 3. Characters: who the sentences are about

LRS: readers judge prose clear when the subjects of sentences are the characters they care about, and the verbs are the actions those characters take.

- **Make the code the character.** The maintainer cares about `PageList.prune`, the `--max-width` flag, the user-visible behavior. "This PR updates the function to..." puts the PR in the subject slot, which the maintainer doesn't care about. "`prune` now keeps the cursor page" does the same work with the right character.
- **Use names the reader already has.** LRS warns that readers don't adopt a new abstraction as a character from one definition. Agent-written PRs coin abstractions ("the sanitization layer," "the resolution pipeline") for things the codebase never named. Use the repo's identifiers and the issue's wording instead.
- **"I" is fine for what you did** ("I hit this on macOS," "I only tested Linux"). Keep it out of sentences about what the code does.
- **Free the buried verbs.** "Add handling for empty input" names a nominalization; "Handle empty input" names the action. Watch for `-tion`, `-ment`, `-ance` nouns and empty verbs (is, has, make, perform, provide), in titles especially. "There is a race between X and Y" becomes "X can read Y before Y initializes it."
- **Passive voice** hurts when it drops the agent the reader needs ("the cache is invalidated": by what?) and helps when it keeps the reader's character in the subject slot.

Two quick tests. First, read only the verbs and see whether they tell the story. Then skim the first 7 or 8 words of each sentence for a character the maintainer recognizes.

## 4. Index and stress: where the point goes

- **Index position** is the opening of any unit: the title for the PR, the first sentence for the body. Readers decide what the unit is about from what they find there, and experts use it to decide whether to keep reading. The title plus the first sentence should carry the current behavior and the change.
- **3 ways the index fails:**
  - There is none, because the body starts with setup.
  - It promises A and B while the body delivers C and D.
  - It's too abstract for its body, like "Improve parser robustness" over a one-line off-by-one fix.
- **Point-first is the default.** LRS reserves point-last for readers who would reject the point if they met it first. In PRs that's narrow: reversing a maintainer's earlier decision, or a fix whose approach looks wrong until the evidence lands. Then lead with the evidence and let the conclusion arrive.
- **Stress position** is the end of a sentence, where readers put the most weight. End the first sentence on the consequence ("...so the next write uses freed memory."), and the reader's next question becomes "what does this change?", which your next sentence answers.
- **Old before new.** Start each sentence with something already introduced (the function, the flag) and end with the new information. That's what makes 3 sentences read as one thought.
- **Numbers:** put the constants the reader can anchor to first, as an orientor, and the change last. "On the 10k-row fixture, parse time dropped from 820 ms to 95 ms" lands the result in the stress position.

## 5. Key terms, and the Frankenedit

LRS tracks **key term chains**: the terms the opening primes should recur where the reader expects them. At PR scale, pick one name for the bug, ideally the reporter's, and use it in the title, the body, the test name, and the commit subject. A PR titled "fix scrollback search crash" whose test is named `test_find_overlay_null` makes the reviewer translate.

LRS's **Frankenedit** is an opening that raises one problem while the body handles another, which readers experience as bait-and-switch. PRs can Frankenedit in two ways:

- **The diff drifts from the title.** Map every hunk to the stated problem. A hunk that doesn't map goes in its own PR, or gets an explicit line ("Also renames `x` to `count`, which the fix touches").
- **The description goes stale.** Review changes the fix, and the body still describes the first version. After every push in response to review, reread the body against the current diff and rewrite it for the current version, with no revision history (see "Replies to review comments" in `pr-copy.md`).

## 6. Argument: why the maintainer should believe it

Williams and Colomb break an argument into claim, reason, evidence, warrant, and acknowledgment-and-response. A bug-fix PR has all five:

| Part | In a PR | Where it comes from |
|---|---|---|
| Claim | This change fixes #N. | The title and first sentence |
| Reason | Because the bug's cause was X, and this removes X. | The cause sentence |
| Evidence | The test output. | `proof.md` |
| Warrant | The test exercises the path the reporter hit, so passing it means the reported bug is gone. | Red-green with `--expect`: the test fails on the unfixed code, for the reported reason |
| Acknowledgment and response | The alternative you passed on and why; the limits of what you checked. | You |

The warrant is the part maintainers silently doubt: "sure, your test passes, but does it test the bug?" A red-green proof answers that doubt without arguing. That's why the collapsed red-green block belongs in the PR. To check any warrant, ask whether the maintainer knows it, accepts it, and sees it applying here; if it looks shaky written as "whenever X, then Y," state it outright.

**The repo's own conventions are the strongest warrants for design choices.** "Matches how `load()` treats empty files" beats any general principle, because the maintainer already accepted it once.

LRS also says evidence should support conclusions without rehearsing the work process. In PRs, the work-process version is the bullet list that narrates the diff, or the "Test plan" that lists every command you ran. The reviewer can read the diff; give them the conclusion and the one piece of evidence that carries it.

## 7. When the reader sees a different problem

Two LRS moves fit the PRs and issues most likely to get pushback.

**Stasis and destabilization, with a lock-and-key fit.** Open on what the reader believes, then show what it misses. The belief you state has to be one this maintainer would actually sign, and your "but" has to hit that belief directly. A "but" that only restates your own position reads as plain denial. This is the reply to "works as designed." Concede what's true ("the 5 s default suits local runs"), then show the gap ("shared CI runners exceed it in 1 of 20 jobs").

**Manifest versus critical problem.** When the reader is invested in an obvious (manifest) problem, you have to change the question they're asking. Concede the manifest concern genuinely, pivot with a visible contrast word, then give one consequence that matters to both problems. LRS calls that a **dual consequence**, and notes the move can be short.

- **Feature PRs:** the maintainer's manifest concern is maintenance burden. Concede it, then show the cost of not having the feature in terms of their burden: duplicate issues about it, or user workarounds that break on upgrade. Keep the change small enough that the burden argument holds.
- **Issues a maintainer might read as user error:** concede the config looks unusual, then show the minimal repro on a clean config.
- **Disagreeing in review:** name the reviewer's concern before your own, give one concrete reason for your approach, tie it to their concern, and defer to their call. The maintainer owns the house.

## 8. Sentence pass

These are the LRS sentence-level checks, scaled to short text:

- Subject and verb near the start of each sentence and close together. If more than half a sentence passes before the first subject-verb pair, move the setup into a short orientor ("On Windows,") or cut it.
- No sentence over 30 words.
- Keep the body short without making it choppy. LRS warns that a run of short sentences hides how ideas connect. Join cause and effect into one sentence with a connector instead of splitting them: "`parse()` drops the last row because the loop stops one short."
- Connectors that name the logic: because, so, although, unless. "And" between two clauses that are really cause and effect hides the argument.
- Prefer connectors to noun chains held together by prepositions. "Provides a fix for the handling of the case of empty input" hides who acts and why.
- Passive voice when the old information belongs at the front ("This was introduced in abc1234"). Judge it by information flow.
- Parallel items in parallel form, short before long.

## 9. Text read in a row

LRS assumes a reader moving through prose. Much of a PR's text gets skimmed as one item among many. The title sits in a queue of 40 open PRs, commit subjects in `git log --oneline`, and replies in a batch of review threads. Full Stack Data Lab's checklist for bulk AI text ("Five Principles for Generating Readable AI Text in Bulk," https://fsdatalab.github.io/blog/agent-text-at-scale/) covers that reader, and 4 of its rules apply here.

- **The first 2 words carry the item.** Nielsen's eye-tracking work found that list readers often see only the first two words of each line. After the house prefix, put the word that sets this item apart from its neighbors: the identifier or the symptom. "`--max-width` counts display width" picks itself out of a queue; "Fix an issue with line wrapping" reads like every other formatter bug. The repo's form still wins (`fix(fmt):` stays), so this governs only the words after it.
- **One shape per list.** Readers parse a clause faster when it matches the shape of the one before it (Frazier et al., 1984). Give every commit subject in a series the repo's verb form and tense, and every table row the same columns. Every review reply gets the same skeleton: `Done in abc1234, <what changed>`, or `Done in patchset 3` on Gerrit. When every item shares a subject, drop it and open on the verb.
- **One word per concept.** ASD-STE100, the controlled English written for aircraft maintenance manuals, gives each word one meaning. That extends section 5's key-term chain from the bug's name to every noun: the component, the option, the failure. A body that says "cache" in one sentence and "store" in the next reads as two things. Use the repo's word everywhere the concept appears.
- **Vary only what differs.** Readers assume a difference between items means something (Mackinlay's expressiveness rule, borrowed from chart design). If one row of a platform matrix gives a version and the others don't, or one limit names a build and the next doesn't, the maintainer stops to ask why. Fill the same fields for every item, or say in a few words why one is different.

The checklist's first rule, open each item on its subject or verb, is section 3 at list scale. Its fifth rule, verbs whose connotation matches the page's purpose, survives in one form: name a failure with the verb that says what happens ("crashes," "hangs," "drops the last row"). Readers recognize charged words faster than neutral ones (Kousta et al., 2009), and "affects," "impacts," or "has issues with" make them read on to learn whether it's bad. Section 2's drama rule still holds, because it targets severity adjectives with no number behind them, and an accurate verb carries no such claim.

## Draft check, in order

Run this after drafting and before the maintainer-reviewer pass. The order follows how a maintainer reads: whether to read at all, whether to care, whether it's clear, whether to agree, and what to remember.

1. **Index and Frankenedit:** do the title and first sentence tell a maintainer what broke and what this changes? Would the title's first 2 words after the house prefix pick this PR out of the queue? Does every hunk in the diff map to that, and does the body match the current diff?
2. **Motivation and length:** which function in section 2 is this? For a recognized bug, delete background and any cost sentence the maintainer doesn't need. Otherwise, require one concrete cost in their terms, and no drama words without numbers.
3. **Characters:** are the subjects the code, the users, and the behavior, using names from the repo and the issue? No coined abstractions, no "this PR" as the actor, no buried verbs.
4. **Warrant and acknowledgment:** does the red-green block show the test exercises the reported bug? Is recon's most likely objection answered, with one alternative and one limit stated? If you're disagreeing, does your "but" hit what the maintainer actually believes?
5. **Key terms:** one name for the bug across title, body, test, and commit, and one word for every other concept the text names.
6. **Stress and sentences:** numbers and payoffs in the last slot of their sentences, then the pass in section 8.
7. **Lists:** read only the first 2 words of each commit subject, table row, and list item. Does each say what sets it apart? Do the items share one shape, and does every difference between them mean something (section 9)?
