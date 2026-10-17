# How outside contributors wrote PRs before LLMs

Before ChatGPT, merged PRs from outside contributors to 12 well-run repos had a median body of 207 characters, about 30 words. Since mid-2025, the median is 671 characters. The newer PRs also carry 2.5x as many headings, twice as many bullet lists, and 3x as much bold text.

This page is why the tool writes PR text the way it does. It targets each repo's pre-2023 baseline and borrows the moves those PRs made, because maintainers learned to read that shape long before they learned to distrust the newer one.

## Method

- **Repos:** ripgrep, tokio, bat, flask, black, django, neovim, prettier, fzf, cobra, rails, curl. They span 6 languages, and each has an active review culture and lots of outside contributions. React was in the original list, but GitHub's search rejected queries against it.
- **Eras:** the 100 most recent merged PRs created before 2022-11-30 (ChatGPT's launch), and the 100 most recent created after 2025-06-01. Some repos had fewer.
- **Filter:** outside contributors only (GitHub's `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, `FIRST_TIMER`, `NONE` associations), bots removed, HTML comments and checklist lines stripped. That left 555 pre-era and 440 recent PRs.
- **Reproduce:** `./fetch.sh data && python3 -I analyze.py data`. Results will drift as new PRs merge.

## What changed

| | 2019 to 2022 | mid-2025 on |
|---|---|---|
| Median body | 207 chars, 30 words | 671 chars, 95 words |
| Has a markdown heading | 25% | 62% |
| "Summary/Changes/Motivation"-style heading | 21% | 42% |
| Bullet list | 19% | 40% |
| Bold text | 3% | 10% |
| Em dash | 0% | 7% |
| Mentions testing | 23% | 53% |
| Hedges ("I think," "not sure," "might") | 9% | 5% |
| Thanks or sorry | 5% | 2% |
| First-person "I" | 23% | 23% |

Templates confound some of this, so the per-repo view matters. Black, Rails, and Tokio had PR templates in both eras, and their heading rates barely moved (94% to 84%, 84% to 82%, 67% to 62%). Untemplated repos moved the most: bat went from 0% to 47% of bodies with headings, and its median body grew from 134 to 705 characters. ripgrep went from 1% to 12% and from 86 to 299 characters. Django added a PR template between the eras, so its jump (2% to 94%) says little about authors.

Two numbers cut against the easy story. Contributors mention testing more than twice as often now, which is a real improvement when the mention carries evidence. And first-person writing held steady, so recent PRs are just as personal; what disappeared is the hedging. Contributors stopped admitting what they hadn't checked.

## What the earlier PRs did

Reading about 40 pre-era bodies from untemplated repos turned up the same handful of moves:

1. **They opened on current behavior or raw evidence.** The first line described what the code does today, or pasted the warning the analyzer printed. None opened with a bolded summary of themselves.
2. **They said how the author ran into it.** One sentence of real stake: a tool they were building, a coworker it confused, a new machine where it broke again. Generated PRs rarely carry this, because there was no such moment.
3. **They linked lineage.** The commit that caused a regression, the earlier PR that was reverted, the same fix applied last year.
4. **They named one alternative and why they passed,** usually in a single sentence.
5. **They verified in one sentence, with a number,** such as a binary size before and after.
6. **They admitted limits:** relying on the existing tests, unfamiliarity with an area, which CI they were waiting on.
7. **They offered the maintainer a specific choice,** like dropping one part of the change if the maintainer preferred.
8. **They credited people,** such as the reporter, or sprint mentors on a first contribution.

Headings were rare outside repos whose templates required them. Most bodies were 1 to 3 short paragraphs.

## What the recent PRs added

The patterns that grew most, read across the recent sample:

- Bold thesis sentences opening the body.
- Section scaffolding ("Context & Purpose," "Value," "Scope philosophy," "Root Cause," "Test plan") around fixes a few lines long.
- Test plans listing checks a reviewer wouldn't need, and blanket lines like "all existing tests pass" or "no behavioral changes."
- Annotations inside code blocks, and prose labels like "Honest scope:".
- Inventories of file and line locations the PR doesn't touch.
- Diff narration: one bullet per change the reviewer can already see.
- Promotion of the author's other projects inside the PR body.

Recent PRs aren't all generated, and some read well. Neovim's Problem/Solution headings, for example, follow a documented project convention, so they're native style. The point is narrower: these patterns grew between the eras, and a PR that leans on them reads like the growth.

## How the tool uses this

- `gather.sh` pulls each target repo's own pre-2023 outside PRs, reports their median length, and shows 5 as voice exemplars. A repo with no pre-2023 history falls back to the shorter half of its recent PRs.
- `pr-copy.md` targets that baseline length, builds the body from the 8 moves above, and keeps the full red-green output in a collapsed `<details>` block. That way the proof stays complete while the prose stays short.
- The stake sentence has to be true, so the tool asks the user how they hit the bug instead of writing one.

## Caveats

- 12 repos and about 1,000 PRs make a directional sample. Results will differ for frontend, data, or infrastructure repos.
- The pre-era sample skews to 2021 and 2022, since the fetch takes the most recent 100 before the cutoff.
- No single PR here is labeled as AI-written, and none should be. The comparison is between eras.
- GitHub's author-association field reflects a contributor's status at query time, so a few pre-era "outside" contributors may have since become members.
