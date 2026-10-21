# Phase 1: Recon

Recon answers one question before any code exists: would a maintainer of this repo want this contribution, from this person, right now? Most closed PRs could have been predicted from data that was public the whole time.

## Gather

Recon runs before you clone. Point the script at the upstream repo:

```bash
bash "<skill-dir>/scripts/gather.sh" --repo <owner/name> --issue <N> \
  --files <comma-separated paths you expect to touch> \
  --q "<component symptom>" --q "<another phrasing>"
```

- **Searches:** GitHub ANDs the words inside one search, so keep each `--q` to 1 to 3 words and give each phrasing its own `--q`. Phrase them the way a maintainer would title the issue (`scrollback crash`, `custom media targets`). A duplicate titled differently is still a duplicate, so try at least 2.
- **`--files`:** this is the most reliable duplicate check. It lists open PRs that touch the same files, and the recent commits on each file. Guess the files from the issue and a quick look at the repo tree if you haven't written code yet, then rerun once you have a diff.
- **Reruns:** add `--search-only` to repeat just the searches.
- Inside a clone, it reads docs from disk instead.
- The dump opens with an **AI policy sweep** (`scripts/policy.sh`, also runnable alone). It reads the repo's docs anywhere in the tree, the owner's `.github` repo, and contribution guides linked from the README, CONTRIBUTING, or templates, including guides in other repos. Then it checks earlier threads for maintainers applying an AI rule. It ends with one verdict: RULE FOUND, MENTIONS ONLY, or NONE FOUND, plus every source it checked.

## The AI policy comes first

Settle this before anything else, because it decides whether houseguest may write anything the maintainer will read.

- **RULE FOUND:** read every quoted passage in full, at its source. Quote the binding rule in `recon.md`, with its path. Then apply it:
  - Bans AI-assisted contributions: STOP.
  - Requires human-written descriptions or comments (WPT, image-rs): the job switches to **author mode** (see `pr-copy.md`). Houseguest checks and suggests; the user writes every word the maintainer reads.
  - Requires disclosure in a set form: use that form.
  - Requires LLM output to be quoted, labeled, or collapsed: follow the format exactly.
- Maintainer comments in the sweep show how strictly the rule is applied. If they've pushed back on AI-shaped contributions recently, say so in the note, because it raises the bar for everything else.
- **MENTIONS ONLY** or **NONE FOUND:** write that verdict and the sources checked into `recon.md`. If the README or CONTRIBUTING links to a contribution guide the sweep couldn't read (a site behind a login, a PDF), open it yourself before deciding.

Never decide GO with the AI policy line blank.

The dump is raw. Read the files it points at, in this order:

1. Every source the AI policy sweep quoted (see above).
2. CONTRIBUTING, HACKING, or DEVELOPMENT in full, including its section on issues and PRs. Gate rules hide in ordinary sentences ("please engage on the issue first"), so read them yourself; the pattern match in the dump only gives hints.
3. Any `AGENTS.md` or `CLAUDE.md`, both at the root and in the directories you'll touch (fetch nested ones by path until you clone). These are the maintainers telling an agent how to behave in their repo.
4. The PR template, and any workflow the dump lists under "Workflows that police PRs." Those workflows enforce the template, so they decide what the body must contain.
5. The issue thread and every linked PR, open or closed. For any open PR that matches, read its diff and its maintainer comments, not just its title.
6. In a docs repo (MDN, a docs site), the writing guidelines for the page type you're editing. They decide where new text belongs.

## Check intent and lineage

Before deciding, look at why the code is the way it is. A change that undoes a deliberate choice needs the maintainer's agreement first. The exception: the choice rests on a factual error you can show (it misreads a spec, or assumes an API that doesn't exist), and the repo sends bug fixes straight to a PR. Then GO, and make the error the center of the PR body.

- Read the commits the dump lists for your files (`--files`). Open the one that introduced the behavior you're changing, and its PR. If its message or review discussion says the behavior is intentional, treat your change as reversing a decision.
- Search the docs (README, `docs/`, `website/`, the API reference) for the behavior. Look for two things: text describing it as intended, and an existing option that already gets the user what they want. An escape hatch the docs already offer usually means a maintainer will point to it instead of merging.

## Predict the objections

Write the 3 objections this repo's maintainers would most likely raise, each with its basis (a doc, a closed PR's reason, a commit, a detail of the change). Use the rejection reasons in the dump; they are this reader's recorded doubts.

