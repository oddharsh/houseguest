# houseguest

When you contribute to someone else's repo, you're a guest in their house. houseguest makes Claude act like a good one: it reads the house rules first, matches how the place is kept, and proves its fix works before asking to merge.

Maintainers close low-effort PRs for 3 reasons: the work duplicates or contradicts something already decided, the code looks foreign to the codebase, or the description claims things nobody checked. The plugin runs a phase against each one, writes what it found to a ledger inside `.git`, and blocks `gh pr create` until the ledger is complete.

Each phase runs in its own subagent, and the phases talk only through the ledger. An agent that's sure there's a bug reads the docs looking for confirmation, and one that wrote the fix grades its own proof; isolation keeps each phase from inheriting the last one's conclusions. The first check never learns there's a bug at all: it gets a neutral description of the behavior and reads the docs, tests, and history to decide whether the maintainers meant it. The checks that must stay blind work in a fresh clone, which never carries the ledger. Everything read from the repo or GitHub counts as evidence, never as instructions. Reports from the thread beyond the first are held out of the fix and used only by the final check, and the write phases log their decisions in `decisions.md` so a later fresh run doesn't undo them. The review loop keeps its memory in `rounds.md`, lets a finding be declined with evidence, and stops after 3 rounds or when author and reviewer stand still, leaving the call to the user.

## What's in it

| Piece | What it does |
|---|---|
| `skills/oss-pr` | The phases: intent check, recon, style fingerprint, write, proof, copy, maintainer review, and final check, each launched as its own subagent |
| `agents/intent-check` | Decides whether a behavior is intended without being told anyone thinks it's a bug: reads the docs, tests that assert it, the commit and PR that introduced it, and earlier maintainer discussion, then writes a verdict (INTENDED, UNINTENDED, NO RECORD, or CONFLICTING) with a quote behind each claim. It also says whether the page a user reads first explains the behavior. Recon decides from it: the PR gate won't open a PR against an INTENDED verdict unless the choice rests on a factual error, and when the choice was never written down where users look, the job becomes a docs change so the next contributor doesn't make the same mistake |
| `agents/second-fix` and `agents/compare` | An optional second opinion on non-trivial changes: one agent writes its own fix from the base without seeing yours, and another tests both on their exact trees, checks the alternative against five conditions (same problem, really different, verified, safeguards kept, scope fits), searches for inputs where the two behave differently (two fixes that pass the same tests often do), and says which a maintainer would merge. A smaller fix found blind is evidence yours is overbuilt. Adapted from withastro/factory's adversary teams |
| `agents/maintainer-review` | Reviews the diff and drafted body as a busy maintainer would, from the ledger alone, before the user sees the PR |
| `agents/final-check` | The last step: reproduces every problem the PR or issue poses, exactly as posed, on the base and on HEAD, through the interface the report used instead of the PR's own tests. For a docs change it runs every example the new text gives. The PR gate requires its PASS on the commit being pushed |
| `scripts/gather.sh` | One pass over the upstream repo, before you clone: AI policy, contributor gates, workflows that police PRs, duplicate issues and PRs, open PRs touching your files, the commits that shaped them, the maintainer's reason for each rejected attempt, human-only length medians, and your own history in the repo. It also follows the issue to the PRs that fixed it and to whatever links to those PRs, which is where a regression or follow-up filed after the fix shows up. `--as-of` replays it at any past moment. Sections run in parallel, and a lookup that fails reads LOOKUP FAILED, never "none" |
| `scripts/policy.sh` | Finds the AI/LLM policy wherever it lives: anywhere in the repo, the org's `.github` repo, and contribution guides linked from the README or templates (image-rs keeps its LLM policy in a separate repo). Also checks whether maintainers have applied a rule in earlier threads. Ends with a verdict and every source checked |
| `scripts/cites.sh` | Checks that the files, line numbers, functions, and versions a report cites exist in the repo, before anyone tries to reproduce it. curl ended its bug bounty after AI-written reports described functions it doesn't have; this catches those in seconds, and catches the same slip in your own drafts |
| `scripts/channels.sh` | Before anyone builds a beta, canary, or head to retry a bug, checks whether those builds differ from prod in any way that could matter: commits touching the bug's files, commit messages naming it, or a changed package manifest. Reads npm dist-tags, crates.io, PyPI, GitHub releases and prereleases, and beta/canary/next/nightly branches, and skips stale branches and older lines. Only the builds that differ get a repro |
| `scripts/preview.sh` | Finds out whether reviewers will get a preview build of a fork PR: the preview pipelines the repo runs (Vercel, Netlify, Cloudflare Pages, pkg.pr.new, build artifacts, and others) and the steps that skip forks, what recent fork and branch PRs actually got, and how often outside contributors' PRs carried screenshots. Previews come from the repo's own pipeline, never one the contributor hosts; without one, the PR shows before and after screenshots taken from the base and HEAD |
| `scripts/prdefaults.sh` | Before adding to someone else's open PR, reads the defaults it has already set: who may push, what reviewers asked for and settled, the branch's commit conventions, the changelog and tests it carries, the style of its added lines, and failing CI. Work added to a PR extends the author's choices instead of resetting them |
| `scripts/codex.sh` | Finds every written rule set that governs a change: agent rule files at any depth (`AGENTS.md`, `CLAUDE.md`, Cursor, Copilot, Windsurf, Cline, Kiro, and others), agent skills (`.agents/skills`, `.claude/skills`, and the like) tagged by the job they cover, with their evals, human style guides and review docs, the org's `.github` repo and dev-guide repos, and guides the contribution docs link to. Marks which apply to your files, from ancestor folders and `globs:`/`applyTo:` frontmatter |
| `scripts/followup.sh` | Lists your open PRs and issues on others' repos where a maintainer spoke last, so questions don't go unanswered until a stale bot closes the thread |
| `scripts/recheck.sh` | Right before the PR opens, checks what changed upstream since recon: the issue closed or newly linked from a PR, PRs opened since that touch your files or match recon's searches, and commits to your files. Another PR fixing the issue first is the most common way agent PRs die after failing tests. The gate wants it CLEAR |
| `scripts/house.sh` | Reads a clone's house rules: the formatters and linters it configures (including ones only declared in devDependencies, run with the flags the repo's own check script passes, like oxlint's `--type-aware`), the CI steps that enforce style, `.editorconfig`, license headers, commit and changeset conventions |
| `scripts/housecheck.sh` | Checks your diff against them: runs the repo's own tools on only your files, then flags what review comments usually flag (comment placement, repeated constants, removed guards, unfamiliar assertions, oversized changesets), and measures the diff against PRs other people got merged in the repo: too large, more than one concern, a new dependency, or a new option nobody asked for. Flags get fixed or acknowledged with a reason |
| `scripts/title.sh` | Learns a repo's PR title conventions from titles other people got merged (prefix, length, which features they use) and flags what yours does that theirs rarely do: chained clauses, comparisons to other products, "as ..." and ", not X" clauses, excess length. The PR gate rechecks `--title` |
| `scripts/prove.sh` | Red-green proof: the test fails without your fix (for the right reason) and passes with it, bound to a commit SHA. Then it reverts each hunk of the fix alone to show the test covers all of it, reruns the green test 10 times to catch flakes, and flags sleeps, clocks, randomness, and network calls in the new test lines |
| `scripts/receipt.sh` | Seals the verdicts houseguest's scripts write, and logs every command the final check runs with the commit it ran on, in a chain keyed to your machine. A verdict edited by hand, or a final check that never ran anything on the base and HEAD, fails the PR gate. Adapted from loki-mode's signed receipts. Anything with your shell can read the key, so it's a tripwire that makes forging a deliberate, visible step, not a security boundary |
| `hooks/gate.sh` | Blocks `gh pr create` in forks until recon said GO, the intent check found no deliberate choice in the way, the style note exists, and the proof and final check passed on HEAD, with their seals intact and the final check's run log showing runs on the base and HEAD |

