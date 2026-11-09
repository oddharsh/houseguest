Important: 0, Nit: 3, Pre-existing: 0
No blocking issues

The fix is right and sits where the bug starts. The old Unix `file_name` rejected any path whose last byte was `.`, which diverged from what the function's own doc comment and the non-Unix branch (`Path::file_name`) promise: `std` returns `Some(".foo.")` for `a/.foo.` and `None` only for a trailing `.` or `..` component. The new check on the final component matches that. The walker test at `crates/ignore/src/walk.rs:2406` fails on base (`.hidden.`, `.hidden..`, `...` and `.dir./inner` all show up without `hidden(false)`) and passes on HEAD, so it guards the regression. Would merge after the nits below, or as is.

## Nits

**1. The body leaves out the second caller this changes.** `file_name` also feeds file type matching at `crates/ignore/src/types.rs:275`. On base, a file named `Dockerfile.` got no name, so `rg -t docker --files` dropped it (`Match::Ignore` via the `None if self.has_selected` arm) and `rg -T docker` never excluded it. On HEAD the name reaches the glob set, `*Dockerfile*` matches it, and both flags now see the file. Same for `LICENSE.` under `-t license` (`LICEN[CS]E[.-]*`). That's the correct behavior, and it lines up with Windows, but it's a user-visible change in `-t`/`-T` that the body describes as a hidden-files-only fix. One sentence in the body saying so would let the changelog entry cover both.

**2. The doc comment the change depends on still reads the old way.** `crates/ignore/src/pathutil.rs:140` says "If the path terminates in `.`, `..`, ...". That wording is exactly the ambiguity the old code fell into (trailing byte vs. trailing component). Rewording it to "the final component is `.` or `..`" would let the inline comment at `pathutil.rs:157-158` go, since it restates the same rule inside the body.

**3. One cause, three layers of tests.** `hidden_trailing_dot` (`pathutil.rs:209`) checks the same names as the walker test and `file_name_trailing_dot` (`pathutil.rs:201`) put together, so it can't fail without one of those failing too. `file_name_basic` (`pathutil.rs:181`) pins behavior the diff doesn't touch. Keep `file_name_dot_components` (it's the only check that `.` and `..` still return `None` after the guard moved), `file_name_trailing_dot`, and the walker test; drop the other two along with the `std::path::Path` and `is_hidden_path` imports they alone need (`pathutil.rs:176`, `pathutil.rs:178`).

Lean: -18 lines possible
