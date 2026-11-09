Important: 5, Nit: 3, Pre-existing: 0

## Important

**1. The flag misses permission errors from directory traversal, which is the common case.** The body says it handles errors "during file traversal and searching," but walker errors never reach `handle_search_error`. They go through `HaystackBuilder::build_from_result` at `crates/core/haystack.rs:38` (`err_message!("{err}")`), which the diff doesn't touch.

Case: `mkdir -p d/locked && echo foo > d/a && chmod 000 d/locked && rg --suppress-error=nopermission foo d` still prints `rg: d/locked: Permission denied (os error 13)` and exits 2. Only an unreadable file inside a readable directory hits the new code, because the walker yields that entry and the open fails later in `searcher.search`.

Instances of the uncovered path:
- `crates/core/haystack.rs:38`, reached from `search` (`main.rs:139`), `search_parallel` (`main.rs:214`), and `files` / `files_parallel` (`main.rs:337`, `main.rs:398`) for `--files`, where traversal is the only source of permission errors.

`ignore::Error::io_error()` (`crates/ignore/src/lib.rs:205`) already digs the `io::Error` out of `WithPath` / `WithDepth`, so the kind check is available there.

**2. Two scratch files are committed at the repo root.** `pullrequest.txt` (210 lines) and `purpose.txt` (15 lines) are tooling output, not source. `purpose.txt` is the task prompt ("Files to modify: crates/cli/src/args.rs ... crates/searcher/src/searcher/glue.rs ... Add tests"), and the diff touches neither of those paths. Neither file is in `Cargo.toml`'s `exclude` list (`Cargo.toml:16-24`), so both would ship in the crates.io tarball. Delete both.

**3. `handle_search_error` calls `set_errored()` directly, against the comment on it.** `crates/core/messages.rs:135` says: "Callers should not use this directly. Instead, it is called automatically via the `err_message` macro." The diff touches `messages.rs` and calls it anyway at `crates/core/main.rs:34` for `PermissionSilence`. Dropping that mode (finding 5) removes the call; if the mode stays, the comment has to change with it.

**4. The new unit tests race on a process-global and one of them can't fail.** All 4 tests in `crates/core/main.rs:265-327` call `reset_errored()` and then assert on `ERRORED`, a single static `AtomicBool` (`messages.rs:25`). `cargo test` runs them on parallel threads in one binary.

Case: `handle_search_error_non_permission_always_sets_errored` sets the flag after `handle_search_error_permission_skip_does_not_set_errored` resets it (`main.rs:299`) and before that test's `assert!(!errored())` at `main.rs:309`. Or another test's reset lands between a call and `assert!(errored())` at `main.rs:279`, `294`, or `324`. CI runs this on every matrix job, so it will flake.

Separately, `handle_search_error_permission_silence_sets_errored` passes on the base behavior (an unconditional `err_message!`), because it never checks that nothing was printed. It doesn't pin the mode it's named for. An integration test in `tests/` that runs `rg` against a `chmod 000` directory and file (skipped when running as root) would check stderr and the exit code, and it would have caught finding 1.

**5. `--suppress-error=permission` duplicates `--no-messages`, and the CLI shape is hard to read.** `--no-messages` (`crates/core/flags/defs.rs:4797`) already hides "messages related to the failed opening and reading of files" and keeps exit status 2. So `rg --no-messages foo /` already gives the `permission` mode, except that it also hides non-permission errors, which nothing in the body asks to keep visible.

The value names read as opposites: `nopermission` sounds like "don't suppress permission errors," yet it suppresses more than `permission` does. The long doc (`defs.rs:179`) says "The only supported value for now is 'permission' related behavior" right before describing two values.

Fix: keep the one behavior `--no-messages` can't give (permission errors don't affect exit status), and name it for that. Set it the way `--no-messages` is set, as a global in `messages.rs` from `set_log_levels` (`crates/core/flags/parse.rs:117`). That lets `haystack.rs:38` read it without threading `HiArgs` there, and it drops the `HiArgs` field and accessor (`hiargs.rs:107`, `hiargs.rs:327`) and the `mod.rs` re-export.

## Nits

- **Placement doesn't follow the file's order.** `defs.rs` defines flags alphabetically, but `SuppressError` sits at `defs.rs:155`, ahead of `-A/--after-context`; it belongs after `--stop-on-nonmatch` (`defs.rs:6632`). `HiArgs.suppress_error` is appended after `with_filename` (`hiargs.rs:107`) instead of between `stop_on_nonmatch` and `threads`. The `binding` local at `defs.rs:191-192` also differs from `--color`, which does `match convert::str(&v.unwrap_value())?` (`defs.rs:826`).
- **The zsh completion lists no values and sits in the wrong group.** `rg.zsh:202` ends in a bare `:kind`, unlike `--engine=` (`rg.zsh:83`) and `--color=` (`rg.zsh:310`), which list their choices. It also sits inside the `(messages)` exclusion group, so zsh stops offering it once `--no-messages` is on the line.
- **The body overstates the tests and has a broken list.** "Unit tests for the error handler covering mode × error type combinations" covers 4 of 6 combinations (no `NotFound` case for `None` or `PermissionSilence`). "Existing tests pass" comes with no output. The `main.rs` bullets under Changes have lost their heading.

Lean: -260 lines possible
- `pullrequest.txt` and `purpose.txt`: -225.
- `handle_search_error` (`main.rs:19-44`, 26 lines with a `handled` flag and a nested `if let` / `match`): with one mode it's an early `return` on `PermissionDenied` when the setting is on, then the existing `err_message!`. About -18.
- `PermissionSilence` variant, its choice, its match arm, and its test, which can't fail (finding 4): about -19.

Wouldn't merge as is.
