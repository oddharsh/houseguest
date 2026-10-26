**Verdict:** request changes, on the body only. The code is correct and small. I'd merge it once #3556 lands and the numbers are re-measured against this PR's real base.

**Findings, most likely blocker first**

1. **The benchmark baseline doesn't isolate this diff.** The body says "against `3fce3b5`". That's the `ignore-0.4.33` tag, 8 commits behind this PR's base (`git log 3fce3b5..base`).
   - Those 8 commits include `c5e744c` ("avoid scratch pools for empty matchers", PR #3555) and `b5611fc` ("reuse parent repository detection", PR #3556).
   - Both are performance changes on the same `Ignore` matching path, and neither carries a merged `(#NNNN)` suffix the way `fada8f9 (#3554)` does. So they look like unmerged PRs this one is stacked on.
   - The "13.4%" and "about half as often" figures therefore measure 3 commits together. Re-run against `b5611fc` and report that delta.

2. **The stacking isn't disclosed.** The hunk at `crates/ignore/src/dir.rs:245` has the context line "`add_child_path` already checked repository markers when needed." That comment comes from `b5611fc`. Without #3556 the hunk has no matching context, so it won't apply to master. The body should say "depends on #3556 (and #3555)".

3. **The benchmark claims can't be checked against the repo's own harness.**
   - `crates/ignore/benches/README.md` names the cases (`incremental_warm`, `incremental_ignored_parent`, ...) and gives the command (`cargo +nightly bench -p ignore --bench workloads incremental`). The body uses prose names instead.
   - "Replay" appears nowhere in `crates/ignore/benches/README.md` or `workloads.rs`, so I can't tell which measurement "allocates or reallocates about half as often" refers to.
   - The body reports the "cached ignored-path control is 3.3% slower" without explaining it. On that path the diff adds one bool load and branch (`dir.rs:600`). Either 3.3% is noise, or something else changed.
   - If it's noise, the "1–4%" walk improvement sits inside that noise band too. Name the bench cases, give the command, and add variance or the run count.

4. **Minor:** "replay" is undefined jargon in a 2-paragraph body. Use the bench name.

**Checked and holding up (not findings)**

- **Correctness of the skip.** Skipping the absolute-parent block in `matched_ignore` also skips the `saw_git` updates for absolute parents. Nothing reads `saw_git` after that block: `m_global` uses `any_git`, and the explicit-ignores loop uses the original `path`. `any_git` still scans every parent, including absolute ones (`dir.rs:565-566`), and that's what the body's "repository boundaries still affect Git ignore rules" sentence means. `absolute_parent_repository_without_rules` pins it.
- **The `compiled` cache.** Prebuilt entries carry their own `has_absolute_parent_rules`. New entries inherit it through `add_child_path` (`dir.rs:453`) and OR in their own matchers (`dir.rs:246-250`). Cache hits and misses agree.
- **The tests catch regressions.** I reasoned these through by hand because I couldn't run the suite (below).
  - Dropping the propagation at line 453 fails the `c/d` assertions.
  - Using `=` in place of `|=` fails the test, because `a` and `a/b` are empty.
  - Dropping any one of the four `is_empty` terms fails that file's loop iteration.
  - The existing `absolute_parent` test only covers `.gitignore` in the immediate parent, so this is new coverage.
- **AI policy.** The body is 2 short, specific paragraphs, identical to the commit message. Nothing reads as machine-written or violates `AI_POLICY.md`.
- **No behavior change** to anything the project chose on purpose. The change is a pure fast path.

**Lean**

Nothing to cut.
- No existing helper checks "any per-directory matcher is non-empty". `has_any_ignore_rules` (`dir.rs:475`) checks options, a different question.
- The per-inner field is needed because children have to inherit the flag.
- `opts.parents` at line 600 can't be dropped. `add_parents` still builds matchers when `parents` is off but the git options are on (`dir.rs:199-206`).
- Both tests earn their lines.

I couldn't run the new tests: the sandbox denied `cargo test --offline`. The test conclusions above come from reading the code.

Files: `/private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/BurntSushi_ripgrep_3557/repo/crates/ignore/src/dir.rs`, `/private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/BurntSushi_ripgrep_3557/repo/crates/ignore/benches/README.md`

Network: none
