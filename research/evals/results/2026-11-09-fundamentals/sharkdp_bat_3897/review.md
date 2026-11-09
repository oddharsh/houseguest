Important: 1, Nit: 1, Pre-existing: 1

The core change is right for the four cases in the body: I traced `-npn`, `-pbp`, and `-bpb` through `number_from_cli` / `number_nonblank_from_cli`, `loop_through` (app.rs:477-486) and `forced_style_components` (app.rs:648), and all three print the wrong thing at `base` and the right thing at HEAD. One input class gets worse, though, and I'd want that fixed before merging.

## Important

**1. `rposition` now lets the value of an attached `-l` decide the result, so `-pn`/`-pb` followed by `-l<lang>` loses its line numbers.**

The scan at `src/bin/bat/app.rs:90-101` and `:116-124` treats every character after the leading `-` as a flag. Clap doesn't: `-l` (language), `-H`, `-m`, and `-r` take a value, and in a cluster the rest of the argument is that value. With `position()` the first `n`/`b`/`p` usually came from real flags, since flags come before the value. With `rposition()` the last one often comes from the language name.

Concrete inputs that were correct at `base` and are wrong at HEAD (piped, so `loop_through` decides):

- `bat -pnlperl file.pl | cat`: clap sees `-p -n -l perl`, so `number` wins and numbers should print (same as the existing `-pn` test at `tests/integration_tests.rs:206`). Base: first `n` (1) > first `p` (0), numbers print. HEAD: last `p` is the one in `perl` (3) > last `n` (1), so `number_from_cli` is false and `loop_through` drops the numbers.
- `bat -pblperl file.pl | cat`: same thing for `-b` at app.rs:118-121.
- `bat -pnlphp file.php | cat`: last `p` comes from `php`.

The same class was already wrong at `base` for other inputs (`bat -lbash x.sh | cat` matches `b` in `bash`, sets `number_nonblank_from_cli`, and forces `LineNumbers` through app.rs:648), so the fix covers both: stop collecting chars at the first value-taking short flag, e.g. `.chars().skip(1).take_while(|c| !matches!(c, 'l' | 'H' | 'm' | 'r'))` in both scans. A test for `-pnlperl` beside the new one would pin it.

## Nit

**2. The `-pnp` case in the new test passes at `base` too, so it guards nothing.**

`tests/integration_tests.rs:226-234`. The body says so itself ("`-pnp` already produces plain output through clap's option handling"). At `base`, `-pnp` sets `number_from_cli`, so `loop_through` is false, but clap's `plain` override still yields plain style and the printer writes the same bytes as loop-through for `multiline.txt`. The "wrong internal printing path" the body mentions isn't observable in this stdout. Either drop the case or pick an input where the two paths differ (I didn't find one quickly; tab width at app.rs:493 is the only candidate, and it's 0 vs passthrough for `-p` with no pager).

## Pre-existing

**3. The scan checks each argument on its own, so "last occurrence wins" still fails across separate arguments.**

`src/bin/bat/app.rs:110-114` returns true the moment any argument is `-b`. So `bat -b -p file | cat` prints line numbers, while `bat -bp file | cat` prints plain (the existing test at `tests/integration_tests.rs:296`). Clap's `overrides_with` gives plain in both. Not this PR's to fix, and the CHANGELOG line correctly scopes the change to combined arguments. If someone takes it on later, `config()` already resolves last-wins from clap itself with `indices_of(...).and_then(Iterator::max)` (app.rs:316-325); the catch is that the raw scan exists to tell CLI args from config-file args, so the indices would need comparing against the number of config/env args prepended in `matches()` (app.rs:280-293).

Not merging yet. With finding 1 fixed (a one-line `take_while` in each scan plus a test), I would merge.
