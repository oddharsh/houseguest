Important: 2, Nit: 3, Pre-existing: 0

## Important

**1. The feature doesn't need to live in ripgrep: `-F -f -` already does the search, and a wrapper can generate the patterns.**

Most of the 480 added lines do one thing: they turn each pattern into a list of literal strings, then hand that list to the fixed-strings path. ripgrep already takes a list of literals from outside. `crates/core/flags/defs.rs:2155` documents it: "When PATTERNFILE is `-`, then stdin will be read for the patterns." So `b64-literals admin | rg -F -f -` gives the same matches as `rg --base64 admin`, using a 30-line script built from the `pattern_literals` loop in `crates/core/base64.rs:64`. Your Go prototype already does that. Two new switches plus two negations, a new module, and a new `LowArgs` field are a permanent cost to ripgrep's flag surface, its man page, and its completions (`crates/core/flags/complete/rg.zsh:48-52`), all for a transform that sits entirely in front of the matcher. Nothing in the repo asked for it either: no issue is linked, and `.github/ISSUE_TEMPLATE/feature_request.md` is where a new flag usually gets argued first. I don't see this fitting ripgrep; a wrapper script is the place for it.

**2. No test exercises the `--base64` ⇒ `-F` wiring, so a regression there ships silently.**

The one behavior that makes the flags correct is in `crates/core/flags/hiargs.rs:149-160` (the forced `true`) and `hiargs.rs:290`. No test goes through that path:

- `matches_every_alignment` (`crates/core/base64.rs:247`) builds its own matcher with `.fixed_strings(true)`, so it passes whether or not hiargs sets it.
- `test_base64` / `test_base64url` (`defs.rs:398`, `defs.rs:462`) only check `LowArgs.base64`.

Concrete case: `"?"` (0x3F) at offset 0 expands to literals that include `P+`. If `hiargs.rs:158` regresses to `low.fixed_strings`, `rg --base64 '?'` compiles `P+` as "one or more P" and matches every line containing a `P`, and every test in this PR still passes. New flags in this repo get an end-to-end `rgtest!` in `tests/feature.rs`. One that searches a file containing `base64("x?y")` with `--base64 '?'`, plus a line with a bare `P` that must not match, would catch it.

## Nits

**3. The man page claims more than the code does, and leaves out the limit the body admits.**

- `defs.rs:364`, `defs.rs:372` and `defs.rs:443` call the result "a regex" and "the rewritten regex". The comment at `crates/core/base64.rs:46-47` says the literals "skip regex parsing entirely". Both are false whenever `-i` or `-S` is set (including from a config file): `crates/regex/src/config.rs:106` sends the patterns through escape-and-parse in that case.
- `defs.rs:367` sells the flag for "certificates". PEM wraps base64 at 64 columns and MIME at 76, so a literal that straddles a line break never matches without `-U`. The doc says a match is found "regardless of where the literal sits".
- The body says queries of 2 bytes or fewer produce many false positives (for example, `rg --base64 a` searches for 2-char strings like `YQ`). The man page, which is what users read, doesn't mention it.

**4. Flags that `--base64` can't honor are accepted and then quietly break the search.**

- `-x` wraps each fragment in a whole-line match, so `rg --base64 -x admin` can match only a line that is exactly one fragment.
- `-w` puts `\b` around fragments that sit inside an alphanumeric run, so it nearly never matches.
- `-i` from a config file makes the search case-insensitive over base64 text.
- `rg --base64 ''` exits 1 without searching, because `expand_patterns` drops the empty pattern and `matches_possible` (`hiargs.rs:538`) then sees no patterns. Plain `rg -F ''` matches every line, as `defs.rs:2150` documents for empty patterns.

The doc mentions only `-i` and `-w`, as "usually not meaningful".

**5. Lines that read as machine-written.**

- Em dashes in doc comments at `crates/core/base64.rs:26` and `:28`.
- Use-case lists that read like ad copy: "JWTs, JSON payloads, certificates or environment dumps" (`defs.rs:367`), and "JSON Web Tokens (JWTs), OIDC ID tokens, signed URLs, S3 pre-signed requests" (`defs.rs:439-440`).
- `defs.rs:365` runs to 108 columns. Every other `doc_long` in the file wraps at 79.

## Lean

- **Two enums for one choice.** `Base64Mode` (`lowargs.rs:232-258`) is `Alphabet` (`base64.rs:24-31`) plus `Off`, glued together by `alphabet()`. Store `pub(crate) base64: Option<base64::Alphabet>`, the same way `lowargs.rs:42` stores `boundary: Option<BoundaryMode>`. The flags' `update` then becomes `args.base64 = v.unwrap_switch().then_some(Alphabet::Standard)`. About -30 lines.
- **Tuple rebinding where the file mutates `low` in place.** `hiargs.rs:125` says "We modify the mode in-place on `low` so that subsequent conversions see the correct mode." Follow it: make `patterns` mutable, then `if let Some(a) = low.base64 { patterns.patterns = base64::expand_patterns(a, patterns.patterns); low.fixed_strings = true; }`. The change at `hiargs.rs:290` then goes away. About -8 lines.
- **Unit tests that `matches_every_alignment` and `encode_url_safe_swaps_chars` already cover:** `empty_query_returns_no_literals` (`base64.rs:197`), `aligned_encoding_is_a_literal` (`:203`) and `url_safe_literals_have_no_standard_only_chars` (`:233`). About -25 lines.

Wouldn't merge. Finding 1 is the reason; 2 through 5 only matter if it stays.

Lean: -63 lines possible (-480 if it moves to a wrapper, per finding 1)
