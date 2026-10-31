Important: 2, Nit: 0, Pre-existing: 0

I'd close this. The original text is correct, and the replacement is a pattern ripgrep can't parse.

## Important

**1. The edit swaps a valid regex assertion for an invalid pattern, and the PR rests on a misreading of the syntax.**

`crates/core/flags/defs.rs:7539` changes `\b{end-half}` to `{end-half}\b`.

- `\b{end-half}` is one token: a half word-boundary assertion that checks only the end side. regex-syntax parses it in `ast/parse.rs:1663` (`"end-half" => ast::AssertionKind::WordBoundaryEndHalf`), and its own test at `ast/parse.rs:4571` parses `\b{end-half}` (regex-syntax 0.8.8, the version in `Cargo.lock`). The `{end-half}` part names which boundary is meant. It isn't a separate thing that goes before `\b`.
- `{end-half}\b` doesn't parse. A leading `{` hits `parse_counted_repetition` (`ast/parse.rs:1103`), which returns `RepetitionMissing` when there's nothing before it. Appended to a pattern the way the doc describes, `foo{end-half}\b`, it fails as a counted repetition because `end-half` isn't a number. A user who copies the new man page text gets a regex error.
- The doc matches the code. `-w` is built in `crates/regex/src/config.rs:316-331` (`into_word`) as `Look::WordStartHalf*`, then the pattern, then `Look::WordEndHalf*`. That's exactly `\b{start-half}PATTERN\b{end-half}`, so there's no typo to fix.
- The body offers no source for "should be `{end-half}\b`," and the diff leaves line 7538's `\b{start-half}` alone, though by the body's own reading it would need the same treatment.

Fix: drop the change.

**2. The new line drops the roff backslash escaping its neighbors use.**

Raw-string doc text goes to the man page as roff, so a literal backslash is written `\\`. Line 7538 (`\fB\\b{start-half}\fP`) and line 4927 (`\fB\\b\fP and \fB\\B\fP`) do this. The added line `\fB\{end-half}\b\fP` (`crates/core/flags/defs.rs:7539`) uses single backslashes, so groff reads `\{` (the conditional-block escape) and `\b` (the bracket-building escape) as escape sequences, not text. The `rg --help` output fails too: `remove_roff` in `crates/core/flags/doc/help.rs:216-259` only collapses `\\` to `\`, so the help text would print `\{end-half}\b` with a stray backslash in front of the brace. This one is moot once finding 1 is resolved by dropping the change. I'm listing it because the line would render wrong even if its meaning were right.

Lean: -1 lines possible (the whole diff; the original line is correct).
