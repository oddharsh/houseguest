Important: 2, Nit: 3, Pre-existing: 0

This is the parallel-walker follow-up to c10f151 ("ignore: always include depth in errors", #3453). It's the right idea, and the `from_path` hunks are the ones that matter: `rg -L` (parallel walker, `follow_links(true)`) on a broken symlink at depth 1 goes through `DirEntryRaw::from_path` at `walk.rs:1759`, and before this PR that error's `depth()` was `None`. Two things to fix before merge.

## Important

**1. Two hunks tag depth on errors that already carry it, so they now hold it twice.**
`crates/ignore/src/walk.rs:331` and `crates/ignore/src/walk.rs:344` add `.with_depth(depth)` inside a closure whose next line (`:332`, `:345`) already wraps the result in `Error::WithDepth { depth, err: Box::new(err) }`. When `ent.file_type()` fails at depth 3, `from_entry` now returns `WithDepth{3, WithPath{p, WithDepth{3, Io}}}`. Before the PR it returned `WithDepth{3, WithPath{p, Io}}`, and `Error::depth()` (`lib.rs:252`) already gave `Some(3)`. So these hunks change nothing `depth()` can see. What they do change is the nesting of a public enum: a caller that matches `WithDepth { err, .. }`, then `WithPath { err, .. }`, then expects `Io` now hits a second `WithDepth`. c10f151's own message flags that kind of structural change as a possible break. Fix: revert both hunks. The `io::Error::from(err)` removals on those lines are identity conversions and can go back too.

**2. The Unix `metadata_internal` got depth; its Windows twin didn't.**
The diff changes the `#[cfg(not(windows))]` `DirEntryRaw::metadata_internal` (`walk.rs:304-306`) but leaves the `#[cfg(windows)]` one at `walk.rs:294` as `Error::Io(io::Error::from(err)).with_path(&self.path)`. Concrete case: on Windows, `DirEntry::metadata()` on a followed symlink whose target is gone returns an error with `depth() == None`; on Unix the same walk returns `Some(depth)`. Everywhere else the diff edits both cfg twins (`from_path` at `:394` and `:413`), so this one reads as missed. The same class has one more instance with depth in scope: `is_same_file_system` (`walk.rs:2024`), called from `walk.rs:1665` with `work.dent` right there, still returns `Error::Io(err).with_path(path)` with no depth. Either add depth at both or say in the body why they stay out.

## Nits

**3. `DirEntryInner::metadata` hand-rolls `Error::from_walkdir`.**
`walk.rs:181-185` builds `Error::Io(io::Error::from(err)).with_depth(x.depth()).with_path(x.path())` from a `walkdir::Error`. `Error::from_walkdir` (`crates/ignore/src/lib.rs:285`) already does exactly that, taking depth and path from the walkdir error itself, in the same `WithPath{WithDepth{Io}}` order. `walk.rs:1130` uses it. One line, fits in 79 columns:

```rust
Walkdir(ref x) => x.metadata().map_err(Error::from_walkdir),
```

**4. No test, and the body doesn't say which case it fixes.**
"More cases where we know the appropriate depth" doesn't tell me which public call changes. The case worth naming (and testing) is the one above: a temp dir holding `broken -> nonexistent`, `WalkBuilder::new(dir).follow_links(true).build_parallel()`, collect the errors, assert `err.depth() == Some(1)`. That fails on `base` and passes here. Link #3453 and c10f151 in the body so the connection is visible. c10f151 shipped without a test, so I won't block on it, but it's a cheap guard for the only behavior this PR adds.

**5. Subject line doesn't match the repo's convention.**
`feat[ignore]: Add depth to more errors`. Every crate commit in `git log base` uses `ignore: <lowercase summary>` (`ignore: always include depth in errors`, `ignore: only stat .jj if we actually care`). Suggest `ignore: add depth to more walk errors`.

Lean: -4 lines possible
