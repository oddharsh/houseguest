# Forks: when the user is the edge case

Upstream serves its median user. Some users sit at the edge: a won't-fix, behavior the project chose on purpose, a release line nobody maintains, a library that does 40 things where they call 2. For them, the right answer is often a fork they own, trimmed to their use. Upstream, houseguest is a guest and the house rules win. In the user's fork, the user owns the house, and this page is houseguest's own rules for keeping it.

## When to offer it

- Recon says STOP because a maintainer declined the change, `intent.md` says the behavior is INTENDED, the user's release line is unmaintained, or the repo is archived.
- The user asks to fork, vendor, patch, or trim a dependency, or asks whether an update is worth taking.

Offer it; never start it unasked. A fork is something the user maintains for as long as they use it, so say what it costs: every upstream fix from here on is theirs to read and carry. Read the license first and record it. The fork keeps the LICENSE file and notices, and a copyleft license's terms travel with any copy the user distributes. A repo's AI policy governs contributions to it, and a private fork isn't one; the day part of the fork goes upstream, the policy applies again.

## The lightest fork that works

Take the first rung that covers the user's case:

1. **No fork.** An option, a config value, or a few lines in the user's own code around the call.
2. **A patch the package manager applies.** `bun patch`, `pnpm patch`, `patch-package`, Cargo's `[patch]`, a Go `replace` to a local directory, a uv path source. The upstream pin stays visible and the patch stays small enough to read.
3. **Vendor and trim.** Copy the source at an exact commit into the user's repo and delete everything their code doesn't reach.

## Trim to the use

1. **Find the kept surface.** List every symbol the user's code imports or calls, then everything those reach. The compiler is the fastest tool here: delete a module and see what breaks.
2. **Delete the rest,** including every transitive dependency the kept surface no longer needs. Each one dropped is one less package that can ship a compromised release into the user's build.
3. **Keep upstream's tests for the kept surface,** and delete the tests for deleted code. Those tests are the rules the fork shares with upstream, so the user's version stays compatible with everyone else's on the parts they both use.
4. **Write `FORK.md`** beside the code: the upstream URL, the base commit's full SHA, the license, the kept surface, the date, and the rules below.

## The rules stay; the code is a cache

The fork's durable record is its rules. The trimmed code can be regenerated from them, against a new base or with a better model, and checked by the same tests.

- **Write each rule in plain words, with an example and a counterexample,** and make both a test. The user reads the examples ("`parse("2026-10-13")` gives Oct 13; `parse("13/10/2026")` errors"); the test code is for the checker.
- **Propose the rules the user never said.** Trimming surfaces behavior their code relies on without anyone saying so: a default timezone, an encoding, which error type comes back. Write each as a proposed rule and ask the user to confirm it before the fork depends on it.
- **Catch contradictions while the user is still deciding.** When one rule's counterexample is another rule's example, stop and show both, quoted, before writing code against either.
- **Prove each change as it's written.** Every change runs the rules' tests red-green (`prove.sh`, as in `proof.md`) before it lands. A personal fork needs no CI when nothing lands unproven.
- **Code no rule reaches is legacy the day it lands.** Coverage of the trimmed code shows it: a line no test runs either gets a rule or gets deleted.
- **Rehearse on the user's real calls.** In a scratch clone of the user's project, run their own call sites with their real inputs against the fork. The rehearsal takes the place of a staging deploy, and works like the final check's run of a report on base and HEAD.
- **Grow the rules from use.** Each new break the user hits becomes a rule with its example before it becomes a fix.

## Variation with selection

Slop is variation without selection: one generated version, shipped because it exists. For a trim or patch that isn't trivial (recon's definition), make at least 2 versions independently, the way the second-fix agent does, and run every version against the rules. Show the user the versions that pass, as the inputs where they differ and what each returns, and let them pick. A version that fails a rule never reaches them.

## Updating: show me the commit

Updating is riskier than a latent bug. A known bug can be tracked and its CVEs watched; an update brings every commit in its transitive set, read or not. So the default is to stay on the base.

- **Watch the base.** Record in `FORK.md` how to check for advisories on it: `gh api "/advisories?ecosystem=<eco>&affects=<package>@<base version>"`, or osv.dev's query API by commit. A latent bug the user can live with becomes a tracked line in `FORK.md`.
- **Update only for a named commit.** Before an update, list what it brings: `git log <base>..<new> -- <kept paths>`, plus every version change in the lockfile's full transitive set. Read every commit. Take the update only when one of them fixes something the user hits, or an advisory covers the kept surface. Name that commit by its SHA. No named commit, no update.
- **Carry the commit.** Cherry-pick the named commit onto the fork and leave the base where it is, then rerun the rules' tests.

The same rule holds when the user asks whether to bump a dependency in their own project. List the transitive set the bump changes and read it. Then name the commit they need, or advise them to stay.

## Sending something back

A real upstream bug found while trimming is an upstream contribution: run the normal phases on it from phase 0. The fork's own rules stay in the fork. They describe one user's edge, and upstream's job is the median.
