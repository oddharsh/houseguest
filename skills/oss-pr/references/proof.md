# Phase 4: Proof

The user wants proof a skeptical maintainer can't argue with. For a bug fix, that means checking one claim mechanically: **this test fails without the change, for the reported reason, and passes with it.** Everything else ("all tests pass," "I verified manually") is weaker evidence, and maintainers know it.

## Red-green

Commit first. The proof binds to a commit SHA, and the gate hook rejects a proof whose SHA isn't HEAD.

**Tests in separate files** (most JS/TS, Python, Go, Java, Ruby):

```bash
bash "<skill-dir>/scripts/prove.sh" \
  --base upstream/main --expect '<assertion message or failing test name>' \
  --suite '<the repo CI test command>' \
  -- <command that runs just the new test>
```

The script reverts every changed non-test file to the merge-base, runs the test (it must fail), restores the fix, and runs it again (it must pass). Then it checks two more things a reviewer would otherwise find later: that the test covers every part of the fix, and that it isn't flaky (both below). If your test files don't match its default test-path pattern, pass `--tests '<regex>'`.

**Tests inline with the code** (Zig `test` blocks, Rust `#[cfg(test)]` modules, doctests): the script can't split test from fix inside one file. Commit the test alone first, then the fix, and pass the test-only commit as `--red-ref <sha>`. If the repo wants one commit per PR, squash after the proof passes and rerun the proof on the squashed commit; that's cheap, and it keeps the SHA honest.

## Why `--expect` matters

The classic false proof: the test references a function the fix adds, so without the fix it fails with an import or compile error. That's a red that proves nothing about the bug. Pass `--expect` with the assertion message or the failing test's name, so a failure for any other reason counts as FAIL. Always read the red output tail in `proof.md` yourself, too.

## Choosing the test command

- Run the narrowest command that runs just your test (`pytest path::test_name`, `go test -count=1 -run TestX ./pkg`, `cargo test name`, `zig build test -Dtest-filter="name"`, `npx vitest run path -t name`). The script runs it about 15 times (3 green, 3 red, 10 for flakes, one per hunk), so a fast command matters. Go caches passing tests, so without `-count=1` the repeat runs prove nothing.
- `--suite` should be the command CI runs, or the closest subset that finishes in a few minutes. It guards against regressions outside your test.

## Coverage: every hunk of the fix is tested

A test that fails without the whole fix can still miss half of it. The script reverts each hunk of the fix on its own and runs the test once. A hunk whose reversal leaves the test green is one no test checks: a reviewer can delete it and nothing tells them it mattered. Comment-only hunks are skipped. When you pass `--suite`, a hunk your test misses is tried against the whole suite too, the way Meta's mutation testing asks whether any test can tell a planted fault apart. If the suite catches it, it counts as covered. If nothing catches it, the hunk may change no behavior at all, and the first answer below is the likely one. `proof.md` gets a `COVERAGE:` line and lists each UNCOVERED hunk as `path:line`.

Each uncovered hunk gets one of three answers, in this order:

1. **Delete it,** if the fix works without it. No test noticing a hunk is often the first sign it isn't needed (`lean.md`).
2. **Cover it** by extending your test, or adding one case, through the same public interface. Follow the neighbors: if they test this kind of edge (the empty input, the error path), test it the same way. Write one case per behavior, not one per hunk.
3. **Acknowledge it** in `$LEDGER/coverage-ack.md` as `- path:line <reason>`, when the repo doesn't test that kind of code either: log text, an error message no neighboring test asserts, a guard no public input can reach. "Hard to test" isn't a reason.

An uncovered hunk with no ack fails the proof. `--max-hunks 0` skips the check for fixes where reverting one hunk alone can't build, and `proof.md` says it was skipped.

## Flakes

A test that passes 9 times in 10 costs a maintainer more than no test: it turns their CI red on someone else's PR months from now. After red-green, the script runs the green test 10 more times (`--flake N`). Any failure fails the proof.

It also lists lines your test adds that commonly cause flakes: sleeps and timeouts, wall-clock time, unseeded randomness, and network calls. These don't fail the proof, but read each one:

