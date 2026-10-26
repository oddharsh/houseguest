Verdict: close. The PR commits its own AI prompt and a 210-line generated description. It adds a feature with no issue behind it. The headline case (unreadable directories during the walk) doesn't work, and the new tests race on a global.

Repo: /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/BurntSushi_ripgrep_3239/repo

## Close / request-changes reasons, most likely first

1. **AI scaffolding committed to the repo root.** `purpose.txt` (15 lines) is the prompt itself: "I want to: Add a new CLI flag called --suppress-error ... Files to modify: crates/cli/src/args.rs ... crates/searcher/src/searcher/glue.rs ... Add tests". `pullrequest.txt` (210 lines) is a generated PR description, and it doesn't match the drafted body. ripgrep has no AI policy (policy.md: none found), so this isn't a rule violation. It's still the fastest close signal there is: two stray files in the root of someone else's tree. The prompt also names files the diff never touches, which tells me nobody re-read the result.

2. **Feature PR with no issue.** `.github/ISSUE_TEMPLATE/feature_request.md` routes feature requests through an issue. Only default file-type changes are told to "please open a PR". This PR adds a user-facing flag with 2 modes, a man page entry and a completion, and links nothing. The motivation (CI, monorepos, locked-down dirs) is generic, with no user report and no example command.

3. **It doesn't cover the case it claims.** The body says the flag handles permission errors "during file traversal and searching". `handle_search_error` is only wired into the `searcher.search(&haystack)` error arms in `search` and `search_parallel` (crates/core/main.rs). Errors from walking into an unreadable directory come through `HaystackBuilder::build_from_result` instead (crates/core/haystack.rs:38, `err_message!("{err}")`), and that path is untouched. The same goes for `--files` mode, which uses that builder too.
   - Concrete case: `mkdir -p d/locked && chmod 000 d/locked && rg --suppress-error=nopermission foo d` still prints `rg: d/locked: Permission denied (os error 13)` and exits 2.
   - That's the most common way people hit permission errors with rg. The error there is an `ignore::Error`, not an `io::Error`, so the `err.kind()` check couldn't be reused as-is anyway.
   - Only unreadable *files* found by the walk, or given as paths, get suppressed.

4. **`nopermission` reverses a deliberate exit-status decision.** CHANGELOG.md:723-729, under BREAKING CHANGES, moved ripgrep to GNU grep semantics on purpose: "if a non-fatal error occurs during a search, then ripgrep will now always emit a `2` exit status code, regardless of whether a match is found or not". `PermissionSkip` carves out one error kind from that rule, and neither body mentions the decision or argues against it.

5. **`permission` mode mostly duplicates `-s/--no-messages`.** `--no-messages` already "suppresses some error messages. Specifically, messages related to the failed opening and reading of files" (defs.rs, NoMessages doc_long), and `err_message!` still calls `set_errored()` under it (messages.rs:82-86), so the exit code stays 2. `--suppress-error=permission` is that same behavior limited to one `ErrorKind`. Users can already get it with `-s` or `2>/dev/null`, and the body doesn't explain why those fall short.

6. **The value names are inverted against ripgrep's naming.** In this CLI, `no` means negation (`--no-messages`, `--no-ignore`). Here both values suppress, and `nopermission` means "suppress harder and change the exit code". The doc text even says "The only supported value for now is 'permission' related behavior" while listing 2 values. "For now" is for-later language for future error kinds nobody asked for.

7. **The unit tests race on a process-global flag.** `cargo test` runs tests in parallel threads by default. All 4 tests in `main.rs mod tests` reset and assert the same `static ERRORED` (messages.rs:25).
   - Race: `..._permission_skip_does_not_set_errored` calls `reset_errored()`. Then `..._permission_silence_sets_errored` (or the `NotFound` test) calls `set_errored()` on another thread. Then the skip test's `assert!(!errored())` fails.
   - The tests are also too weak. None of them checks whether the message gets printed, and that's half the feature. Item 3 slipped through because they call the helper directly instead of running `rg`.
   - ripgrep tests CLI behavior end to end in `tests/` (`rgtest!` in tests/feature.rs, tests/regression.rs). One unix-only integration test with a `chmod 000` dir and file would have caught item 3.
   - I couldn't run `cargo test` (the sandbox blocked the build), so the race is from reading the code.

8. **It doesn't follow the codebase's ordering.**
   - crates/core/flags/defs.rs keeps flag definitions alphabetical (`/// -A/--after-context` at line 216, then `--auto-hybrid-regex`, `-B`, `--binary`...). The PR puts `SuppressError` and its test above `AfterContext` at line 155. They belong between `StopOnNonmatch` and `Text`, where the `FLAGS` entry already sits.
   - `HiArgs` fields are alphabetical (crates/core/flags/hiargs.rs:37-106), and `suppress_error` was appended after `with_filename`.
   - In rg.zsh, every choice flag lists its values (`--engine=...:when:(( default\:... ))` at line 83). The new entry ends in a bare `:kind` with no choices. It also sits inside the `'(messages)'` exclusion group, so completion treats it as mutually exclusive with `--no-messages`/`--messages`, and the code doesn't.

9. **The body overclaims and reads as generated.**
   - "Existing tests pass" comes with no command output. `pullrequest.txt` claims `cd crates/core && cargo test --tests` passed, "regression, feature, JSON, multiline". Those integration tests live in the top-level `tests/` directory, so that claim doesn't hold together either.
   - The pullrequest.txt line "Catches invalid values via an error" describes a check `test_suppress_error` doesn't contain; it never passes an invalid value.
   - The body has a bullet list with its section header missing ("- Added `handle_search_error()` helper ..." sits orphaned under the args heading), plus a stray "the Default behavior".
   - The only commit, 1f0e884, is titled "Fix zsh completions and formatting for --suppress-error", but it contains the whole feature.

## Lean pass (contributor's lines only)

- **Rung 1, not needed:** delete `purpose.txt` and `pullrequest.txt`. That's -225 lines.
- **Rung 1, not needed:** drop `PermissionSilence`. It's `-s` scoped to one error kind (item 5), and no issue asked for it. Dropping it collapses the enum, the `Option`, the `doc_choices` and the match arms in `update`. A single switch would cover the remaining mode, if a maintainer even wants it (item 4). That saves roughly 15 lines across defs.rs, lowargs.rs and main.rs.
- **Rung 5:** in `handle_search_error` (main.rs, 26 lines), the `handled` flag and nested `if let`/`match` can become one early return before the existing `err_message!`, about 4 lines total:

```rust
if err.kind() == PermissionDenied && suppress.is_some() {
    if suppress == Some(PermissionSilence) { set_errored(); }
    return;
}
```

That's about -15. With a single mode it shrinks to one `if` guarding the existing `err_message!`, and the helper can go entirely.
- **Rung 6, replace:** drop the 4 racy unit tests (63 lines) and the test-only `reset_errored` in messages.rs (5 lines). Add one unix-only `rgtest!` in tests/feature.rs instead. That's -68, offset by about 15.
- **Accessor:** `HiArgs::suppress_error()` can stay, since neighbors use the same accessor pattern, but it moves with the field into alphabetical position.

Fixing item 3 means touching `HaystackBuilder::build_from_result`, which handles `ignore::Error`, so the real fix adds some lines back there.

Lean: -300 lines possible

Network: none
