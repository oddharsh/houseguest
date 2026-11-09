Important: 0, Nit: 1, Pre-existing: 2
No blocking issues

The fix is the right size. Clap already resolves `-npn`, `-pbp`, and `-bpb` with last-one-wins through `overrides_with` (`src/bin/bat/clap_app.rs:97-100`), and the raw scan at `src/bin/bat/app.rs:82-127` disagreed with it because `position` found the first `n`/`b`/`p`. Switching to `rposition` makes the scan agree with clap within one argument. I traced three of the four new cases against `base`:

- `-npn`: base scan sees `n`=0, `p`=1, so `number_from_cli` is false and `loop_through` (`app.rs:477-486`) drops the numbers clap asked for. Fails on base, passes on HEAD.
- `-pbp`: base sees `b`=1 > `p`=0, so `number_nonblank_from_cli` is true and `forced_style_components` (`app.rs:648`) forces line numbers past the plain clap kept. Fails on base, passes on HEAD.
- `-bpb`: base sees `b`=0 < `p`=1, so loop-through drops the numbers clap kept. Fails on base, passes on HEAD.

CHANGELOG entry matches the format in `CONTRIBUTING.md` ("- Short description of what has been changed, see #123 (@user)"). No AI policy to check against.

## Nit

**The `-pnp` case can't fail.** `tests/integration_tests.rs:226-234` asserts plain output, but base already prints plain output for `-pnp`: clap's `plain` overrides `number`, and with piped output and `--decorations=auto` the printer path and the loop-through path emit the same bytes for `multiline.txt`. The body says the bug here is that "the raw scan still selects the wrong internal printing path," and this assertion doesn't observe the path. Either drop the block or keep it knowing it documents intent rather than guarding the fix.

## Pre-existing

**Last-one-wins stops at the argument boundary.** Both scans run inside `wild::args_os().any(...)` (`app.rs:82`, `app.rs:110`), so each argument is judged alone and a standalone `-b` returns true no matter what follows it. `bat -b -p empty_lines.txt` (or `bat -pb -p ...`) prints line numbers: clap lets the later `-p` override `number-nonblank`, but `number_nonblank_from_cli` is true and `app.rs:648` forces `LineNumbers`. After this PR `-pbp` and `-b -p` disagree, which is the same bug one space apart. Worth a follow-up that folds over all args in order rather than `any`; not this PR's job.

**The scan reads values of short options as flags.** `-l` takes a value (`clap_app.rs:111-116`), and clap accepts it attached. `bat -lbash script.sh` gives chars `l,b,a,s,h`, so `b` with no `p` sets `number_nonblank_from_cli`, and `app.rs:648` prints the file with line numbers nobody asked for. `-lnginx` or `-lpython` (ends in `n`) set `number_from_cli` the same way. `rposition` doesn't change any of these outcomes.

Would merge.

Lean: -10 lines possible