- **Waiting:** replace a sleep with waiting on the condition itself, or with the fake timers the neighboring tests use.
- **Time and randomness:** use the clock or seed the repo's tests already inject. If none of them do, assert something that doesn't depend on it.
- **Network:** use the repo's fixtures, recorded responses, or local server helpers. A test that needs the internet fails offline and in sandboxed CI.

When a flake shows up, fix the test. Don't raise retries, and don't drop `--flake`. When the repo's runner can shuffle test order (`go test -shuffle=on`, `pytest -p randomly`, `vitest --sequence.shuffle`, `rspec --order random`) and CI uses it, pass the same flag in the test command so an order dependency shows up here too.

## Checks beyond the example

Red-green proves the fix for one input. Many repos already run checks that cover far more: properties over thousands of generated inputs, fuzzers, snapshots, type tests, simulators, and proofs. These used to be expensive to write and keep green. seL4's proof took about 25 person-years for 8,700 lines of C. An agent changes that math for running and repairing them. Introducing one stays the maintainers' call, since they'd own it forever. The style phase saved what's there to `checks.md`; rerun it with the files your diff actually changed:

```bash
bash "<skill-dir>/scripts/checks.sh" --files <your changed files> --save "$LEDGER/checks.md"
```

It lists each kind it finds, the files nearest yours, and the CI line that runs it, or says nothing in CI does. A check CI never runs, or runs only when a maintainer adds a label (tokio's loom jobs), is one your PR's CI won't catch, so run it here. For each kind near your change:

- **Property tests and fuzzers.** Run the properties and fuzz targets that reach your code on the base and on HEAD, with a time bound (`go test -fuzz FuzzX -fuzztime 60s`, `cargo fuzz run <target> -- -max_total_time=60`). A counterexample on the base is a second red; pin its shrunk form in the repo's own regression mechanism (Hypothesis `@example(...)`, a `proptest-regressions/` file, a `testdata/fuzz/FuzzX/` entry) so it reruns forever. When the neighbors already state properties of this function, add one for the rule your fix restores, beside your literal case: the case shows the bug, the property states the rule. Seed any property you hand to `prove.sh` (Hypothesis `derandomize=True` or `@seed`, fast-check's `seed`, or `go test -run FuzzX`, which replays only the corpus). An unseeded one can pass the red run by luck, and fails the flake check for the same reason.
- **Expect and snapshot tests.** When the tests for your function snapshot, red's output is a diff of wrong output against right, the most legible evidence a reviewer gets. Quote it in `proof.md` and pass the snapshot's name to `--expect`. Create or update only your test's snapshot (run that one test in the tool's update mode), then read it as you'd read a hand-written literal. Never accept snapshots in bulk (`cargo insta accept`, `vitest -u`, `UPDATE_EXPECT=1` over the suite): an existing snapshot your change moves is either the bug, named in the PR, or a regression. `prove.sh` counts snapshot and golden files as test files, so red keeps your new snapshot and runs it against the unfixed code.
- **Type tests.** When the fix makes a bad state unrepresentable, the bug stops compiling and a runtime test can't reach it. A type test can: `// @ts-expect-error` above the bad call in a `tsd` or `.test-d.ts` file, a `trybuild` case, or a `compile_fail` doctest. On the base the bad call compiles, so the type test fails (an unused `@ts-expect-error` is an error); on HEAD it passes. Pass the checker's error text to `--expect`. Add one only where the repo already keeps type tests.
- **Deterministic simulation.** A race or ordering bug that shows 1 run in 50 can't anchor a red-green on its own. If the repo has a simulator or model checker (loom, shuttle, madsim, turmoil, a `vopr` or `simulator` harness), reproduce the bug in it and record the seed or schedule that fails on the base. That turns the flake into a red-green. Without one, say in the PR how often the repro fails on each side, with the run count.
- **Formal specs and proofs.** When Kani harnesses, Verus or Lean proofs, or a TLA+ spec cover the code you changed, run them on HEAD with the repo's command. A proof that breaks fails this phase the same way a red test does: fix the code, or the proof if the property itself changed. When your change alters behavior a spec models, update the spec in the same PR, or say in the body that it's stale and ask how they keep it current.

