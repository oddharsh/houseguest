Important: 3, Nit: 1, Pre-existing: 0

## Important

**1. Reverses paging for `--list-themes`, which the project added on purpose two releases ago.**
`src/bin/bat/app.rs:325-327` forces `PagingMode::Never` whenever `--list-themes` is set. That undoes deliberate, recent work:

- `CHANGELOG.md:78` (v0.26.0): "Add paging to `--list-themes`, see PR #3239".
- `CHANGELOG.md:51` (v0.26.1): "Fix hang when using `--list-themes` with an explicit pager, see #3457". A maintainer merged a fix to keep the pager path working, so paging was kept on purpose after it caused trouble.
- `src/bin/bat/app.rs:305-306` carries a branch written only so `--list-themes` still pages when stdin is a pipe ("ignore stdin when --list-themes is used because in that case no input will be read anyways"). Nobody writes that guard for a mode that shouldn't page.

Concrete case: `bat --list-themes` in a terminal prints a colored preview for every bundled theme, which runs hundreds of lines. On base it opens in the pager with quit-if-one-screen. On this PR it scrolls past and the first themes are gone. Worse, `bat --list-themes --paging=always` now silently ignores an explicit user flag, and the new test locks that in.

The body says only "Fixes #1618" and names no factual error that #3239 or #3457 rested on. I can't read #1618 offline, but its number is far older than #3239, so it most likely predates the paging work rather than reporting a regression from it. If there's a real problem with paging here (a hang, a pager that misbehaves), describe it and fix that case; don't turn the feature off.

**2. No changelog entry for a behavior change.**
`CONTRIBUTING.md`: "Please update the changelog if your contribution contains changes regarding any of the following: - the behavior of `bat`". This diff changes what `--list-themes` does and doesn't touch `CHANGELOG.md`. The CONTRIBUTING note says CI fails on a missing entry, so this PR is red as submitted.

**3. The test and fix were never compiled or run.**
The body's own Validation section says `cargo test` was "not runnable here: cargo toolchain is unavailable". So the claim that the new test "verifies --list-themes --paging=always does not invoke the configured pager" (`tests/integration_tests.rs:615-628`) has no output behind it, and nobody checked that the existing `list_themes_*` tests still pass. Run `cargo test --test integration_tests` and paste the result before asking for review.

## Nit

**4. The override leaves the `--list-themes` stdin guard dead.**
Because the new block at `src/bin/bat/app.rs:325-327` overwrites `paging_mode` after the match, the `&& !self.matches.get_flag("list-themes")` condition at `src/bin/bat/app.rs:305-306` (and its comment) can no longer affect the result. If this change survived in some form, that guard should go with it, and `let mut paging_mode` plus a post-match overwrite reads slower than handling the flag inside the match. Moot if finding 1 holds.

Wouldn't merge: finding 1 alone is a close, since it reverses a choice the maintainers made and then defended with a follow-up fix.

Lean: -2 lines possible
