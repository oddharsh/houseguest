Important: 1, Nit: 3, Pre-existing: 0

This is a sensible follow-up to c10f151 ("ignore: always include depth in errors"), and the parallel walker's broken-symlink path (`DirEntryRaw::from_path` at `walk.rs:1759`) now reports a depth where it used to return `None`. One platform got left behind, though.

## Important

**1. The Windows twin of a changed function still drops the depth.**

The diff adds depth to the `#[cfg(not(windows))]` `DirEntryRaw::metadata_internal` (`crates/ignore/src/walk.rs:298-306`) but leaves the `#[cfg(windows)]` one right above it untouched:

```
// crates/ignore/src/walk.rs:295
.map_err(|err| Error::Io(io::Error::from(err)).with_path(&self.path))
```

Case: on Windows, a parallel walk with `follow_links(true)` reaches a symlink whose target is deleted after the entry is built. `DirEntry::metadata()` hits `fs::metadata(&self.path)`, fails, and `err.depth()` returns `None`; the same walk on Linux returns `Some(depth)`. Every other pair of cfg twins in this diff got the same change (both `from_path` impls at `:394` and `:413`), so this one reads as missed. Fix: same line as the unix version, `Error::Io(err).with_depth(self.depth).with_path(&self.path)` (and drop the identity `io::Error::from` like you did on unix).

## Nits

**2. `from_entry` and the Windows `from_entry_os` now attach the depth twice.**

At `crates/ignore/src/walk.rs:330-333` and `:343-346` the closure already wrapped the error in `Error::WithDepth { depth, .. }`. The diff adds `.with_depth(depth)` inside it, so the error is now `WithDepth{d, WithPath{p, WithDepth{d, Io}}}`. `depth()` returns the same value, so nothing observable through the accessors changes, but `Error`'s variants are public and c10f151's own message warns that callers may match on the nesting. Pick one: revert these two hunks, or keep your inner form and delete the outer wrapper:

```rust
let ty = ent.file_type().map_err(|err| {
    Error::Io(err).with_depth(depth).with_path(ent.path())
})?;
```

**3. The walkdir arm rebuilds `Error::from_walkdir` by hand.**

`walkdir::DirEntry::metadata()` returns a `walkdir::Error` that already carries the entry's depth and path (walkdir 2.5.0 `Error::from_entry`). `Error::from_walkdir` (`crates/ignore/src/lib.rs:285`, already used at `walk.rs:1130`) builds exactly the `WithPath{path, WithDepth{depth, Io}}` shape that `walk.rs:181-185` now assembles manually. Five lines become one:

```rust
Walkdir(ref x) => x.metadata().map_err(Error::from_walkdir),
```

**4. No test pins the new depth.** The `walk.rs` test module already has a unix `symlink` helper (`:2073`) and symlink tests (`:2376`, `:2414`). A broken symlink at depth 1, walked in parallel with `follow_links(true)`, asserting `err.depth() == Some(1)`, fails on base and passes here. Not required by anything written, and c10f151 shipped without one, so take it or leave it.

Would merge once the Windows `metadata_internal` matches its unix twin.

Lean: -6 lines possible (walkdir arm via `from_walkdir`: -4; dropping the outer `WithDepth` wrapper in the 2 `from_entry*` closures: -1 each)
