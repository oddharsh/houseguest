Important: 2, Nit: 2, Pre-existing: 0

## Important

**1. No demonstrated need: the output this PR says it makes deterministic was already deterministic at base, and the new test passes on base.**

The body says the swap "makes the output reproducible across runs" and "eliminates redundant sorting operations." Neither holds up against the base code:

- At base, `TypesBuilder::definitions()` sorted every def by name (`defs.sort_by(|def1, def2| def1.name().cmp(def2.name()))`, base `crates/ignore/src/types.rs:374`) and sorted each def's globs. Every user-visible ordering goes through that function: `build()` stores its result (`crates/ignore/src/types.rs:323`), `Types::definitions()` returns it (`:251`), and `rg --type-list` prints it (`crates/core/main.rs:332`). So `--type-list` and `definitions()` were already reproducible run to run.
- `test_deterministic_order` (`crates/ignore/src/types.rs:584`) asserts `["combo", "foo", "html", "js", "py", "python", "rust"]`. Base `definitions()` returns exactly that list, so the test passes before and after the change. It pins the order; it doesn't show any bug this PR fixes.
- "Redundant sorting": the removed sort runs once per `build()` or `--type-list`, over a few hundred defs. In exchange, every `add()` call in `add_defaults()` (once per name per glob in `DEFAULT_TYPES`, on every `rg` startup) does a `BTreeMap` lookup with string comparisons in place of a hash. That trade may well be a wash, but the PR gives no measurement in either direction, so it can't claim a win.

The only ordering the swap actually changes is `select("all")` and `negate("all")`, which iterate `self.types.keys()` (`crates/ignore/src/types.rs:382`, `:396`). At base that's `HashMap` order, so with `-tall` a file matching two types (`main.py` against both `py` and `python` in the test fixtures, `:534-535`) can report either def through `Glob::file_type_def()` and the `--debug` "whitelisting" line (`crates/ignore/src/walk.rs:1945`). Whether a match is whitelisted or ignored doesn't change, since every selection from `all` has the same kind. The body never names this case and the test doesn't exercise it.

I'd rather keep the status quo than swap the map without a reason. If that `-tall` def-reporting case is what you hit, say so in the body, show the run-to-run difference, and test that path (select `all`, match `main.py`, assert the `file_type_def()` name). Otherwise I'd close this.

**2. The PR body and the new test comment read as machine-written, which `AI_POLICY.md` (linked from `CONTRIBUTING.md`) rules out.**

`AI_POLICY.md`: "If you are opening a pull request, you are expected to be able to explain the proposed changes in your own words. This includes the pull request body and responses to questions." `CONTRIBUTING.md`: "Contributions not following the AI Policy will be closed."

Instances:

- `pr-body.md`: "The change is purely organizational" sits beside a title that calls it a `fix` for determinism. The two claims contradict each other.
- `pr-body.md`: "It improves determinism for build systems and CI pipelines." No build system, pipeline, or command is named, and per finding 1 the output it would affect was already sorted.
- `crates/ignore/src/types.rs:585-587`: the test comment says it verifies order "regardless of HashMap iteration quirks," but after this diff the file no longer uses a `HashMap`, and the test exercises nothing hash-ordered.

Please rewrite the body yourself, naming the concrete case you saw.

## Nit

**1. `let _ = btypes.build().unwrap();` (`crates/ignore/src/types.rs:592`) does nothing for the assertion.** `TypesBuilder::definitions()` reads `self.types` directly and doesn't depend on `build()` having run. Delete the line, and the 3-line comment above it with finding 2.

**2. Commit and title don't match the repo's style or the change.** The single commit is titled "test: add deterministic order test for TypesBuilder" but it also swaps the map and drops the sort. The PR title uses a conventional-commit prefix (`fix(types):`); this repo writes `area: message`, as in the base commit `dfe4a81` "ignore/types: add Hurl".

Lean: -4 lines possible (the whole diff, 24 lines, if no concrete case turns up)
