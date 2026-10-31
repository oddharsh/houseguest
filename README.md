# houseguest

A Claude Code plugin for contributing to repos you don't own. It reads the house rules first, matches how the place is kept, and proves the fix works before asking to merge.

```
/plugin marketplace add oddharsh/houseguest
/plugin install houseguest@houseguest
```

Needs `gh` (authenticated), `git`, and `jq`; Gerrit projects also need `curl`. To try it for one session from a clone: `claude --plugin-dir ./houseguest`.

## Why it exists

Maintainers close low-effort PRs for 3 reasons. houseguest runs a phase against each one.

| Why the PR gets closed | What catches it |
|---|---|
| It duplicates or contradicts a decision already made | Intent check and recon, before any code |
| The code looks foreign to the codebase | Style fingerprint, plus the repo's own linters on your diff |
| The description claims things nobody checked | Red-green proof, plus a final check on base and HEAD |

## How it works

1. **Intent check.** Decides whether the behavior is deliberate, without being told anyone thinks it's a bug.
2. **Recon.** AI policy, duplicates, rejected attempts, open PRs on your files, fixes already upstream. Ends in GO, DOCS, or stop.
3. **Style.** Fingerprints the repo's formatters, linters, and commit conventions.
4. **Write.** The smallest change that fully fixes it, one concern per PR.
5. **Proof.** The test fails without the fix, passes with it, covers every hunk, and survives 10 reruns.
6. **Copy.** PR text sized to the repo's pre-LLM baseline.
7. **Maintainer review.** A busy maintainer's read of the diff, for up to 3 rounds. A second agent checks each blocking finding against the code before it costs a round.
8. **Final check.** Reproduces each problem exactly as the report posed it, on base and HEAD.

Each phase runs in its own subagent, so the agent that wrote the fix never grades its own proof. Phases talk only through a ledger in `.git/houseguest/<branch>/`, which git never tracks.

A hook blocks `gh pr create` until every phase has passed on HEAD with its seal intact. Gerrit projects (Chromium, Go, Android, Qt, Wikimedia) get the same gate on `git cl upload`, `git review`, `repo upload`, and pushes to `refs/for/`.

Nothing reaches upstream without your yes.

## What's in it

| Piece | Job |
|---|---|
| `skills/oss-pr` | The phases, and the references they read |
| `agents/` | `intent-check`, `maintainer-review`, `finding-check`, `final-check`, plus `second-fix` and `compare` for an optional blind second opinion |
| `hooks/gate.sh` | The PR gate |
| `skills/oss-pr/scripts/` | 15 helpers, listed below |

<details>
<summary>The 15 scripts, and the question each one answers</summary>

| Script | Question |
|---|---|
| `gather.sh` | What does recon need from upstream, in one pass? |
| `policy.sh` | What's the repo's AI policy, wherever it lives? |
| `codex.sh` | Which written rule sets (`AGENTS.md`, `REVIEW.md`, style guides) govern this change? |
| `cites.sh` | Do the files, lines, and functions a report cites exist? |
| `channels.sh` | Could a beta, canary, or nightly build behave differently for this bug? |
| `preview.sh` | Will reviewers get a preview build of a fork PR? |
| `prdefaults.sh` | What has an existing PR already settled before you add to it? |
| `recheck.sh` | What changed upstream since recon? |
| `followup.sh` | Which of your open PRs and issues are waiting on you? |
| `house.sh` | What enforces style in this repo, and how? |
| `housecheck.sh` | Does your diff pass the house rules and look like PRs that got merged? |
| `title.sh` | Does your PR or issue title match the ones this repo accepts? |
| `checks.sh` | Which property tests, fuzzers, or proofs does the repo already run? |
| `prove.sh` | Does the test fail without the fix and pass with it? |
| `receipt.sh` | Were the ledger's verdicts edited by hand? |

</details>

## Does it work

- **PR length.** Outside contributors' PR bodies in 12 well-run repos had a median of 30 words before LLMs and 95 since mid-2025. houseguest writes to the old baseline. [research/pre-llm-prs.md](research/pre-llm-prs.md)
- **Reviewer recall.** Replayed against 23 public PRs, the reviewer named the maintainer's reason on 12 of 12 rejected ones. [research/reviewer-evals.md](research/reviewer-evals.md)
- **Reviewer noise.** It still raised a blocking finding on 8 of 11 PRs merged clean (a few of those findings hold up). `research/evals/run.sh` rescores every prompt change. The finding check exists to cut this number and hasn't been scored yet.
- **Design sources.** Astro's factory, StrongDM's holdout scenarios, loki-mode's receipts, and others. [research/software-factories.md](research/software-factories.md)

## Disclosure

Every PR it drafts ends with one line: "AI-assisted. Recon, red-green check, and PR text by houseguest," trimmed to the phases that ran. It uses the repo's own disclosure form when one exists, and stops when a repo bans AI contributions.

## Precedence and credits

The repo's tooling beats its written rules, which beat nearby code, which beat houseguest's fallback defaults. Those fallbacks adapt [anti-slop](https://github.com/dmmulroy/anti-slop), [deslop](https://github.com/maharshi365/deslop), [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT), and [ponytail](https://github.com/DietrichGebert/ponytail)'s laziness ladder by DietrichGebert (MIT), and apply only to lines your diff touches. The finding check and the reviewer's list of things that aren't findings adapt Anthropic's [code-review](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-review) plugin (Apache-2.0).

## License

MIT. See [LICENSE](LICENSE).
