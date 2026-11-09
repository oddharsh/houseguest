Important: 1, Nit: 0, Pre-existing: 0

## Important

**1. The "fix" replaces correct regex syntax with wrong syntax, and the old text documents what the code actually does.** `crates/core/flags/defs.rs:7539`

`\b{end-half}` isn't a typo. It's the regex crate's half word boundary assertion (`\b{start}`, `\b{end}`, `\b{start-half}`, `\b{end-half}`), the same family as `\b{start-half}` on the line above, which the PR leaves alone. It means "not followed by a word character," which is exactly what `-w` builds:

- `crates/regex/src/config.rs:316-330` (`into_word`) wraps the HIR in `Look::WordStartHalf*` and `Look::WordEndHalf*`. Those are the HIR nodes `\b{start-half}` and `\b{end-half}` parse to.
- The PCRE2 path does the same by hand: `crates/pcre2/src/matcher.rs:73` builds `(?<!\w)(?:pat)(?!\w)`.

The replacement says the opposite of what `-w` does. `pat\b` is a full word boundary, and both `word()` builders document (`crates/regex/src/matcher.rs:336-342`, `crates/pcre2/src/matcher.rs:165-175`) and test (`crates/regex/src/matcher.rs:560-569`) that `-w` is deliberately different from `\b`: `rg -w -- -2` matches `-2` in `abc -2 foo`, while `\b-2\b` doesn't. A user who follows the new man page and writes `-2\b` by hand gets a different result from `-w`. `{end-half}\b` also isn't a usable regex at all: the leading `{end-half}` is either a literal or a repetition error depending on position, so "surround every pattern with" it has no meaning.

The new line also breaks the escaping the line above uses. `doc_long` is roff, so a literal backslash is written `\\` (see `\fB\\b{start-half}\fP` on line 7538). The new `\fB\{end-half}\b\fP` drops the doubling, so in the man page `\{` and `\b` are roff escapes (conditional-block open and bracket-building), not text. In `rg --help`, `crates/core/flags/doc/help.rs:254-258` only unescapes `\fB`, `\fI`, `\fP`, `\-`, and `\\`, so the help output prints `\{end-half}\b` verbatim.

The body's only evidence is "seems incorrect" and "seems like a typo." It doesn't run `rg -w` against `\b{end-half}` or `pat\b` on any input, which would have shown the original was right.

Fix: close the PR; the current text is correct. If the docs confused the reader, the useful change is a sentence after line 7539 pointing at the regex crate's `\b{start-half}`/`\b{end-half}` syntax, in its own PR.
