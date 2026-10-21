# houseguest

When you contribute to someone else's repo, you're a guest in their house. houseguest makes Claude act like a good one: it reads the house rules first, matches how the place is kept, and proves its fix works before asking to merge.

Maintainers close low-effort PRs for 3 reasons: the work duplicates or contradicts something already decided, the code looks foreign to the codebase, or the description claims things nobody checked. The plugin runs a phase against each one, writes what it found to a ledger inside `.git`, and blocks `gh pr create` until the ledger is complete.

Each phase runs in its own subagent, and the phases talk only through the ledger. An agent that's sure there's a bug reads the docs looking for confirmation, and one that wrote the fix grades its own proof; isolation keeps each phase from inheriting the last one's conclusions. The first check never learns there's a bug at all: it gets a neutral description of the behavior and reads the docs, tests, and history to decide whether the maintainers meant it.

## What's in it

| Piece | What it does |
|---|---|
| `skills/oss-pr` | The phases: intent check, recon, style fingerprint, write, proof, copy, and maintainer review, each launched as its own subagent |
| `agents/intent-check` | Decides whether a behavior is intended without being told anyone thinks it's a bug: reads the docs, tests that assert it, the commit and PR that introduced it, and earlier maintainer discussion, then writes a verdict (INTENDED, UNINTENDED, NO RECORD, or CONFLICTING) with a quote behind each claim. It also says whether the page a user reads first explains the behavior. Recon decides from it: the PR gate won't open a PR against an INTENDED verdict unless the choice rests on a factual error, and when the choice was never written down where users look, the job becomes a docs change so the next contributor doesn't make the same mistake |
| `agents/maintainer-review` | Reviews the diff and drafted body as a busy maintainer would, from the ledger alone, before the user sees the PR |
| `scripts/gather.sh` | One pass over the upstream repo, before you clone: AI policy, contributor gates, workflows that police PRs, duplicate issues and PRs, open PRs touching your files, the commits that shaped them, the maintainer's reason for each rejected attempt, human-only length medians, and your own history in the repo. `--as-of` replays it at any past moment |
| `scripts/policy.sh` | Finds the AI/LLM policy wherever it lives: anywhere in the repo, the org's `.github` repo, and contribution guides linked from the README or templates (image-rs keeps its LLM policy in a separate repo). Also checks whether maintainers have applied a rule in earlier threads. Ends with a verdict and every source checked |
| `scripts/channels.sh` | Before anyone builds a beta, canary, or head to retry a bug, checks whether those builds differ from prod in any way that could matter: commits touching the bug's files, commit messages naming it, or a changed package manifest. Reads npm dist-tags, crates.io, PyPI, GitHub releases and prereleases, and beta/canary/next/nightly branches, and skips stale branches and older lines. Only the builds that differ get a repro |
| `scripts/prdefaults.sh` | Before adding to someone else's open PR, reads the defaults it has already set: who may push, what reviewers asked for and settled, the branch's commit conventions, the changelog and tests it carries, the style of its added lines, and failing CI. Work added to a PR extends the author's choices instead of resetting them |
| `scripts/codex.sh` | Finds every written rule set that governs a change: agent rule files at any depth (`AGENTS.md`, `CLAUDE.md`, Cursor, Copilot, Windsurf, Cline, Kiro, and others), human style guides and review docs, the org's `.github` repo and dev-guide repos, and guides the contribution docs link to. Marks which apply to your files, from ancestor folders and `globs:`/`applyTo:` frontmatter |
| `scripts/followup.sh` | Lists your open PRs and issues on others' repos where a maintainer spoke last, so questions don't go unanswered until a stale bot closes the thread |
| `scripts/house.sh` | Reads a clone's house rules: the formatters and linters it configures (including ones only declared in devDependencies, run with the flags the repo's own check script passes, like oxlint's `--type-aware`), the CI steps that enforce style, `.editorconfig`, license headers, commit and changeset conventions |
| `scripts/housecheck.sh` | Checks your diff against them: runs the repo's own tools on only your files, then flags what review comments usually flag (comment placement, repeated constants, removed guards, unfamiliar assertions, oversized changesets), and measures the diff against PRs other people got merged in the repo: too large, more than one concern, a new dependency, or a new option nobody asked for. Flags get fixed or acknowledged with a reason |
| `scripts/title.sh` | Learns a repo's PR title conventions from titles other people got merged (prefix, length, which features they use) and flags what yours does that theirs rarely do: chained clauses, comparisons to other products, "as ..." and ", not X" clauses, excess length. The PR gate rechecks `--title` |
| `scripts/prove.sh` | Red-green proof: the test fails without your fix (for the right reason) and passes with it, N runs each, bound to a commit SHA |
| `hooks/gate.sh` | Blocks `gh pr create` in forks until recon said GO, the intent check found no deliberate choice in the way, the style note exists, and the proof passed on HEAD |

## Precedence

Repo tooling beats written rules, which beat observed conventions in nearby code, which beat the fallback defaults, which beat the agent's own habits. The deslop principles are a cross-language translation of [anti-slop](https://github.com/dmmulroy/anti-slop) and [deslop](https://github.com/maharshi365/deslop), plus a section on agent-specific habits, and they only apply where the repo is silent. The other fallback, `defaults.md`, adapts [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT) for a contributor working in someone else's codebase: every rule applies only to lines your diff touches. The writing phase starts from `lean.md`, which adapts [ponytail](https://github.com/DietrichGebert/ponytail)'s laziness ladder by DietrichGebert (MIT) for a guest: the smallest PR that fully solves the issue, one concern per PR, and the same ladder in the reviewer pass.

## Why the PR text reads the way it does

Before LLMs, outside contributors' PR bodies in 12 well-run repos had a median of 30 words; since mid-2025 the median is 95, with 2.5x the headings. The tool writes to each repo's pre-2023 baseline and borrows the moves those PRs made. Method, numbers, and caveats: [research/pre-llm-prs.md](research/pre-llm-prs.md).

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

`.git/houseguest/<branch>/` holds `intent.md`, `recon.md`, `style.md`, `proof.md`, logs, and the final `pr-body.md`. It's the only thing the phases share: each subagent reads the notes its phase needs and writes its own, and the intent check runs before anything else is written there. Git never tracks anything under `.git`, so none of it can leak into the upstream repo, and it disappears with the clone.

## Disclosure

Every PR and issue it drafts ends with one line: "AI-assisted. Recon, red-green check, and PR text by houseguest," trimmed to the phases that actually ran. Where a repo specifies its own disclosure form, houseguest fills in theirs instead. Where a repo bans AI-assisted contributions, recon stops the job.

## License

MIT. See [LICENSE](LICENSE).