**If the top objection would close the PR or issue** (duplicate, breaking change, works as designed, needs discussion first, out of scope), the decision can't be GO. Either fix the cause or decide STOP or ASK. Changing the framing doesn't fix the cause: a report against a recorded maintainer decision is still against it when it's filed as a feature request. Only new evidence the decision didn't weigh justifies ASK, posted in the thread where the decision was made.

## Check what the report cites

Before reproducing anything, check that what the report names exists:

```bash
bash "<skill-dir>/scripts/cites.sh" --issue <N> --repo <owner/name>   # in the clone; --file <draft> for text not on GitHub
```

It checks each file path (and `:line`), each function or identifier in backticks or followed by `()`, and each version against the tree. curl ended its bug bounty in 2026 after a flood of AI-written reports, one of which came with GDB sessions and register dumps for a function curl doesn't have. A MISSING name doesn't prove the report wrong (it may be the reporter's own code, or another version), but it's the first thing to settle, and it goes in recon.md. Run it on the user's own issue draft too: a draft citing a function that doesn't exist is the fastest way to lose a maintainer.

## Check the other builds before reproducing

Prod is the build the user runs. Head, beta, canary, next, and nightly builds may already fix the bug, or break it differently. Find out which of them changed anything relevant before building any of them:

```bash
bash "<skill-dir>/scripts/channels.sh" --repo <owner/name> --package <npm name, crates:name, or pypi:name> \
  --paths <comma-separated files or folders where the bug lives> --q "<component symptom>"
```

- **What it finds:** prod (npm's latest, the newest stable crates.io or PyPI version, the newest GitHub release, or the highest version tag; or `--prod <version|tag|sha>` for what the user actually runs). Pass `--prod` whenever the user runs something else: a source build (the commit they built), an older pinned version, or a version the script couldn't map to a commit (it says so and stops rather than guess). Then head, branches named beta/canary/next/nightly/develop, the newest GitHub prerelease, and npm dist-tags. Branches last touched before prod shipped, and dist-tags for older lines (`legacy`, `backport`), are left out because they aren't newer builds.
- **What counts as a difference:** a commit since prod that touches `--paths`, a commit message containing every word of a `--q`, or a change to the package manifest above `--paths`. It compares on GitHub, so nothing is cloned or built for this step.
- **Then reproduce on prod, plus every build in its REPRODUCE ON line, and nothing else.** A build marked SAME or skipped can't behave differently for this bug, so the prod result stands for it. Prefer published artifacts (`npx pkg@canary`, `pip install pkg==<pre>`, a nightly release's assets) over building from source. Build from source only for head, and only when it's marked DIFFERS and nothing published contains those commits.
- **Read the listed commits before building.** DIFFERS means a commit touched your paths or named your terms; it doesn't mean the behavior changed. A repo-wide refactor that passes through your file rarely matters; a commit that changes the logic your repro runs does. Build only when at least one listed commit could change the result, and say which in recon.md. In a replay over 66 past issues, 12 of the 24 builds marked DIFFERS had only commits like "Give borrowed string bytes a lifetime" or "Remove dead code from the re-export hubs": real changes to the file, none to the bug.
- **ONLY IF FLAG-GATED:** an experimental build of a commit already listed. Reproduce on it only when your code path checks a feature flag.
- **ONLY IF DEPENDENCY-RELATED:** only the package manifest changed. Reproduce on it only when the bug could come from a dependency.
- **READ THE COMMITS FIRST (sweeps only):** every listed commit is a cleanup, rename, format, or docs change. Skim them; reproduce only if one could change the behavior.
- **UNKNOWN:** the script couldn't map a build to a commit or compare it. Reproduce on it.
- **Choosing `--paths`:** the files in the stack trace, the module named in the error, or the files you expect to change. Too narrow misses the fix; a whole package root is fine. Add `--as-of` when replaying an old issue.

Results decide the job. Fixed on head but not in prod: STOP for a PR, and for an issue, look for the fixing commit and STOP (or ask about a backport per "Release lines" below). Reproduces everywhere it was run: GO, and the issue names each build. A build that fails differently: describe both failures.

## Decide: go, stop, or ask first

**Stop** (report with links, write the note, end the job) when any of these hold:

- The repo bans AI-assisted contributions, or requires something the user can't honestly provide.
- An open PR already makes this change, or a superset of it. This holds whoever opened it (a bot, a maintainer, another contributor) and whatever state its CI is in. Maintainers usually finish their own bot's PR rather than review a second one. Offer to help on that PR instead: review it, test it, or add the missing piece the way `existing-pr.md` describes (`DECISION: JOIN`).
- A maintainer closed the issue as won't-fix, or closed a previous PR for this change with a reason that still applies. Quote the reason.
- The bug no longer reproduces on a build `channels.sh` marked DIFFERS (head, canary, nightly). Name the commit that fixed it; its list of commits touching your paths is the place to look.
- The repo is archived, or no outside PR has merged in 6 months and no maintainer has committed in 3. The dump prints the last fork merge date.

**Ask first** when:

- The repo has a gate the user must pass before opening a PR: vouch lists, a required discussion or issue before code, or a "discuss before non-trivial PRs" rule. Click-through CLAs that are signed on the PR itself (a bot asks after you open it) aren't gates; note them and move on.
  - **Trivial**, for these rules, means all of: no change to public behavior, API, config, or output format; the non-test diff is small (roughly 50 lines or fewer); and it follows a pattern the repo has already merged (link the precedent). Everything else is non-trivial. When the repo defines trivial itself, its definition wins.
  - Some repos invite unsolicited fixes ("we favor asking for forgiveness over permission"). Their stated stance overrides the generic ASK rules below for bug fixes.
- The change reverses a deliberate choice (from the lineage check), or adds a public option, flag, or API that no maintainer has agreed to.
- The issue is unconfirmed (no maintainer reply), and the change alters behavior someone might rely on. This includes the user's own fresh issue: an issue filed minutes before the PR, with no maintainer reply, hasn't been agreed to. If that issue already asks for agreement ("happy to send a PR if you agree"), ASK means **wait** for the answer; don't post a second comment.
- Someone is assigned or said "I'll take this" recently.

**Go** when none of the above apply. A maintainer-confirmed bug with no open PR touching the same files is the best case.

### What ASK produces

ASK writes a short comment for the user to post on the issue (or a new issue or discussion if the repo wants one), then stops. Draft it in the repo's voice, in 3 to 5 sentences:

1. What happens today, with the smallest repro.
2. The change you'd make, in one sentence.
3. The trade-off or the decision it reverses, named plainly (link the commit or PR).
4. A direct question: "Would you take a PR that does this, or would you prefer X?"

If the change has a trivial, uncontroversial half with a clear precedent (a one-line fix matching an earlier merged PR) and a half that needs agreement, say so: the trivial half can be a PR now, and the rest waits for the answer.

## Issues and feature requests

The same go, stop, or ask logic applies to an issue, read as "is filing this here welcome?":

- **GO:** a bug that reproduces on the latest release or default branch, with no duplicate. A feature request is also GO when the repo takes feature requests as issues (it has a template or label for them) and no recorded decision covers it. A feature request isn't ASK just because no one has agreed yet; agreement is what the issue asks for.
- **STOP:** a duplicate (comment on the existing issue instead, adding only what's new), a recorded decision that covers it, or a bug already fixed in the release line the user is on.
- **ASK, meaning post somewhere else first:**
  - The repo routes questions or proposals to Discussions or a forum (check the issue template `config.yml` contact links).
  - The bug lives upstream: in a dependency, the platform API, or a service the tool calls. Write for that venue, not this repo, and say why it belongs there.
- **Release lines:** when the bug is fixed on a newer line, check whether the user's line is still maintained (a branch for it, recent backport PRs, releases from it). If it is, a backport request is GO. If it isn't, the answer is to upgrade, so STOP and say so.

## Timing signals

Check the open milestones and recent releases. A milestone due within 2 weeks usually means a freeze, so non-critical PRs may sit until after release; say so in the note. Newer builds are covered by `channels.sh` above.

## Write `recon.md`

If you haven't cloned yet, write recon notes to `${TMPDIR:-/tmp}/houseguest/<owner>/<repo>/<topic>/` and move them into the ledger after cloning.

```markdown
# Recon: <repo> <issue or topic>
DECISION: GO | STOP | ASK
Reason: <one sentence, with link>

- AI policy: <the sweep's verdict; the quoted binding rule with its path, or "none found in: <sources>"; and the mode it puts the job in (normal, author mode, or STOP)>
- Gates: <discussion-first / vouch / DCO / CLA, and whether the user has passed them>
- Duplicates and prior attempts: <#links with state and the maintainer's reason for each close; open PRs touching the same files>
- Intent and lineage: <the commit or PR that made the current behavior, and whether it was deliberate; any documented escape hatch>
- Predicted objections: <the top 3, each with its basis>
- Reproduces on: <channels.sh's recon line with each result filled in: yes, no, or how it failed>; or "n/a: not a bug fix" for features and docs
- Timing: <milestone, freeze, last outside merge, or "nothing pending">
- Disclosure required: <their exact required format and when it applies, or "not required">
```

The `DECISION:` line is machine-read by the PR gate hook, so keep that exact spelling.
