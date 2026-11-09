Important: 3, Nit: 1, Pre-existing: 0

## Important

**1. Reverts a feature the project shipped on purpose (paging for `--list-themes`).**

`CHANGELOG.md:78`, under v0.26.0 Features, reads "Add paging to `--list-themes`, see PR #3239". `CHANGELOG.md:51`, under v0.26.1 Bugfixes, reads "Fix hang when using `--list-themes` with an explicit pager, see #3457". So maintainers added this paging, then fixed a bug in it one release later. The code still shows the design: `list_themes` buffers its whole output and writes it through `OutputType::from_mode(config.paging_mode, ...)` at `src/bin/bat/main.rs:251-253`. `src/bin/bat/app.rs:305-306` also special-cases `--list-themes` inside the `auto` branch so it gets `QuitIfOneScreen` on a terminal even when stdin isn't a TTY.

The new block at `src/bin/bat/app.rs:325-327` forces `PagingMode::Never` for every `--list-themes` run. Every way into the pager is now dead:
- `bat --list-themes` on an interactive terminal: base gives `QuitIfOneScreen` (`app.rs:316-317`), HEAD never pages. That's the default case, and every theme's colored preview scrolls past.
- `bat --paging=always --list-themes`: an explicit user request is silently dropped, which contradicts the `--paging` help at `src/bin/bat/clap_app.rs:340` ("Specify when to use the pager").
- `BAT_PAGING=always` or `paging=always` in the config file: same as above.

The body gives no reason this should change, and `Fixes #1618` is a 2021-era issue number that predates #3239. If #1618 wanted the pager gone, it was superseded when maintainers chose the opposite. If there's a real bug left (a specific pager hanging or garbling the preview), name it and fix that case, not the whole feature.

**2. No changelog entry.**

`CONTRIBUTING.md`: "Please update the changelog if your contribution contains changes regarding any of the following: the behavior of `bat`". This diff changes what `bat --list-themes` does on a terminal and leaves `CHANGELOG.md` untouched (`git diff base...HEAD --stat` shows only `src/bin/bat/app.rs` and `tests/integration_tests.rs`). The CONTRIBUTING note says the CI workflow fails without one.

**3. The body says the test "verifies" something nobody ran.**

The Summary says the PR adds "an integration test that verifies `--list-themes --paging=always` does not invoke the configured pager". The Validation section says `cargo test` was "not runnable here: cargo toolchain is unavailable". So the code was never compiled and the test never ran on base or HEAD. `git diff --check` is a whitespace check, so it doesn't count as validation. Run `cargo test --test integration_tests list_themes` on both trees and paste the output, or drop the word "verifies".

## Nit

**`src/bin/bat/app.rs:305-306` is now dead.** The `&& !self.matches.get_flag("list-themes")` guard and its comment only matter if `--list-themes` can still reach a pager, and line 325 overrides whatever the match picks. If this change stood, the guard should go with it. (Moot if finding 1 holds.)

Lean: -20 lines possible (the whole diff; the shipped behavior is the intended one)
