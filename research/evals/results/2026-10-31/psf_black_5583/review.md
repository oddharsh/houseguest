Important: 1, Nit: 0, Pre-existing: 0

The code change is right and small. One problem, in the description only.

## Important

**1. The first repro in the body can't produce the error it claims (description claim the proof doesn't support).**

`pr-body.md` lines 8 and 16 show `x = b'{"name": "é"}'`. That literal holds a raw `é` (bytes `303 251` in the file), and Python rejects it outright: a bytes literal may contain only ASCII characters, so `ast.parse` raises `SyntaxError: bytes can only contain ASCII literal characters`. Black would report it can't parse the file, which is a different failure from the "not equivalent to the source" error the body quotes.

The `--fast` block makes it worse. It's labelled "silently changes the values," yet line 16 prints that same line unchanged. Only the `y = b"\N{bullet}"` -> `b"\N{BULLET}"` line shows the bug.

My guess is the example started as an escaped JSON string and the escape got rendered away. Even then, `b'{"name": "é"}'` is already lowercase and wouldn't change; it needs uppercase hex, such as `b'{"name": "é"}'`, to trigger the normalization. Swap in an input that actually reproduces it (or drop the first line and keep the `\N{bullet}` one), and paste the real output from `black` and `black --fast` on base.

Fix: edit the body only. No code change needed.

## What I checked and found fine

- `src/black/strings.py:344` skips only `\u`, `\U` and `\N{}` for bytes and still lowercases `\x`, which is an escape in bytes. That matches Python's bytes escape rules.
- `is_bytes` reaches every bytes path. `visit_STRING` (`src/black/linegen.py:570`) and string leaves inside f-string replacement fields (`src/black/strings.py:382`) both go through `normalize_unicode_escape_sequences`, which now passes it. The f-string middle caller at `src/black/strings.py:410` keeps the `False` default, which is correct because no `bf`/`bt` prefix exists.
- The new cases in `tests/data/cases/format_unicode_escape_seq.py` fail without the fix: `龜` would become `龜` and `\N{ox}` would become `\N{OX}`. The `B"..."` case also covers the `prefix.lower()` check.
- The `CHANGES.md` entry sits under "Stable style" with the PR number. That's allowed for a crash fix under the stability policy (`docs/the_black_code_style/index.md`, "We may still fix bugs where _Black_ crashes").
- No AI policy found (`policy.md`); the disclosure line is fine.

Once the repro is corrected, I'd merge.
