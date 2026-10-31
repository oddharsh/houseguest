Important: 0, Nit: 1, Pre-existing: 1
No blocking issues

The fix is the right size. `position` to `rposition` in both raw scans (`src/bin/bat/app.rs:92-93`, `:118-119`) makes the scan agree with clap, where `plain` overrides `number` and `number-nonblank` and the last one wins (`src/bin/bat/clap_app.rs:97-100`). I traced the 3 cases that matter on base. `-npn` and `-bpb` scan as false, so loop-through drops the numbers clap asked for. `-pbp` scans as true, and `forced_style_components` (`app.rs:648`) then turns line numbers on despite the trailing `-p`. The new assertions for all 3 fail on base and pass on HEAD. CHANGELOG entry matches the format in CONTRIBUTING.md. Would merge.

## Nits

**The `-pnp` block can't fail on base.** `tests/integration_tests.rs:226-234`. On base, `-pnp` scans as `number_from_cli = true`, which only switches to the interactive printer; clap's override still gives plain style, so `multiline.txt` prints the same bytes either way. The body says as much, but it also says "add regression coverage for all four combinations," and this one covers nothing. Either drop the block, or point it at an input where the two printers differ: `test_UTF-16LE.txt` comes out as raw UTF-16 bytes through `SimplePrinter` and as converted UTF-8 through `InteractivePrinter` (see the `utf16` test at `tests/integration_tests.rs:1948`, which needs `--decorations=always` to get the conversion).

## Pre-existing

**The raw scan reads values of short options as flags.** `src/bin/bat/app.rs:89` and `:115` treat every char of a `-xyz` argument as a flag, but `-l`, `-H`, `-m`, and `-r` take values (`clap_app.rs:113`, `:138`, `:398`, `:570`). So `bat -lbash script.sh | cat` finds a `b` with no `p`, sets `number_nonblank_from_cli`, and `forced_style_components` (`app.rs:648`) prints line numbers nobody asked for. `-lrb` does the same. Blame dates these lines to 061fb21, before the base, and this PR neither causes nor worsens it, so it belongs in its own issue.

Lean: -9 lines possible (the `-pnp` block, if dropped instead of retargeted)
