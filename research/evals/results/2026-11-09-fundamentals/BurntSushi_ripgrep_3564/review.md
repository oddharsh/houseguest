Important: 1, Nit: 1, Pre-existing: 1

The fix itself is right: `file_name` now rejects only an exact `.` or `..` final component, which is also what `crates/globset/src/pathutil.rs:9` already does for globs (it rejects only `..`). The tests exercise the bug and the walker test would go red on base. What blocks me is a second user-visible change the body never mentions.

## Important

**1. Undisclosed, untested behavior change in file type matching (`-t`/`-T`).**
`file_name` has a second caller: `Types::matched` at `crates/ignore/src/types.rs:275`. At base, any file whose name ends in `.` got `None` there, so with a type selected it fell into the `None if self.has_selected => Match::Ignore` arm, and with only negations it got `Match::None`. At HEAD the name reaches the glob set. Concrete case with the default types (`crates/ignore/src/default_types.rs:170`, `make` includes `Makefile.*`): a file named `Makefile.` is skipped by `rg -tmake` at base and searched at HEAD; `rg -Tmake` searches it at base and skips it at HEAD. Same for `Kconfig.` under `-tkconfig` (line 126) and `license.` under `-tlicense` (line 135).

I think the new behavior is the correct one (it matches what `-g 'Makefile.*'` already does via globset), so this is fixing the root cause once, which is good. But the PR title and body describe only hidden-file handling, and nothing tests the types path. Please:
- say in the body that `-t`/`-T` now apply to names ending in `.`, so it lands in the CHANGELOG correctly;
- add one line to the existing `matched!` tests in `crates/ignore/src/types.rs` (around line 546), e.g. `matched!(match_trailing_dot, vec!["make:Makefile.*"], vec!["make"], vec![], "Makefile.");`, which fails on base and passes on HEAD.

## Nit

**2. Two of the four new unit tests cover nothing the other tests don't.** (`crates/ignore/src/pathutil.rs:181`, `:209`)
`file_name_basic` pins behavior this PR doesn't change, and `hidden_trailing_dot` checks the same names (`.foo.`, `.foo..`, `...`, `foo.`) that `hidden_with_trailing_dot` in `walk.rs` already checks end to end. `file_name_dot_components` and `file_name_trailing_dot` are the ones that pin the fix. Dropping the other two also drops the `Path` and `is_hidden_path` imports. I'd merge with them in; I'd rather not maintain them.

## Pre-existing

**3. `file_name`'s doc comment says a root returns `None`; the Unix impl returns `Some("")`.** (`crates/ignore/src/pathutil.rs:140-141`, blamed to c55818f)
On Unix, `file_name("/")` and `file_name("a/")` both return `Some("")` at base and at HEAD (the last byte is `/`, so no guard fires and the slice after the last slash is empty), while the doc says "consists solely of a root of prefix" yields `None` (and "of prefix" is presumably "or prefix"). This PR doesn't touch that branch or make it worse, so it belongs in its own change if anyone cares.

Lean: -19 lines possible