Record each check you ran under `## Beyond the example` in `proof.md`: the command, base result, HEAD result, and any seed. A check that found nothing still goes in, since "fuzzed `parse` for 60s on HEAD, no crashes" is a claim the PR body can make and a reviewer can rerun.

## Performance

Only when the change touches a hot path, or the repo has a benchmark suite covering the code:

- Use the repo's own benchmark tool (`cargo bench`, `go test -bench`, `pytest-benchmark`, `vitest bench`, a `src/bench*` directory). For CLI-level timing, `hyperfine` with `--warmup 3`.
- Run base and head on the same machine, back to back, at least 10 runs each. Report the median and spread for both, plus the delta.
- Treat a delta inside the noise as "no measurable change" and say exactly that. Don't round noise into a win.
- Append results to `proof.md` under `## Performance` with the exact commands.

Don't add a benchmark harness to a repo that has none unless the PR is about performance; it's code the maintainers didn't ask to own.

## Non-code changes

Docs, typos, CI config, and build metadata have nothing to red-green. Write `proof.md` by hand:

```markdown
# Proof: <branch>
STATUS: N/A (docs-only)
SHA: <git rev-parse HEAD>
- Checked: <rendered the docs page / ran the CI job locally with act / built the package>
```

## What reviewers can see

Red-green convinces a reviewer the fix works; a preview lets them see it without checking out your branch. When the change is something a reviewer would want to look at or try (a UI, a docs site, a CLI's output, a package they'd install), find out what the repo gives them:

```bash
bash "<skill-dir>/scripts/preview.sh" --repo <owner/name> --files <your changed files> --save "$LEDGER/preview.md"
```

It lists the preview pipelines the repo runs, what recent fork PRs and branch PRs actually got, and how often outside contributors' PRs carried screenshots. Then:

- **FORKS GET ONE:** the repo's own pipeline will post a link on your PR. Build nothing. Write one sentence for the PR body telling reviewers where on the preview to look ("On the preview, `/docs/install` below 600px wide shows the menu").
- **BRANCHES ONLY:** the repo builds previews, but a fork PR waits for a maintainer to authorize the build, or never gets one. Don't ask for it in the body; maintainers know their pipeline and authorize it when they want to look. Do what NONE FOUND says.
- **NONE FOUND:** show the change in the PR itself. For a visible change, take before and after screenshots, or a short recording for an interaction, from the base and from HEAD (`git worktree add <dir> <base>` gives you the base without touching your branch). For a CLI, the command and its output in a code block do the same job. Include them when the change is visual, or when the screenshot line shows this repo's outside contributors usually do.

`gh` can't upload images. Save them to `$LEDGER/shots/`; after the PR opens, the user drags them into the description on GitHub. Write the body so it reads complete before they land, and add the caption with the images.

Never host your own preview (your Vercel or Netlify, a `gh-pages` branch on your fork, a tunnel) unless the user asks. A reviewer can't tell what a stranger's deployment was built from, a link to an unknown domain in a first-time contributor's PR reads as spam, and it breaks the day the user deletes it. If the user asks anyway, name the commit it was built from beside the URL.

Record the verdict and what reviewers will see in `proof.md` under `## Preview`.

## When the proof fails

A FAIL is the useful outcome; it caught something before a maintainer did. Read which half failed:

- **Green failed:** the fix doesn't work, or the test is wrong.
- **Red passed:** the test doesn't exercise the bug. Rewrite the test until it fails on the unfixed tree.
- **Red failed for the wrong reason:** restructure the test so it compiles without the fix, for example by testing through an existing public API instead of a new helper.
- **Hunks untested:** see "Coverage" above: delete the hunk, cover it, or acknowledge it.
- **Flaky:** the logs for each extra run are in `logs/flake-*.log`. Find what differs between a passing and a failing run, and fix the cause in the test, or in the fix if the race is there.

Never edit `proof.md` to say PASS. The PR description quotes it, and the gate hook trusts it.
