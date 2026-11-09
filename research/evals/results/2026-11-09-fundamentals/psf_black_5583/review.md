Important: 1, Nit: 2, Pre-existing: 0

The code change is right. `\x` is the only one of the four escapes the regex handles that bytes literals recognize, so lowercasing it keeps the value. Skipping `\u`, `\U` and `\N{...}` when the prefix has a `b` is the whole fix. The test lines in `tests/data/cases/format_unicode_escape_seq.py` fail on base, because `assert_format` runs the equivalence check and `b"龜"` becomes `b"龜"`. They pass on HEAD. Crash fixes may land in stable style ("Exceptions are fixing crashes", `the_basics.html.txt`, Style Changes). A file previously formatted with `--fast` keeps its already-normalized bytes unchanged, so the stability policy holds.

## Important

**1. The repro in the description doesn't reproduce the bug** (pr-body.md, the first code block)

```python
x = b'{"name": "é"}'   # JSON stored as bytes
```

This line has a literal `é` and no `\u` escape. In a bytes literal it's a `SyntaxError` ("bytes can only contain ASCII literal characters"). Pasted into `example.py`, Black fails on it while parsing the source AST. That's a different error from the "not equivalent to the source" error quoted, and it fails the same way with or without this PR. The `--fast` output for `x` is also identical to the input, so it can't show "silently changes the values." The escape probably got decoded somewhere along the way, and the intended line was something like `b'{"name": "é"}'`. Put the real escape back, then make the `--fast` output show `é` for that line. A maintainer who pastes the snippet today gets an unrelated error and stops reading.

## Nit

**2. The scale claim has no command or output behind it.** "2,202 files, stable and preview ... The run reports no new failures" names no command, no base run, and no counts for base and HEAD. Give the command and the before and after failure counts in a collapsed block, or cut it to the one file that matters (`ruff/expression/bytes.py`).

**3. The footer repeats the disclosure.** The "AI disclosure:" sentence already says Claude Code wrote it. The emoji "Generated with Claude Code" line under it is tool boilerplate. Drop it.

Would merge once the repro in finding 1 is fixed.
