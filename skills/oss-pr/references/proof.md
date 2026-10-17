# Phase 4: Proof

The user wants proof a skeptical maintainer can't argue with. For a bug fix, that means checking one claim mechanically: **this test fails without the change, for the reported reason, and passes with it.** Everything else ("all tests pass," "I verified manually") is weaker evidence, and maintainers know it.

## Red-green

Commit first. The proof binds to a commit SHA, and the gate hook rejects a proof whose SHA isn't HEAD.

**Tests in separate files** (most JS/TS, Python, Go, Java, Ruby):

```bash
bash "<skill-dir>/scripts/prove.sh" \
  --base upstream/main --expect '<assertion message or failing test name>' --runs 3 \
  --suite '<the repo CI test command>' \
  -- <command that runs just the new test>
```

The script reverts every changed non-test file to the merge-base, runs the test (it must fail), restores the fix, and runs it again (it must pass). If your test files don't match its default test-path pattern, pass `--tests '<regex>'`.

**Tests inline with the code** (Zig `test` blocks, Rust `#[cfg(test)]` modules, doctests): the script can't split test from fix inside one file. Commit the test alone first, then the fix, and pass the test-only commit as `--red-ref <sha>`. If the repo wants one commit per PR, squash after the proof passes and rerun the proof on the squashed commit; that's cheap, and it keeps the SHA honest.

## Why `--expect` matters

The classic false proof: the test references a function the fix adds, so without the fix it fails with an import or compile error. That's a red that proves nothing about the bug. Pass `--expect` with the assertion message or the failing test's name, so a failure for any other reason counts as FAIL. Always read the red output tail in `proof.md` yourself, too.

## Choosing the test command

- Run the narrowest command that runs just your test (`pytest path::test_name`, `go test -run TestX ./pkg`, `cargo test name`, `zig build test -Dtest-filter="name"`, `npx vitest run path -t name`). Fast runs make `--runs 3` cheap, and 3 runs catch flaky tests.
- `--suite` should be the command CI runs, or the closest subset that finishes in a few minutes. It guards against regressions outside your test.

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

Never edit `proof.md` to say PASS. The PR description quotes it, and the gate hook trusts it.
