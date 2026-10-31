Important: 0, Nit: 1, Pre-existing: 0
No blocking issues

I checked the parts that could go wrong and they hold:

- The flag propagates correctly. `add_child_path_with_found_ignore_files` copies it from the parent (`crates/ignore/src/dir.rs:453`), and each absolute parent ORs in its own matchers on top of what it inherited (`dir.rs:246`). A rule file several directories above an empty parent still sets it, and so does a cache hit, because the cached `IgnoreInner` for a path always has the same ancestry.
- Skipping the absolute-parent loop at `dir.rs:600` drops nothing else. That loop only writes the four `m_*` matches and `saw_git`. `saw_git` isn't read after the loop, `any_git` is computed over all parents before it (`dir.rs:565`), and the explicit and global matchers after it use the outer `path`, since the rewritten `path` is scoped to the `if let`.
- `Gitignore::is_empty` is `self.set.is_empty()` (`crates/ignore/src/gitignore.rs:171`), so a whitelist-only file (`!allowed`) still counts as rules. The first test covers that.
- Both tests would catch a regression. Reset the flag in `add_child_path_with_found_ignore_files`, use `=` instead of `|=`, or drop any one of the four matchers from the OR, and `absolute_parent_rules_through_empty_directories` fails: `td/a` is an empty absolute parent sitting between the rules and the root, and the loop covers all 4 file kinds. If someone moves the `any_git` computation inside the new guard, `absolute_parent_repository_without_rules` fails. Both tests use the same helpers (`tmpdir`, `mkdirp`, `wfile`) as `absolute_parent_matchers_are_cached_across_roots` beside them.

The stored flag is justified, since deriving it on each call would mean walking the parent chain, which is the cost this PR removes. I found nothing in `AI_POLICY.md` or `CONTRIBUTING.md` that this violates, and the body reads like a person wrote it.

## Nits

**The benchmark numbers are measured against a commit that isn't this diff's base.** The body says "On Linux x86-64 against `3fce3b5`". That's the `ignore-0.4.33` release, 9 commits behind this PR's base `b5611fc`. Between them sit `c5e744c` ("avoid scratch pools for empty matchers", which is itself an allocation change) and `b5611fc` ("reuse parent repository detection"). So "replay allocates or reallocates about half as often" may be partly `c5e744c`'s effect, not this one. Please rerun against `b5611fc`, or name the cases from the `#3554` bench suite (`fada8f9`) that produced the 13.4% and the 3.3% control slowdown, so I can rerun them. A line on why a cached ignored path gets slower would also help, since this diff only adds one bool check on that path.

I'd merge this as is. The nit only changes the description.
