Important: 2, Nit: 2, Pre-existing: 1

## Important

**1. An environment variable stands in for "stdout is a terminal", so every pipe and redirect in an MSYS2 shell gets colored help.**

`src/bin/bat/app.rs:117` now reads `_ => interactive_output || is_mintty`, and `is_mintty_terminal()` (`src/bin/bat/app.rs:201-206`) returns true whenever `MSYSTEM` is set or `TERM_PROGRAM=mintty`. Both variables describe the shell session and get inherited by every child process. Neither says anything about where this process's stdout points.

Concrete case: in Git Bash, `MSYSTEM=MINGW64` is always set. So `bat --help > help.txt` writes ANSI escapes into the file, and `bat --help | grep -- --color` greps through escape codes. The same happens when the user has `alias cat=bat` and pipes `cat --help` into another program. Before this PR, `--color=auto` stayed plain in all of those, because `is_terminal()` is false for a pipe or a file. The MSYS2 check also fires in MSYS2 shells running under Windows Terminal or VS Code (ConPTY), where `is_terminal()` already answers correctly, so there it can only make things worse.

The new comment at `src/bin/bat/app.rs:62-66` says "we do NOT override interactive_output itself so that piping (bat file | grep foo) still works correctly." That's true for file display only because the PR doesn't touch file display (see finding 2). For the one path it does change, piping breaks exactly as the comment says it won't.

Fix: decide on the stdout handle, not the environment. Rust's `std::io::IsTerminal` on Windows already falls back to inspecting the pipe name for msys/cygwin ptys when `GetConsoleMode` fails, so if `is_terminal()` really returns false in some mintty setup, the PR needs to show which one and why that check misses it. An env var check can't tell a pty from a pipe.

**2. The description and changelog claim a fix the code doesn't make, and the root cause has no evidence behind it.**

- `pr-body.md` says the bug "caused `bat --help` (and regular file display) to lose colored output," lists "Run `bat somefile.rs` and confirm syntax highlighting works" as a test, and `CHANGELOG.md:25` says it restores "colored output for `bat --help` and normal file display." But `is_mintty` is read only inside the `if matches.get_flag("help")` branch (`src/bin/bat/app.rs:117`). File display still decides color at `src/bin/bat/app.rs:458` with `!env_no_color() && self.interactive_output`, unchanged. Paging (`app.rs:339`) and `loop_through` (`app.rs:463`) are unchanged too. So `bat somefile.rs` behaves exactly as on `base`.
- That also cuts against the stated root cause. File display has gated color on `interactive_output` long before v0.23.0. If `is_terminal()` returned false under mintty, file display would have been plain for every mintty user all along, and #3034 would be about far more than `--help`. The body's own timeline (regression in v0.23.0, when help moved onto bat's pipeline) points at something in the help path, not at `is_terminal()`.
- "Verified all existing tests pass (232 passed, 0 failed)" proves nothing about this change: no test sets `MSYSTEM` or `TERM_PROGRAM`, and off Windows `is_mintty_terminal()` is a hard-coded `false`. The "To manually test" steps are instructions, not results. There's no output from an actual mintty run anywhere.

Fix: either drop "regular file display" from the body and the changelog entry, or make the change cover it. Before either, show `is_terminal()` returning false on a real mintty stdout (a one-line `eprintln!` run is enough) so the root cause is something you observed. CONTRIBUTING.md asks for "a test to `tests/integration_tests.rs`" for functional changes; an integration test that runs `bat --help` with `MSYSTEM=MINGW64` set and stdout captured (a pipe) and asserts no `\x1b[` in the output would have caught finding 1 on Windows CI.

## Nit

**1. `is_some_and` is how this file reads optional env vars.** `src/bin/bat/app.rs:202-204` uses `.map(|v| v == "mintty").unwrap_or(false)`. Two functions up, `env_no_color()` (`src/bin/bat/app.rs:38`) does the same job as `env::var_os("NO_COLOR").is_some_and(|x| !x.is_empty())`, and the file already imports `env`, so `std::env::` is redundant too.

**2. Two cfg'd copies of one function for a one-line check.** `src/bin/bat/app.rs:197-211` defines `is_mintty_terminal` twice, once returning `false`. If a check like this survives finding 1, `cfg!(windows) && ...` inline at its single caller does the same in one expression and drops the 16-line helper plus the doc comment that repeats the call-site comment.

## Pre-existing

**1. `--help` ignores `NO_COLOR` under `--color=auto`.** The help branch's auto arm (`_ => interactive_output` at `base` `src/bin/bat/app.rs:110`, from 6f0a61c) never calls `env_no_color()`, while file display (`app.rs:458`) and the clap color setting (`src/bin/bat/clap_app.rs:22`) both do. So `NO_COLOR=1 bat --help` in a terminal is colored. Not this PR's to fix, though the new `|| is_mintty` now extends it to piped help in MSYS2 shells.

Wouldn't merge as is: finding 1 is a regression for anyone in Git Bash who redirects `bat --help`.

Lean: -16 lines possible
