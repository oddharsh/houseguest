Important: 0, Nit: 3, Pre-existing: 1
No blocking issues

The fix is right and lands in the right place. The Unix `file_name` in `crates/ignore/src/pathutil.rs` was rejecting any path whose last byte is `.`, which diverged from the non-Unix branch (`Path::file_name` returns `Some("foo.")` for `a/foo.`). Checking the final component against exactly `.` and `..` matches what the function is for. The walker test at `crates/ignore/src/walk.rs:2406` fails on base: `.hidden.`, `.hidden..`, `...`, `.dir.` and `.dir./inner` all show up without `--hidden`. The body explains the cause in plain words and I see nothing that runs against `AI_POLICY.md`.

Would merge. The three nits below are small enough that I'd take them in a follow-up commit or fix them myself.

## Nits

**1. The doc comment on `file_name` still describes the old behavior.** `crates/ignore/src/pathutil.rs:140` says "If the path terminates in `.`, `..`, ... this will return `None`." After this change `file_name("a.")` returns `Some("a.")` (and the new test at line 202 asserts it), so a reader takes the doc at face value and gets it wrong. Say "terminates in a `.` or `..` component". That also lets the new inline comment at lines 157-158 go, since it restates the same rule.

**2. The body leaves out the second caller.** `file_name` also feeds file type matching at `crates/ignore/src/types.rs:275`. On base, a name ending in `.` returned `None`, which with a type selected means `Match::Ignore`. Concrete case: the `license` type includes `COPYING[.-]*` (`crates/ignore/src/default_types.rs:132`), so `rg -tlicense` skipped a file named `COPYING.` on base and lists it now. That's the correct result, but it's a user-visible change the description and title don't mention. One sentence in the body covers it.

**3. Two of the four unit tests don't test the change.** `file_name_basic` (`pathutil.rs:180-185`) pins inputs whose output didn't change. `hidden_trailing_dot` (`pathutil.rs:208-217`) checks the same names the walker test already checks end to end, through the same `is_hidden_path_only` path. `file_name_trailing_dot` plus the walker test catch a regression; the other two can go.

## Pre-existing

**`file_name` returns `Some("")` for a root or a trailing slash.** On Unix, `file_name("/")` and `file_name("a/")` find the last `/` at the end and return an empty name, while the doc at `pathutil.rs:140-141` promises `None` for a bare root. Blame puts these lines in c55818f (2026-07-17), before this PR, and the diff doesn't change that result. Not for this PR.

Lean: -17 lines possible
