Important: 1, Nit: 1, Pre-existing: 0

The code fix is right and the test would catch a regression. The blocker is the repro in the description, which doesn't reproduce.

## Important

**1. The first example in the description is invalid Python, so it can't show the bug it's offered for** (`pr-body.md:8` and `pr-body.md:16`)

The example is `x = b'{"name": "é"}'` with a literal `é` (bytes `303 251` in the file, UTF-8). A bytes literal can only hold ASCII characters, so CPython rejects that line with `SyntaxError: bytes can only contain ASCII literal characters`. Black's safe mode then fails while parsing the source AST, a different error from the "not equivalent to the source" message the body quotes. Under `--fast` the regex has no `\u` to match, so the output line is identical to the input. That contradicts the "silently changes the values" comment right above it.

A maintainer who pastes this repro gets a different error for `x` and no change for `x` under `--fast`, which makes the rest of the description harder to trust. The source almost certainly read `b'{"name": "é"}'` before something decoded the escape. Fix: use `é` in the input block and `é` in the `--fast` output block, or drop `x` and keep `y = b"\N{bullet}"`, which does reproduce.

## Nit

**2. The `🤖 Generated with [Claude Code](https://claude.com/claude-code)` footer** (`pr-body.md`, last line). The AI disclosure line above it already says how the PR was made, and Black has no AI policy asking for more. The footer reads as tool boilerplate; drop it and keep the disclosure.

## Checked and fine

- `src/black/strings.py:344-346`: the guard covers the whole failure set. Of the four forms `UNICODE_ESCAPE_RE` matches, only `\x` is an escape in bytes; f-strings and t-strings can't take a `b` prefix, so the f-string caller at `strings.py:410` relying on the `False` default is correct. Raw bytes (`rb`, `Rb`, `bR`) still return early at `strings.py:368`.
- `tests/data/cases/format_unicode_escape_seq.py:15-16`: without the fix, `龜` and `\U0001F60E` get lowercased and `\N{ox}` uppercased, which changes the bytes value, so the case fails the output comparison and the AST check. `B"\xA3\N{ox}"` pins that `\x` normalization in bytes still happens with an uppercase prefix.
- Stable placement fits the stability policy's crash-fix exception in `the_basics.html`, and the `CHANGES.md` entry sits under "Stable style" with the PR number.

Would merge once the example is fixed.
