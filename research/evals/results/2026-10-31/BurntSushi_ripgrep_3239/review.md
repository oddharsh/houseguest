Important: 5, Nit: 3, Pre-existing: 0

I'd close this. ripgrep already has `--no-messages`, and the half of this flag that it doesn't already cover changes a documented exit-status rule without an issue asking for it.

## Important

**1. Duplicates `--no-messages`, which the body never mentions.**
`crates/core/flags/defs.rs:4799-4822` defines `--no-messages`: "suppresses some error messages. Specifically, messages related to the failed opening and reading of files." That's the exact message `handle_search_error` silences, because `err_message!` (`crates/core/messages.rs:81-86`) only prints when `messages()` is true. So `rg foo --no-messages` already does what `--suppress-error=permission` does: no message, `ERRORED` still set, exit 2. The new flag only narrows it to one `io::ErrorKind`.

The one new behavior is `nopermission`, which drops exit status 2 for an error. The module doc at `crates/core/messages.rs:9-15` states the design on purpose: ripgrep keeps going after a read error, "But when an error does occur, it will alter ripgrep's exit status." Changing that needs an issue and a maintainer's yes first. The PR links none, and the body names no factual error behind the current choice.

**2. The flag doesn't reach traversal errors, though the body says it does.**
The body says it handles "permission-denied errors during file traversal and searching." The diff only touches the `searcher.search()` error arm (`crates/core/main.rs:157`, `crates/core/main.rs:223`). Directory permission errors come from the walker and go through `crates/core/haystack.rs:38` (`err_message!("{err}")` on an `ignore::Error`), which the diff leaves alone. That's the case most users hit:

```
mkdir d && chmod 000 d
rg foo --suppress-error=nopermission
```

This still prints `rg: ./d: Permission denied (os error 13)` and exits 2, so `nopermission` fails at its stated job. `rg --files` (`files`, `files_parallel` at `crates/core/main.rs:332`, `:368`) takes the same `build_from_result` path and is also uncovered. If this went ahead, the guard would have to cover every `err_message!` that can carry a permission error, and `ignore::Error` needs its own kind check because it isn't an `io::Error`.

**3. Two scratch files committed, and the copy reads as machine-written.**
`pullrequest.txt` (210 lines) and `purpose.txt` (15 lines) land at the repo root. `purpose.txt` is a prompt ("I want to: Add a new CLI flag... Files to modify: crates/cli/src/args.rs ... crates/searcher/src/searcher/glue.rs"), and it names two files this PR doesn't touch. `pullrequest.txt:5` has a curly apostrophe ("ripgrep’s"). The PR body has an orphan bullet ("Added `handle_search_error()` helper...") with its file heading missing, a stray capital in "the Default behavior," and "Existing tests pass" with no command or output behind it. Delete both files and rewrite the body by hand.

**4. The new unit tests race on a global, and none of them can catch a regression in the silencing.**
- Race: all four tests in `crates/core/main.rs:266-326` reset and read the process-wide `ERRORED` static, and libtest runs tests on parallel threads by default. If `handle_search_error_default_sets_errored_for_permission` (`:272`) calls `set_errored` between the reset at `:299` and the assert at `:310`, then `handle_search_error_permission_skip_does_not_set_errored` fails. The same interleaving breaks any pair where one test sets and another asserts unset. `reset_errored` (`crates/core/messages.rs:142`) exists only to make this pattern possible.
- Weak check: `MESSAGES` defaults to false (`crates/core/messages.rs:21`), so no message ever prints in these tests. Delete the `PermissionSilence` arm at `crates/core/main.rs:33-36` so it falls through to `err_message!`, and `handle_search_error_permission_silence_sets_errored` still passes, because the test asserts the same thing as the default-case test. The thing that mode changes (stderr output) is never asserted.

ripgrep tests CLI behavior end to end in `tests/` (the `rgtest!` harness in `tests/feature.rs`, `tests/regression.rs`), which asserts on stderr and exit status per process and has no shared-global problem. A test for this would belong there.

**5. Calls `set_errored()` directly, against the comment in the file the diff touches.**
`crates/core/messages.rs:133-136`: "Callers should not use this directly. Instead, it is called automatically via the `err_message` macro." `crates/core/main.rs:34` calls it directly. It also falsifies the field doc at `crates/core/messages.rs:24` ("Flipped to true when an error message is printed"), since `PermissionSilence` now sets it with nothing printed. The diff edits `messages.rs` and leaves both comments wrong.

## Nit

**6. Out of order with the files' own layout.** `HiArgs` fields and the `from_low_args` initializer are alphabetical (`stop_on_nonmatch`, `threads`, ... `with_filename`), but `suppress_error` is tacked on after `with_filename` at `crates/core/flags/hiargs.rs:107` and `:323`. In `defs.rs` the `FLAGS` entry sits in the right spot, but the `SuppressError` impl and its test sit at `crates/core/flags/defs.rs:155`, before `-A/--after-context`, instead of between `--stop-on-nonmatch` (`:6632`) and `-a/--text` (`:6691`).

**7. zsh completion is in the wrong group and offers no values.** `crates/core/flags/complete/rg.zsh:202` puts `--suppress-error=` inside the `'(messages)'` exclusion group, so zsh stops offering it once `--no-messages` is typed, even though the two aren't exclusive in `defs.rs`. It also ends in `:kind` with no choices; `--engine=` at `rg.zsh:83` shows the house form with each value listed.

**8. The value names read backwards.** `--suppress-error=nopermission` reads as "don't suppress permission errors," but it suppresses them harder than `permission` does. The `doc_long` at `crates/core/flags/defs.rs:179` also says "The only supported value for now is 'permission'" and then documents two values.

## Lean

- Close in favor of `--no-messages`: every added line goes.
- If anything stayed: `pullrequest.txt` and `purpose.txt` (-225); the `let binding` / `convert::str(&binding)` pair at `defs.rs:191-192` becomes `match convert::str(&v.unwrap_value())? {` like `--color` at `defs.rs:827` (-1); the `handled` flag in `handle_search_error` becomes an early `return` per arm (about -4).

Lean: -411 lines possible
