# Harvest: build big at home, post small upstream

Every other page here starts from a bug the user hit. A harvest starts from something the user builds on purpose: a port of the project, a differential harness against it, a fuzzer over its parser. Agents made these cheap to build, and maintainer attention stayed as scarce as it was. So the ambitious project lives in a repo or fork the user owns, and each divergence or crash it finds leaves as its own small oss-pr job.

Dan Luu's [post on ambitious projects](https://danluu.com/ambitious/) gives the example: Michael Malis's pgrust, a Postgres rewrite whose testing turned up upstream Postgres bugs in SP-GiST, the JSONPath format cache, pgcrypto, the dictionary loader's memory safety, and a money overflow. The rewrite doesn't have to ship for those fixes to land.

## When to offer it

Offer it when the user asks what to contribute to a project, or names a port, harness, or fuzzer they want to build. Never start one unasked: it costs the user's compute and attention, and every finding becomes a job they shepherd.

Pick the project for its oracle. A reference implementation makes a port testable, a spec or an existing parser makes a fuzzer testable, and a written invariant makes property tests possible. Without one of those, the project has no way to say which side of a difference is wrong.

The harvest repo is the user's (`room.sh` says `own`), so the gate stays out of it. Its rules are `forks.md`'s: rules with examples, every change proven as it lands.

## Oracle first

The first commit in the harvest repo is the oracle, before any port or build code. Yossi Kreinin's rebuttal, quoted in the post's appendix, is that agent loops need clear pass/fail criteria and tend to overfit. The oracle supplies the criteria, and three habits keep the loop from overfitting to it:

- **Build it from what already exists:** a differential run against the reference (`proof.md`, "Differential runs"; `defaults.md` on seeded, generated inputs), a fuzz target, or seeded property tests.
- **Show it can fail** before trusting a pass, the way a hillclimb shows its instrument catches a deliberate slowdown (`proof.md`, "Hillclimbing", step 1). Plant a known divergence and watch the oracle flag it.
- **Hold out inputs.** Keep a seed range or corpus the build loop never runs against, and grade on it, for the same reason `holdout.md` exists. The oracle itself changes only in its own commit with the reason, never in the commit that makes the build pass.

The build then runs as a climb per "Hillclimbing", with the count of differing inputs as the metric and zero as the target.

## Triage each finding

Each divergence or crash falls in one of 4 classes, and only one leaves the harvest repo:

1. **The new code is wrong.** Fix it in the harvest repo.
2. **The harness is wrong.** Fix the harness, in its own commit.
3. **Both readings are allowed:** the spec or docs leave it open. Record it; at most it becomes a docs job, if recon finds the behavior was never written down.
4. **The reference is wrong.** Harvest it.

Before calling a finding the reference's, reproduce it through upstream's own interface with no harvest code in the loop: a CLI call, a query, a test in their suite. A finding that shows only through the harness isn't a report yet.

Log each finding in `HARVEST.md` in the harvest repo, one line each: the input or seed, the class, and the upstream job it became.

## Each finding is its own job

A class-4 finding runs the normal phases from phase 0, like any other job (`forks.md`, "Sending something back"). The intent check gets a neutral statement, recon checks duplicates (fuzzed parsers often have the crash filed already), proof writes a red-green test in upstream's own suite, and the PR carries one concern. Five findings in one module are five jobs, unless recon traces them to one cause.

A memory-safety crash is probably a vulnerability, so it goes through recon's "Security reports" before anything public.

Post one at a time, and let the first one's reception set the pace for the rest. A dozen PRs from a stranger in a week reads as the flood SKILL.md opens on, however good each one is.

Nothing about the harvest project gets posted upstream. The PR body may say how the user found the bug in one true sentence ("Found by differential testing against a port"), and stops there: no link pitching the port, no offer to contribute the harness. If a maintainer asks for the harness, that's a new conversation they started.

Recon's note records where the job came from, so `practice` can count these jobs later:

```markdown
- Source: harvest <harvest repo URL or path>, finding <its HARVEST.md line>
```
