Important: 3, Nit: 1, Pre-existing: 0

## Important

**1. Reverts a feature the project shipped on purpose, and overrides an explicit `--paging=always`.**
`src/bin/bat/app.rs:325-327` forces `PagingMode::Never` whenever `--list-themes` is set. Paging for `--list-themes` is a released feature, and it got a follow-up fix a release later:

- `CHANGELOG.md:78` (v0.26.0): "Add paging to `--list-themes`, see PR #3239 (@einfachIrgendwer0815)"
- `CHANGELOG.md:51` (v0.26.1): "Fix hang when using `--list-themes` with an explicit pager, see #3457 (@abhinavcool42)"
- `src/bin/bat/main.rs:251-254` (from #3457) buffers the whole theme list, then sends it through `OutputType::from_mode(config.paging_mode, ...)` so it can reach the pager. After this PR that call always gets `Never`, so the pager path #3457 fixed can't run any more.
- `src/bin/bat/app.rs:304-306` already special-cases `--list-themes` inside the `auto` arm (ignore stdin so paging still turns on). Someone tuned this flag's paging on purpose.

Concrete case: `bat --list-themes --paging=always` in a terminal pages the list on base. On HEAD it dumps every theme preview straight to the terminal, ignoring a flag the user typed. The same goes for `BAT_PAGING=always` and `--pager=builtin`. The body says only "Fixes #1618", with no quote from that issue and no reason it outweighs #3239 and #3457. #1618 is roughly 2,000 numbers older than #3239, so whatever it asked for has to be reconciled with the later decision in the body. Otherwise this reads as undoing a maintainer-approved feature.

If an issue really shows paging breaking `--list-themes`, fix that case (as #3457 did for the hang) and keep the flag working. The new test `tests/integration_tests.rs:617-628` pins the opposite of the shipped behavior: it asserts that `--paging=always` does *not* page.

**2. No changelog entry, which `CONTRIBUTING.md` requires and CI enforces.**
`CONTRIBUTING.md`: "Please update the changelog if your contribution contains changes regarding any of the following: - the behavior of `bat`". This PR changes how `bat --list-themes` pages, and `git diff base...HEAD --stat` touches only `src/bin/bat/app.rs` and `tests/integration_tests.rs`. `.github/workflows/require-changelog-for-PRs.yml` greps `CHANGELOG.md` for `#<PR number> ... <submitter>` and fails without it.

**3. Nobody compiled or ran the change, and the body says so in agent voice.**
`pr-body.md` Validation: "attempted cargo test ... *(not runnable here: cargo toolchain is unavailable in this environment)*". The only check that ran is `git diff --check`, which is a whitespace check. So the new test has never gone red on base or green on HEAD, and nobody ran the existing `list_themes_*` and pager tests against the change. "not runnable here" and "this environment" read as an agent describing its sandbox to itself. Run `cargo test --test integration_tests` before asking for review, paste the result, and write the body in your own words.

## Nit

**4. The override leaves the guard at `src/bin/bat/app.rs:304-306` dead.**
Since lines 325-327 overwrite `paging_mode` after the match, `&& !self.matches.get_flag("list-themes")` and its comment can never change the result. If the behavior change survived (see 1), it belongs inside the match the way the neighbors branch (`extra_plain` and `no-paging` are handled per arm), with the dead guard deleted. That also drops the new `let mut`.

Lean: -2 lines possible
