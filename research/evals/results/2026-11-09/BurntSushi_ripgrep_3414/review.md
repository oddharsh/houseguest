Important: 2, Nit: 3, Pre-existing: 0

## Important

**1. Four new flags with no issue behind them.**
The PR adds `--base64`, `--no-base64`, `--base64url` and `--no-base64url` (480 lines across 6 files), and `pr-body.md` links no issue or discussion. `.github/ISSUE_TEMPLATE/feature_request.md` sends exactly one kind of feature straight to a PR: "If you're requesting the addition or change of default file types, please open a PR." Everything else goes through a feature request first, which asks you to "describe the behavior you want and the motivation." ripgrep carries every flag forever, so the questions belong there before the code: is this in scope for ripgrep at all, versus a `--pre` script, and does it need two alphabets (see Lean 3)?

**2. Nothing tests the `HiArgs` wiring, so breaking it fails no test.**
The unit tests in `crates/core/base64.rs` build their own matcher with `fixed_strings(true)` (`matches_every_alignment`, base64.rs:247), and `test_base64` / `test_base64url` in `crates/core/flags/defs.rs` only check parsing into `LowArgs`. No test runs `rg --base64`. Two regressions that pass the whole suite:
- `crates/core/flags/hiargs.rs:290`: change `fixed_strings,` back to `low.fixed_strings`. `rg --base64 '?'` then expands to literals that include `P+` and `P/`, the regex engine reads `P+` as "one or more P", and a line holding `Pizza` matches. With the PR as written it doesn't.
- `crates/core/flags/hiargs.rs:149-160`: drop the `match low.base64.alphabet()` block. `rg --base64 admin` then searches for plain `admin` and misses `a3ViZS1hZG1pbg==` (base64 of `kube-admin`).

Fix: two `rgtest!` cases in `tests/feature.rs` (or `tests/misc.rs`, which already tests `-F` end to end at line 176): `--base64 admin` finds a line with `a3ViZS1hZG1pbg==`, and `--base64 '?'` doesn't match `Pizza`.

## Nits

**1. "naturally free of duplicates" is false, and the test that guards it avoids the failing inputs.**
`crates/core/base64.rs:59-61` claims each `(offset, lead, trail)` tuple gives a distinct literal. Bytes with a 2-bit period (`0x00`, `0x55` `U`, `0xAA`, `0xFF`) make the three offset windows line up. By my port of `pattern_literals`, `b"U"` gives 48 literals with 40 distinct (`VU`, `VV`, `VW` repeat), and `b"UUU"` gives 129 with 113 distinct. `literals_are_unique` (base64.rs:211) passes only because `a`, `foo`, `hello` and `secret-token-1234` aren't periodic. Add `b"U"` to its inputs and it fails. Results stay correct, but `Patterns::from_low_args` dedups on purpose for speed (comment at hiargs.rs:1024-1034), and the expansion runs after that dedup. Either `sort` + `dedup` the result in `expand_patterns`, or delete the sentence and the test.

**2. The docs describe code that isn't there.**
- `defs.rs:364`, `:372` and `:443` say the pattern is "transformed into a regex", "the generated regex" and "the rewritten regex". The code emits fixed-string literals.
- `base64.rs:46-47` says the matcher will "skip regex parsing entirely." That's false whenever `-i` or `-S` is on: `is_fixed_strings` in `crates/regex/src/config.rs:106-108` returns false, so every literal (up to 264 per pattern) gets escaped and parsed.
- `defs.rs:367` pitches certificates. PEM wraps at 64 columns, and ripgrep searches line by line, so an encoding that straddles a line break is a silent miss. The man page should say so.

**3. `rg --base64 ''` matches nothing, while `rg -F ''` matches every line.**
The early return at `base64.rs:64-66` turns `""` into zero literals, and `matches_possible` (hiargs.rs:539) then reports no match is possible. The base64 encoding of the empty string is the empty string. Delete the early return and the `empty_query_returns_no_literals` test: the offset-0 pass then yields `""` and the flag agrees with `-F`.

## Lean

**1. `hiargs.rs:145-160` and `:290`: mutate `low` instead of threading a tuple.**
`HiArgs::from_low_args` already does this for `low.mode` ("We modify the mode in-place on `low` so that subsequent conversions see the correct mode," hiargs.rs:126-127):

```rust
let mut patterns = Patterns::from_low_args(&mut state, &mut low)?;
if let Some(alphabet) = low.base64.alphabet() {
    patterns.patterns = base64::expand_patterns(alphabet, patterns.patterns);
    low.fixed_strings = true;
}
```

That drops the tuple match and leaves line 290 untouched. About -8 lines.

**2. `Base64Mode` (`lowargs.rs:232-258`) is `Option<Alphabet>` spelled out by hand.**
`LowArgs` already models an off-or-one-of-two flag pair as `boundary: Option<BoundaryMode>` (lowargs.rs:42). `base64: Option<crate::base64::Alphabet>` deletes the enum and `alphabet()`, and the two `update` fns set `Some(..)` / `None`. About -25 lines.

**3. `--base64url` may not need to exist.**
The body says the alphabets only differ "when searching for text with many bits set." If `--base64` emitted the literals for both tables, the PR would lose the `Base64Url` flag and its test (defs.rs:415-476), its `FLAGS` entry, 2 zsh lines, the `Alphabet` enum, and `Base64Mode` would shrink to a `bool` like every other switch. The cost: up to 2x literals for queries whose encoding hits index 62 or 63, and no new misses. That's a design call, so it belongs in the issue from Important 1. About -100 lines, and it subsumes Lean 2.

**4. `base64.rs:70-73` and `:203-208`.**
The 3-line arithmetic comment exists only to justify the `with_capacity(264)` hint; `Vec::new()` does the job and both go. `aligned_encoding_is_a_literal` is covered by `matches_every_alignment`, which already feeds `foo` with an empty prefix and suffix. About -10 lines.

Lean: -115 lines possible (about -40 if `--base64url` stays)
