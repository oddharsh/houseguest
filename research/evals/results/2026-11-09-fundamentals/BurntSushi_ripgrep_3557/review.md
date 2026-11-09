Important: 2, Nit: 0, Pre-existing: 0

The code change looks right to me. I traced `matched_ignore` (`crates/ignore/src/dir.rs:553-688`): when every absolute parent's four matchers are empty, the skipped loop at `dir.rs:633-666` can only change `saw_git`, and nothing reads `saw_git` after that loop. `any_git` is computed from the full chain at `dir.rs:565-566` before the gate, and the explicit and global matchers after the block use the outer, unrewritten `path`. The flag is accumulated with `|=` in `add_parents` (`dir.rs:246-250`), inherited by every child in `add_child_path_with_found_ignore_files` (`dir.rs:453`), and lives on the cached `IgnoreInner`, so a prebuilt parent from `compiled` carries it too. The first test covers each of the four matchers through an empty absolute parent (`td/a`), so dropping the `|=`, the inheritance, or any one arm of the `||` turns it red. What blocks me is the description: this is a performance PR, and the numbers that justify it don't hold up.

## Important

**1. The speed and allocation numbers were measured against the wrong base, and the base they name already includes neighboring wins in the same code.**

The body says "On Linux x86-64 against `3fce3b5`". This branch's parent is `b5611fc` (`git rev-parse HEAD^`), and `git log 3fce3b5..b5611fc` shows 8 commits in between. Three of them bear directly on the claims:

- `c5e744c` "ignore: avoid scratch pools for empty matchers" makes `GitignoreBuilder::build` return `Gitignore::empty()` when there are no globs (`crates/ignore/src/gitignore.rs:350-352`), and its message says it avoids "allocation for scratch pools". Before it, matching a path against an absolute parent's empty matchers could still touch scratch pools. This PR skips that same matching, so a `3fce3b5` baseline counts `c5e744c`'s savings toward "replay allocates or reallocates about half as often".
- `b5611fc` "ignore: reuse parent repository detection" changes the same `add_parents` loop this PR edits (`dir.rs:244-245`).
- `fada8f9` adds `crates/ignore/benches/workloads.rs`, which doesn't exist at `3fce3b5`, so "warm incremental matching" (presumably `incremental_warm`) had to be backported to measure there, and the body doesn't say how.

So the 13.4% and the "about half" may be mostly `c5e744c` and `b5611fc`. Rerun `incremental_warm`, the allocation count, and the controls with `b5611fc` as the baseline and HEAD as the candidate, and put those numbers in the body.

**2. The measurements don't follow the method `crates/ignore/benches/README.md` asks for, so nobody can reproduce or weigh them.**

The bench README says to "Alternate baseline and candidate runs, and retain the per-run results instead of relying on a single measurement" (line 66-67). It also says "Report affinity with results, especially when comparing construction or cached matching costs" (line 72-73), and "Check promising changes in both configurations" for fat LTO and the profiling build (line 76). The body falls short of that in five places:

- Every result is a single percentage, with no per-run numbers, spread, or run count.
- It gives no CPU affinity and no LTO configuration.
- It names no benchmark. "replay" matches nothing in `crates/ignore/benches/` (`grep -rn replay crates/ignore/benches/` is empty), and "cached ignored-path control" could be `incremental_ignored`, `incremental_ignored_parent`, or `incremental_ignored_nested`.
- "Warm-cache walks of the Ruff and uv checkouts improve 1-4%" uses trees that aren't in the repo, at unnamed revisions, with no command.
- The control moved 3.3% the wrong way. On a path where absolute parents have rules, the diff adds a single `bool` load at `dir.rs:600`, and an ignored-path cache hit may not reach `matched_ignore` at all. A 3.3% swing there puts the noise floor at or above the 1-4% walk gains the body reports. Either explain the slowdown or drop the walk claim.

Name each benchmark the way `workloads.rs` does, give the exact `cargo +nightly bench -p ignore --bench workloads ...` lines and the affinity, and paste the per-run results for base and HEAD (or put them in a collapsed block).
