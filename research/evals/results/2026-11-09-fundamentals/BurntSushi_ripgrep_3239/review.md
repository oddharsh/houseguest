Important: 5, Nit: 3, Pre-existing: 0

## Important

**1. Prompt and draft residue committed to the repo root.** Two files in the diff aren't part of any change ripgrep could ship:

- `pullrequest.txt` (210 lines): a second, longer PR description, committed as a file. It contains a curly apostrophe ("ripgrep’s", line 5) and reads as generated copy ("This ensures consistent behavior across both single-threaded and multi-threaded code paths.").
- `purpose.txt` (15 lines): the task prompt ("I want to: Add a new CLI flag called --suppress-error..."). It lists `crates/cli/src/args.rs` and `crates/searcher/src/searcher/glue.rs` as files to modify; the diff touches neither, and `crates/cli/src/args.rs` doesn't exist in this tree.

Delete both. On its own this is enough for me to close a PR on a busy day.

**2. Permission errors during traversal still print and still set exit 2, so the flag misses the most common case.** The body says the flag controls "permission-denied errors during file traversal and searching." Only the `searcher.search()` error arm is routed through `handle_search_error` (`crates/core/main.rs:157` and `main.rs:223`). Directory read failures from the walker go through `HaystackBuilder::build_from_result`, which still calls `err_message!("{err}")` unconditionally at `crates/core/haystack.rs:38`.

Case: a tree with a `chmod 000` subdirectory. `rg --suppress-error=nopermission foo .` still prints `rg: ./locked: Permission denied (os error 13)` and exits 2, because the walker's `read_dir` failure (`crates/ignore/src/walk.rs:1500`) arrives as an `ignore::Error`, never reaching the new helper. That's the "locked-down system directories" scenario `pullrequest.txt` gives as motivation.

Every instance of an unhandled permission-error site:
- `crates/core/haystack.rs:38`, reached from `search` (`main.rs:139`), `search_parallel` (`main.rs:214`), `files` (`main.rs:337`), and `files_parallel` (`main.rs:398`). So `rg --files --suppress-error=nopermission` ignores the flag entirely.

`ignore::Error::io_error()` (`crates/ignore/src/lib.rs:205`) already exposes the underlying `io::Error`, so the check can live in `build_from_result` without new plumbing beyond passing the mode to `HaystackBuilder`.

**3. The tests wouldn't catch a regression in the behavior the flag exists for.** Three problems, all in `crates/core/main.rs:266-326`:

- They race. All four tests reset and assert one process-global `static ERRORED` (`crates/core/messages.rs:25`), and `cargo test` runs tests on parallel threads. If `handle_search_error_non_permission_always_sets_errored` sets the flag between `handle_search_error_permission_skip_does_not_set_errored`'s reset and its `assert!(!errored())`, the skip test fails spuriously. That's a flaky test in CI.
- None of them checks output, though suppressing output is half the feature. `MESSAGES` defaults to `false` (`messages.rs:21`) and nothing in the test sets it, so `err_message!` never prints in any of these tests. A regression where `PermissionSilence` printed the error would pass all four.
- There's no CLI-level test. ripgrep tests flag behavior end to end in `tests/feature.rs` and `tests/regression.rs` with the `rgtest!` macro, asserting stderr and exit status. One `#[cfg(unix)]` test with an unreadable file and an unreadable directory, run under each mode, would have caught finding 2 and needs none of the global-state juggling. With that test in place, the `main.rs` test module and the test-only `reset_errored` in `messages.rs:141-144` can go.

**4. Half the flag duplicates `--no-messages`, and the value names invert ripgrep's own `no-` convention.** `--no-messages` already suppresses "messages related to the failed opening and reading of files" (`crates/core/flags/defs.rs`, `NoMessages::doc_long`) and still lets the error set exit status 2, since `err_message!` calls `set_errored()` before checking `messages()` (`messages.rs:80-85`). Case: `rg --no-messages foo unreadable.txt` and `rg --suppress-error=permission foo unreadable.txt` both print nothing and exit 2. The only behavior this PR adds is the exit-status change in `nopermission`.

The naming makes that worse. ripgrep uses `no-` to negate (`--no-messages` / `--messages`, `NoMessages::name_negated`), so `--suppress-error=nopermission` reads as "don't suppress permission errors." It does the opposite: it suppresses them harder. A user picking between the two values from `doc_choices` alone (`defs.rs:186-188`) will guess wrong.

There's also no linked feature request. The feature template (`.github/ISSUE_TEMPLATE/feature_request.md`) asks for "the behavior you want and the motivation" and sends only file-type changes straight to a PR, which I read as: new flags get discussed in an issue first. Drop the `permission` mode, pick a name for the exit-status behavior that doesn't collide with `no-`, and open the issue so the design gets settled before more code.

**5. The description claims more than the diff and tests show.**

- "during file traversal and searching": traversal isn't covered (finding 2).
- "Unit tests for the error handler covering mode × error type combinations": there are 3 modes (`None`, `PermissionSilence`, `PermissionSkip`) by 2 error kinds, so 6 combinations; the tests cover 4. `None` with `NotFound` and `PermissionSilence` with `NotFound` are missing.
- "Existing tests pass": no command or output shown.
- `pullrequest.txt` says `test_suppress_error` "Catches invalid values via an error." It doesn't; `defs.rs:204-214` has no invalid-value case.
- The body's "Changes" section has an orphaned bullet ("Added `handle_search_error()` helper...") under the flags heading with its own heading missing, and "the Default behavior" with a stray capital. Both read as pasted from a template.

## Nit

**6. New items break the alphabetical order the files keep.** `SuppressError` is defined at `defs.rs:155`, ahead of `AfterContext`; the definitions run alphabetically, so it belongs between `StopOnNonmatch` (`defs.rs:6632`) and `Text` (`defs.rs:6691`). The `HiArgs` field sits after `with_filename` (`hiargs.rs:107`) in an otherwise alphabetical struct, and the `suppress_error()` accessor sits ahead of `buffer_writer()` (`hiargs.rs:327`).

**7. The zsh completion doesn't complete the values.** `rg.zsh:202` ends in `:kind` with no choices, while `--engine` (`rg.zsh:83`), `--sort` (`rg.zsh:253`), and `--color` (`rg.zsh:310`) list theirs with `((...))`. It's also placed in the `(messages)` exclusion group, so after typing `--suppress-error` zsh stops offering `--no-messages`, though the two combine fine.

**8. `doc_long` is muddled.** "The only supported value for now is 'permission' related behavior" (`defs.rs:179`) sits directly above the docs for two values. `doc_short`'s "certain errors" says nothing about which; say "permission denied errors."

## Lean

- Delete `pullrequest.txt` and `purpose.txt`: -225.
- `handle_search_error` (`main.rs:19-43`): the `let mut handled` flag plus nested `if`/`if let`/`match` is one `match (err.kind(), suppress)` with three arms (skip: nothing; silence: `set_errored()`; `_`: `err_message!`), the way `search` already matches on `err.kind()` at `main.rs:155`: about -9.
- `SuppressError::update` (`defs.rs:191-193`): `let binding = v.unwrap_value(); let value = convert::str(&binding)?;` is `match convert::str(&v.unwrap_value())? {`, as `Color::update` does: -2.
- Dropping the `permission` mode (finding 4) removes a variant, a match arm, a test, and a doc paragraph: about -12.
- With a CLI test in `tests/feature.rs`, the `main.rs` test module and `reset_errored` go: about -65, offset by the new test.

I wouldn't merge this as is.

Lean: -245 lines possible
