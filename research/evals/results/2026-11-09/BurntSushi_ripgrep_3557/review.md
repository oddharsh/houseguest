Important: 1, Nit: 1, Pre-existing: 0

The code looks right to me. I traced the flag through all three `IgnoreInner` constructors (`dir.rs:246`, `dir.rs:453`, `dir.rs:852`) and the `compiled` cache reuse in `add_parents`, and skipping the absolute-parent loop only drops `saw_git` updates that nothing reads after the loop (`any_git` is computed from all parents before it). The problem is the numbers that justify it.

## Important

**1. The benchmark claims don't isolate this change and don't follow the repo's own benchmarking instructions.** (`pr-body.md`, paragraph 2)

- **Wrong baseline.** The body measures "against `3fce3b5`", which is the `ignore-0.4.33` tag. The PR's base is `b5611fc`, and `3fce3b5..b5611fc` holds 8 commits, including `c5e744c` (#3555, "avoid scratch pools for empty matchers") and `b5611fc` (#3556). #3555 also targets empty matchers and cuts allocation. So the 13.4% and the "allocates or reallocates about half as often" figures likely include #3555's savings. Please rerun with `b5611fc` as the baseline. If this is stacked on #3555/#3556, say so in the body.
- **Missing run details.** `crates/ignore/benches/README.md` says to "Report affinity with results". It also says to "retain the per-run results instead of relying on a single measurement", and to check promising changes with and without fat LTO. The body gives one percentage per claim, with no affinity, no LTO configuration, and no run count.
- **Unnamed benchmarks.** "Warm incremental matching" presumably means `incremental_warm`. Nothing in `workloads.rs` is called "replay", so I can't tell what was measured or with which tool. "The cached ignored-path control" could be `incremental_ignored`, `incremental_ignored_parent`, or `incremental_ignored_nested`. Please name the exact `--exact` cases and give absolute times.
- **The slower control undercuts the walk gains.** That control got 3.3% slower, but on that path the change only adds one bool check in `matched_ignore` (`dir.rs:600`). If that's noise, then the noise floor is about 3%, and the "1–4%" Ruff/uv walk improvements are inside it. If it's real, it needs an explanation. The Ruff/uv checkout walks also aren't in the bench suite, and no command or revision is given for them.

## Nit

**2. The looped test doesn't say which ignore file failed.** `dir.rs:1461-1463` runs the same three asserts for `.ignore`, `.gitignore`, `.customignore`, and `.git/info/exclude`. If one of the four `!is_empty()` terms at `dir.rs:246-250` is dropped, the failure prints only `ig.matched(child.join("blocked"), false).is_ignore()`, and you have to bisect the loop by hand to see which one. Add `"{name}"` as the assert message, the way `multi_root_gitignore_order_independent` attaches messages to its asserts.

Would merge once the numbers are redone against the real base with the details the bench README asks for.
