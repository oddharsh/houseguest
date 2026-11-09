Important: 2, Nit: 0, Pre-existing: 0

I'd close this. The doc it edits is already correct, and the replacement text breaks both the man page and `--help`.

## Important

**1. The fix rests on a misreading of regex syntax; the original text matches the code.** `crates/core/flags/defs.rs:7539`

`\b{end-half}` is one assertion in the regex crate's syntax (the "end half" word boundary), the counterpart of `\b{start-half}`. It's no misplaced `\b`. "Surrounding every pattern with" already says it goes after the pattern. That's exactly what `-w` builds: `into_word` in `crates/regex/src/config.rs:316-331` wraps the HIR in `hir::Look::WordStartHalfUnicode`/`WordStartHalfAscii` before and `hir::Look::WordEndHalfUnicode`/`WordEndHalfAscii` after. Those `Look` variants are what `\b{start-half}` and `\b{end-half}` parse to. The new text `\{end-half}\b` names no assertion at all. Read as a regex, it's a literal `{end-half}` followed by a full `\b`, which isn't what `-w` does.

The body's claim ("This seems like a typo or simple mistake") has no support beyond the reading above. The man output it quotes, `\b{start-half} and \b{end-half}`, is the correct rendering.

**2. The new line drops the roff escaping the line above uses, so both renderers break.** `crates/core/flags/defs.rs:7539`

Line 7538 writes a literal backslash as `\\b` because `doc_long` is roff source. Line 7539 now has a bare `\{` and `\b`, which are roff escapes. Two instances on that line:

- Man page: rendering the snippet with mandoc gives `ERROR: incomplete escape sequence: \b\fP.`, and the sentence comes out as "surrounding every pattern with \b{start-half} and end-half}". The `\{` gets eaten, and the `\fP` that closes the bold is swallowed by `\b`.
- `rg --help`: `remove_roff` in `crates/core/flags/doc/help.rs:216-259` only rewrites `\\` to `\`, so the bare escapes pass through as `\{end-half}\b`. That makes the two renderers disagree, and neither one says `\b{end-half}`.

## Lean

The PR's only changed line shouldn't exist (ladder rung 1): the original sentence is right. Closing it is the fix.

Lean: -1 lines possible