## Precedence

Repo tooling beats written rules, which beat observed conventions in nearby code, which beat the fallback defaults, which beat the agent's own habits. The deslop principles are a cross-language translation of [anti-slop](https://github.com/dmmulroy/anti-slop) and [deslop](https://github.com/maharshi365/deslop), plus a section on agent-specific habits, and they only apply where the repo is silent. The other fallback, `defaults.md`, adapts [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT) for a contributor working in someone else's codebase: every rule applies only to lines your diff touches. The writing phase starts from `lean.md`, which adapts [ponytail](https://github.com/DietrichGebert/ponytail)'s laziness ladder by DietrichGebert (MIT) for a guest: the smallest PR that fully solves the issue, one concern per PR, and the same ladder in the reviewer pass.

## Why the PR text reads the way it does

Before LLMs, outside contributors' PR bodies in 12 well-run repos had a median of 30 words; since mid-2025 the median is 95, with 2.5x the headings. The tool writes to each repo's pre-2023 baseline and borrows the moves those PRs made. Method, numbers, and caveats: [research/pre-llm-prs.md](research/pre-llm-prs.md).

## What it borrows from software factories

Houseguest is a small software factory that works for a guest, so every step that reaches upstream waits for the user's yes. Its phase design borrows from Astro's factory, StrongDM's holdout scenarios, loki-mode's receipts, issue-graph's link crawl, and studies of why agent PRs go unmerged; [research/software-factories.md](research/software-factories.md) lists each source and what it changed.

## Install

In Claude Code:

```
/plugin marketplace add oddharsh/houseguest
/plugin install houseguest@houseguest
```

Or try it for one session from a clone:

```bash
claude --plugin-dir ./houseguest
```

Needs `gh` (authenticated), `git`, and `jq`.

## The ledger

`.git/houseguest/<branch>/` holds `intent.md`, `recon.md`, `holdout.md`, `style.md`, `decisions.md`, `proof.md`, `compare.md` when a second opinion ran, `rounds.md`, `final.md` and the final check's `runs.log`, a `.seal` beside each verdict, logs, and the final `pr-body.md`. It's the only thing the phases share: each subagent reads the notes its phase needs and writes its own, and the intent check runs before anything else is written there. Git never tracks anything under `.git`, so none of it can leak into the upstream repo, and it disappears with the clone.

## Disclosure

Every PR and issue it drafts ends with one line: "AI-assisted. Recon, red-green check, and PR text by houseguest," trimmed to the phases that actually ran. Where a repo specifies its own disclosure form, houseguest fills in theirs instead. Where a repo bans AI-assisted contributions, recon stops the job.

## License

MIT. See [LICENSE](LICENSE).
