Important: 2, Nit: 2, Pre-existing: 0

## Important

**1. The PR body reads as machine-written, which the AI policy says gets the PR closed.**

`AI_POLICY.md`: "If you are opening a pull request, you are expected to be able to explain the proposed changes in your own words. This includes the pull request body and responses to questions." `CONTRIBUTING.md`: "Contributions not following the AI Policy will be closed."

Instances in `pr-body.md`:
- The em dash in "The change is purely organizational — the matching behavior is identical."
- "It improves determinism for build systems and CI pipelines." No build system or CI pipeline is named, and nothing in ripgrep's CI depends on this order (see finding 2).
- The title uses a conventional-commit prefix, `fix(types):`. This repo titles changes by crate path: `dfe4a81 ignore/types: add Hurl`, `9b84e15 ignore/types: add container type...`. It also says "fix" when no bug is named.

Rewrite the body in your own words, naming the concrete case you hit. If there isn't one, see finding 2.

**2. The body's central claim is false: the output was already deterministic on base.**

The body says the change "makes the output reproducible across runs." On base, `TypesBuilder::definitions()` already sorted by name: `defs.sort_by(|def1, def2| def1.name().cmp(def2.name()))` at `crates/ignore/src/types.rs:374` (base). That's the line this PR deletes. `Types::definitions()` (`types.rs:251`) returns the same sorted vector, and its doc comment already promised "Definitions and globs are sorted." So `rg --type-list` and every other caller of `definitions()` got the same order on every run before this PR.

The one order the swap really changes goes unmentioned in the body: `select("all")` and `negate("all")` iterate `self.types.keys()` (`types.rs:382`, `types.rs:396`). Under a HashMap that order was random per process; under a BTreeMap it's by name. With `-tall`, a file like `main.py` matches both `py` and `python`, and `matched()` reports "the last one" (`types.rs:284`). So which definition gets attributed in the returned `Glob` used to vary between runs, and now it doesn't. If that's what you're after, say so, show where the attribution surfaces, and add a test for it. As written, the PR removes a sort and calls the result a fix.

## Nit

**3. The new test passes on base, so it doesn't show the PR changed anything.** `test_deterministic_order` (`types.rs:584`) asserts sorted names from `definitions()`, and base sorted them at `types.rs:374`. It does catch one regression (going back to `HashMap` without restoring the sort), so it isn't useless. Run it on base before calling it proof of the change, though.

**4. Dead and stale lines in the test.** `let _ = btypes.build().unwrap();` (`types.rs:592`) does nothing for the assertion: `definitions()` reads the builder, never the built `Types`. The comment at `types.rs:585-587` says "regardless of HashMap iteration quirks" in a file that no longer uses `HashMap`, and it only restates the assertion below it. Delete both.

Lean: -4 lines possible (the `build()` line and the 3-line comment). Ladder rung 1 also applies: unless finding 2's `-tall` attribution is the real motivation, the change needn't exist.
