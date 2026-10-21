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

## When the proof fails

A FAIL is the useful outcome; it caught something before a maintainer did. Read which half failed:

- **Green failed:** the fix doesn't work, or the test is wrong.
- **Red passed:** the test doesn't exercise the bug. Rewrite the test until it fails on the unfixed tree.
- **Red failed for the wrong reason:** restructure the test so it compiles without the fix, for example by testing through an existing public API instead of a new helper.
- **Hunks untested:** see "Coverage" above: delete the hunk, cover it, or acknowledge it.
- **Flaky:** the logs for each extra run are in `logs/flake-*.log`. Find what differs between a passing and a failing run, and fix the cause in the test, or in the fix if the race is there.

Never edit `proof.md` to say PASS. The PR description quotes it, and the gate hook trusts it.
