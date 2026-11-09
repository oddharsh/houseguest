Important: 3, Nit: 2, Pre-existing: 1

## Important

**1. The fix only reaches `--help`; the body and CHANGELOG say it also fixes normal file display, and it doesn't.**

`is_mintty` is read in exactly one place, the help branch at `src/bin/bat/app.rs:117`. Every other consumer of terminal detection still sees only `is_terminal()`, so `bat somefile.rs` in mintty behaves exactly as it did on `base`:

- `src/bin/bat/app.rs:458`: `Some("auto") => !env_no_color() && self.interactive_output` decides `colored_output` for file display. Untouched.
- `src/bin/bat/app.rs:463`: `loop_through` is still `true` when `interactive_output` is false, so file display stays in cat mode.
- `src/bin/bat/app.rs:334`, `:339`, `:438`: paging and width decisions, same `self.interactive_output`.
- `src/theme.rs:265`: `should_detect` calls `std::io::stdout().is_terminal()` directly for the OSC 10/11 theme probe.

The new comment at `app.rs:62-66` even says so ("we do NOT override interactive_output itself"), which contradicts:

- `pr-body.md`: "This caused `bat --help` (and regular file display) to lose colored output", and testing step 4, "Run `bat somefile.rs` and confirm syntax highlighting works."
- `CHANGELOG.md:25`: "restoring colored output for `bat --help` and normal file display."

If the root cause is real, it's in how `interactive_output` is computed at `app.rs:61`, and a fix belongs there once rather than in one of its 7 readers. If only help is broken, the body and CHANGELOG need to say help only, and explain why file display works when it reads the same flag.

**2. `MSYSTEM` is an environment heuristic, so `--color=auto` help output is now colored when it's piped or redirected inside any MSYS2 shell.**

`is_mintty_terminal()` (`src/bin/bat/app.rs:201-206`) returns true whenever `MSYSTEM` is set, and `MSYSTEM` is inherited by every child process of a Git Bash, MINGW64, or UCRT64 shell regardless of where stdout points. Concrete cases that now write ANSI escapes where `base` wrote plain text:

- `bat --help > help.txt` in Git Bash.
- `bat --help | grep -- --theme` in an MSYS2 shell running under Windows Terminal or conhost, where `is_terminal()` already returns true for the console and false for the pipe, as it should.
- Any Windows tool that spawns `bat --help` from an environment that inherited `MSYSTEM` (an editor launched from Git Bash, for example).

The comment at `app.rs:65-66` claims "piping (bat file | grep foo) still works correctly," but that's only true because file display isn't touched (finding 1). The one path the PR does change loses its pipe detection. `TERM_PROGRAM=mintty` has the same problem in a pipe, though it at least names the terminal.

**3. The root cause and the history in the body aren't backed by anything, and the CHANGELOG contradicts the history.**

- Root cause: the body says `is_terminal()` returns false under mintty "because mintty uses POSIX PTYs that Windows's `isatty()` does not recognize." `std::io::IsTerminal` doesn't call `isatty()` on Windows; its docs say it uses a heuristic that treats msys-/cygwin- named pty pipes as terminals, which is the mintty case. Maybe that heuristic misses some setup in #3034, but the PR needs output from a real mintty session showing `is_terminal()` returning false (bat version, Rust version, mintty/Git Bash version) before a maintainer takes an env-var override on faith.
- History: "starting with v0.23.0, when help rendering moved from clap's built-in output to bat's own syntax-highlighting pipeline." The v0.23.0 section of `CHANGELOG.md` (line 320 on) has no help-rendering or terminal-detection entry. Help went through bat's pipeline with "Add paging to '-h' and '--help' see PR #3478" under v0.26.1 (`CHANGELOG.md:80`), and the `atty` to `is-terminal` switch is #2530 under v0.24.0 (`CHANGELOG.md:295`).
- Testing: the only result reported is "232 passed, 0 failed," and the changed function is `#[cfg(windows)]`, so on a non-Windows run that number covers none of it. The mintty steps are written as instructions for someone else ("To manually test..."), with no output saying they were run. Nothing in the PR shows it was exercised in the environment it targets.

## Nit

**4. No regression test.** `CONTRIBUTING.md` ("Regression tests"): "You are **strongly encouraged** to add regression tests," and "For functional changes, you most likely want to add a test to `tests/integration_tests.rs`." A Windows-only integration test that runs `bat --help` with `MSYSTEM` set and stdout captured would also have caught finding 2 (it would show escapes in captured output).

**5. Lean, on the contributor's own lines.**

- `src/bin/bat/app.rs:202-204`: `.map(|v| v == "mintty").unwrap_or(false)` is `.is_some_and(|v| v == "mintty")`, the form `env_no_color()` uses at `app.rs:38` (MSRV is 1.88).
- `app.rs:208-211`: the `#[cfg(not(windows))]` stub goes away with `cfg!(windows) && ...` in the body of one function.
- `app.rs:62-67`: a 5-line comment plus a local computed on every run, 50 lines above its single use inside the help branch, and the comment repeats the doc comment at `:197-199`. The check can sit inline at `:117`.

## Pre-existing

**6. `--help` ignores `NO_COLOR`.** On `base`, `app.rs:110` was `_ => interactive_output`, while file display (`app.rs:458`) and clap (`clap_app.rs:22`) both check `env_no_color()`. So `NO_COLOR=1 bat --help` in a terminal is colored today. Not this PR's to fix, though the new `|| is_mintty` widens the set of environments it applies to.

Lean: -12 lines possible
