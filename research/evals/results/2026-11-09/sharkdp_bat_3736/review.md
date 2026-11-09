Important: 2, Nit: 2, Pre-existing: 1

## Important

**1. Environment variables stand in for "stdout is a terminal", so `--color=auto` help now writes escape codes into pipes and files.**

`MSYSTEM` and `TERM_PROGRAM` describe the shell bat was launched from. They say nothing about where stdout goes, and every child process inherits them. In Git Bash or any MSYS2 shell, `MSYSTEM=MINGW64` is set for the whole session, so:

- `bat --help > help.txt` now writes ANSI escapes into `help.txt`.
- `bat --help | grep -- --style` now matches against highlighted text, and `bat --help | less` gets raw escapes unless `-R` is on.

Instances:
- `src/bin/bat/app.rs:117`: `_ => interactive_output || is_mintty` is true for any redirected stdout once `MSYSTEM` is set. At the base it was `interactive_output`, so piped help was plain.
- `src/bin/bat/app.rs:205`: `std::env::var_os("MSYSTEM").is_some()` matches every MSYS2/Git Bash process, terminal or not. The `TERM_PROGRAM` arm at `:202-204` has the same problem for any child of mintty.
- `src/bin/bat/app.rs:62-66`: the comment says "we do NOT override interactive_output itself so that piping (bat file | grep foo) still works correctly." That's only true for `bat file`, which this diff never touches. For `bat --help`, the case it does touch, piping is exactly what breaks.
- The same new path skips `NO_COLOR`. `config()` gates auto color on `!env_no_color() && self.interactive_output` (`src/bin/bat/app.rs:458`). With this diff, `NO_COLOR=1 bat --help | cat` under Git Bash emits color.

The fix needs a signal tied to the stdout handle. I'm fairly sure Rust's std `is_terminal()` on Windows already falls back to checking for an MSYS/Cygwin pty pipe name (`msys_tty_on`), which is the case the body says it misses. That's why item 2 asks for a real repro.

**2. The description and CHANGELOG claim a fix the diff doesn't make, and nothing shows the bug was reproduced or the fix run.**

- `CHANGELOG.md:25` says "restoring colored output for `bat --help` and normal file display." Body step 4 says "Run `bat somefile.rs` and confirm syntax highlighting works." But `is_mintty` is a local in `App::new()` and only reaches the help branch (`src/bin/bat/app.rs:117`). Normal display still decides color at `src/bin/bat/app.rs:458` from `self.interactive_output` alone. `loop_through` at `:463` still passes the file through unhighlighted. So `bat somefile.rs` in mintty behaves exactly as it did at the base.
- The body says "When either is present and `is_terminal()` returns false, the output is still treated as interactive." The code comment at `:65` says the opposite, and the code follows the comment.
- "Verified all existing tests pass (232 passed, 0 failed)" doesn't name a platform. On Linux or macOS, `is_mintty_terminal()` is the `#[cfg(not(windows))]` stub returning `false` (`:208-211`), so that run never executes a new line. On Windows, `short_help` and `long_help` are `#[ignore]`d (`tests/integration_tests.rs:625-640`), and nothing sets `MSYSTEM`.
- The root cause ("mintty uses POSIX PTYs that Windows isatty() does not recognize") comes with no output from a mintty session, before or after. The Testing section lists steps "To manually test" without saying anyone ran them. Please show `bat --help` and `bat --help | cat` from Git Bash on the base and on this branch.

## Nits

**3. No regression test.** `CONTRIBUTING.md` says: "You are **strongly encouraged** to add regression tests," and points functional changes at `tests/integration_tests.rs`. The test helper `bat()` pipes stdout and scrubs `NO_COLOR`, `COLORTERM`, and friends (`tests/utils/command.rs:6-24`), but not `MSYSTEM` or `TERM_PROGRAM`. A Windows-gated test running `bat --help --paging=never` with `.env("MSYSTEM", "MINGW64")` and asserting `contains("\x1B[").not()`, the way `help_with_color_never` does at `tests/integration_tests.rs:675`, would have caught item 1.

**4. The helper doesn't match how this file writes env checks.** Environment probes in `app.rs` are free functions at the top of the file: `is_truecolor_terminal()` (`:31`) and `env_no_color()` (`:37`). `env_no_color()` also uses `var_os(..).is_some_and(..)`, not `.map(..).unwrap_or(false)`. If any env check survives item 1, write it as one free function beside those, with `cfg!(windows) &&` instead of two `#[cfg]` copies (`:197-211`). Then drop the 5-line call-site comment (`:62-66`), which repeats the doc comment and gets the piping behavior wrong.

## Pre-existing

**5. Help ignores `NO_COLOR` in a real terminal.** At the base, `src/bin/bat/app.rs:110` (`_ => interactive_output`) never checks `env_no_color()`, so `NO_COLOR=1 bat --help` in a terminal is highlighted. Normal display honors it at `:458`. Item 1 covers the part this diff extends to pipes.

Lean: -13 lines possible (merge the two `#[cfg]` functions into one `cfg!(windows) &&` free function using `is_some_and`, -8; drop the duplicate call-site comment, -5). If item 1 means the env heuristic goes, all 24 added lines in `app.rs` go with it.

Request changes. The current approach regresses piped `bat --help` for every Git Bash user, and it doesn't touch the file-display case the CHANGELOG says it fixes.
