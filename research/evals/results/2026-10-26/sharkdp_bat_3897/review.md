Review of sharkdp/bat PR #3897, "fix: use last occurrence in combined short flags"

Verdict: I'd merge it after one test fix. The source change is 4 tokens (`position` to `rposition` in `src/bin/bat/app.rs`, lines 92-93 and 118-119), and I think it's correct. Clap applies `-p`'s `overrides_with("number"/"number-nonblank")` left to right inside a combined flag, so "last occurrence wins" is what clap already does, and the raw scan now agrees with it. CONTRIBUTING's changelog rule is met (the entry is under Bugfixes, in the right format, with the PR number). There's no AI policy. I found nothing duplicated and no intended behavior being reversed.

I couldn't run the tests: the sandbox blocked the build. Everything below comes from reading the code.

Findings, most important first:

1. **The `-pnp` assertion would pass without the fix** (`tests/integration_tests.rs`, the second `bat()` block in `repeated_combined_flags_use_last_number_or_plain_flag`).
   - Before the PR, `-pnp` gives n_pos=1 > p_pos=0, so `number_from_cli` is true and `loop_through` is false (app.rs:477-486).
   - That only swaps the SimplePrinter for the InteractivePrinter (controller.rs:192). Clap still resolves the style to plain, and colored output is off when piped. So both printers print the same `line 1\n...line 10\n`.
   - The body admits this ("`-pnp` already produces plain output"), yet still says "add regression coverage for all four combinations." Only 3 of the 4 assertions can fail on base: `-npn`, `-pbp` and `-bpb`.
   - Fix: delete the `-pnp` block (10 lines), or test something that actually differs between the two paths. Either way, drop "all four" from the body.

2. **Four cases are crammed into one test function, unlike the neighboring tests.**
   - The adjacent tests (`numbers_ignored_from_cli_when_followed_by_plain_in_loop_through_mode`, `numbers_honored_from_cli_when_preceeded_by_plain_in_loop_through_mode`, `line_numbers_from_cli_in_loop_through_mode`) each check one flag form.
   - With everything in one fn, an `-npn` failure hides whatever `-pbp` and `-bpb` would have reported.
   - Split it to match the file's pattern, one fn per flag form.

3. **The same bug class survives across separate arguments, and the body's framing hides that.**
   - The body says `-pbp` "should use plain output", but `bat -b -p empty_lines.txt | cat` still prints line numbers.
   - `number_nonblank_from_cli` is `any(arg == "-b")` (app.rs:110-113), and `style_components` checks `self.number_nonblank_from_cli` before plain (app.rs:648). Clap's `-p` override never gets a say.
   - This was already broken before the PR and doesn't block it. It should be stated as out of scope, though, rather than leaving readers to think "last occurrence wins" now holds generally.

4. **Minor: the body's Tests section lists two commands but no output.** That's not much to go on when the build couldn't be checked here.

Nothing in the body reads as instructions to the reviewer. Its prose is clean and specific.

Lean (contributor's lines only):
- The `-pnp` block in the new test can't catch a regression (finding 1). Delete it, -10 lines.
- The source diff has nothing to trim. `rposition` is std, and the change is the minimum. The n/b scan closures are near-copies, but they were copies before this PR, so merging them belongs in its own PR.

Lean: -10 lines possible

Relevant paths:
- /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/sharkdp_bat_3897/repo/src/bin/bat/app.rs
- /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/sharkdp_bat_3897/repo/tests/integration_tests.rs
- /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/sharkdp_bat_3897/repo/src/bin/bat/clap_app.rs
- /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/sharkdp_bat_3897/repo/src/controller.rs

Network: none
