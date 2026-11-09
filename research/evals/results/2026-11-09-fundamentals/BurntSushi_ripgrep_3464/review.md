Important: 2, Nit: 3, Pre-existing: 0

## Important

**1. The Windows twin of a changed function was missed, so `DirEntry::metadata()` errors carry depth on Unix and not on Windows.**

The diff adds depth to `DirEntryRaw::metadata_internal` only in the `#[cfg(not(windows))]` copy (`crates/ignore/src/walk.rs:297-306`). The `#[cfg(windows)]` copy right above it (`crates/ignore/src/walk.rs:287-295`) still ends in `.map_err(|err| Error::Io(io::Error::from(err)).with_path(&self.path))`, with no `with_depth`. The PR did update the Windows copies of `from_entry_os` (`:337-346`) and `from_path` (`:387-394`), so this one reads as an oversight rather than a choice.

Case: on Windows, `WalkBuilder::new(root).follow_links(true).build_parallel()`, a symlink at depth 2 whose target disappears after the entry is built (`from_path` with `link = true` sets `follow_link`, so `metadata_internal` stats again). `dent.metadata().unwrap_err().depth()` is `Some(2)` on Linux and macOS at HEAD and `None` on Windows. Fix: add `.with_depth(self.depth)` to the Windows `map_err` the same way as `:305`.

**2. Depth is now attached twice in `from_entry` and the Windows `from_entry_os`.**

Both sites already wrapped the error in `Error::WithDepth { depth, err: Box::new(err) }` at base, so `Error::depth()` already returned `Some(depth)` there. The diff adds an inner `.with_depth(depth)` without dropping the outer wrapper, so the error is now `WithDepth { WithPath { WithDepth { Io } } }`:

- `crates/ignore/src/walk.rs:331-332` (`from_entry`, `ent.file_type()`)
- `crates/ignore/src/walk.rs:344-345` (Windows `from_entry_os`, `ent.metadata()`)

Nothing a caller can observe through `depth()` changes at these two sites; only the nesting gets deeper. The base commit (`c10f151`, "ignore: always include depth in errors") warns that callers down-casting nested errors could break, and this adds a third layer for no gain. Either revert these two hunks, or keep the inner `with_depth` and delete the outer `Error::WithDepth { .. }` line so the shape matches the other sites in this diff and `Error::from_walkdir` (`crates/ignore/src/lib.rs:297-303`).

## Nit

**3. `Walkdir(ref x) => ...` in `DirEntryInner::metadata` (`crates/ignore/src/walk.rs:181-185`) hand-rolls what `Error::from_walkdir` (`crates/ignore/src/lib.rs:285`) already does.** `x.metadata()` returns a `walkdir::Error` that carries the entry's depth and path, and `from_walkdir` builds exactly `WithPath { WithDepth { Io } }` from it; `walk.rs:1130` converts walkdir errors this way already. `Walkdir(ref x) => x.metadata().map_err(Error::from_walkdir),` replaces the five lines.

**4. The PR text doesn't say which case was missing depth, or what changes for callers.** The concrete gap at base is the parallel walker: `DirEntryRaw::from_path` (followed symlinks, e.g. a dangling link with `follow_links(true)`), `metadata_internal`, and `path_equals` all returned errors with `depth() == None`, while the serial walker got depth through `from_walkdir` after `c10f151`. That's the #3453 use case, and saying so would let a reviewer check it in one read. The body should also carry the same down-casting caveat `c10f151` did, since `DirEntry::metadata()` errors change shape here. Smaller: the repo's subjects use `ignore: ...` (`git log`: "ignore: always include depth in errors"), not `feat[ignore]:`.

**5. No test pins any of this.** Nothing in `crates/ignore` asserts on `Error::depth()` (the only use is `walk.rs:1205`, which reads it). A test beside the existing walk tests that builds a dangling symlink at depth 1, walks with `follow_links(true)` through `build_parallel()`, and asserts the error's `depth() == Some(1)` fails on base and passes here; it would also have caught item 1 on the Windows CI job.

Lean: -6 lines possible (item 2 revert: -2; item 3: -4)
