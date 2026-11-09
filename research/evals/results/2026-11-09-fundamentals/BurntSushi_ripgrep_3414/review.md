Important: 2, Nit: 4, Pre-existing: 0

## Important

**1. Two new flags for something `-F -f` already does, with no issue behind them (lean rung 1: does it need to exist?)**

The whole feature reduces to "generate a list of literals, then search them as fixed strings." `crates/core/flags/hiargs.rs:149-160` does exactly that: it swaps the patterns for `base64::expand_patterns(...)` and forces `fixed_strings`. ripgrep already has that path. Write the output of `pattern_literals(alphabet, b"admin")` one per line to `lits.txt` and `rg -F -f lits.txt` gives the same matches as `rg --base64 admin`, since `grep::cli::patterns_from_path` (used at `hiargs.rs:1057`) reads one pattern per line. A 30-line script outside ripgrep covers it.

What this PR adds instead is 2 permanent flags (plus 2 `--no-` forms, man page text, completions in `crates/core/flags/complete/rg.zsh:48-52`) and a 284-line module in core. The feature-request template (`.github/ISSUE_TEMPLATE/feature_request.md`) is where a new flag gets argued first, and the body links no issue. I'd want that discussion, and an answer to "why not a script feeding `-F -f`," before reviewing the code below in detail. If it does go in, one flag with a value (`--base64=standard|url`) is worth weighing against two that override each other.

**2. Nothing tests the wiring that makes the flag work; reverting it passes every test**

The base64 tests build their own matcher (`crates/core/base64.rs:247-283`, `RegexMatcherBuilder::new().fixed_strings(true)`), and `test_base64` / `test_base64url` in `crates/core/flags/defs.rs` only check `LowArgs.base64`. No test runs `rg --base64`. So the two lines that actually turn the flag on are unpinned:

- `crates/core/flags/hiargs.rs:158` (the `true` that implies `-F`). Change it to `low.fixed_strings` and every test still passes, yet `rg --base64 '~'` breaks. At offset 2 the query `~` (0x7E) encodes to literals like `9+` (lead bits `1111` give `9`, the low 6 bits `111110` give `+`). Without `-F`, `9+` is parsed as the regex "one or more 9s", so it matches `99` and misses the real `9+`.
- `crates/core/flags/hiargs.rs:152-156` (the expansion itself). Drop it and `rg --base64 admin` silently searches for plain `admin`; no test notices.

ripgrep pins flags end to end in `tests/feature.rs` with `rgtest!` (for example `f1842_field_context_separator` at `tests/feature.rs:1005`). One test there that searches a file holding `AwwKa3ViZS1hZG1pbjCC` with `--base64 admin` and asserts the exact output line, plus one with a query whose literals contain `+` (`~` works), would catch both.

## Nits

**3. The "no duplicates" invariant is false, and the expansion runs after the dedup pass that exists for exactly this.** `crates/core/base64.rs:61` says each `(offset, lead, trail)` tuple gives a distinct bit pattern, "so the result is naturally free of duplicates," and `literals_are_unique` (`base64.rs:211`) asserts it. Any run of `U` (0x55, bits `0101...`) breaks it: for `pattern_literals(Alphabet::Standard, b"UUU")`, offset 1 with lead `01`/trail `0101` and offset 2 with lead `0101`/trail `01` both yield `VVVVV`. (`b"U"` gives `VV` twice the same way.) The test passes only because none of its queries has a 2-bit period. Duplicates are harmless to correctness, but `Patterns::from_low_args` dedups on purpose (comment at `hiargs.rs:1024-1033`, "I've seen this have a big impact on real world data") and the expansion at `hiargs.rs:149-160` lands after it. Fix the comment and drop the test, or dedup the expanded list.

**4. An empty pattern flips meaning.** `base64.rs:65-67` returns no literals for an empty query, so `rg --base64 ''` hits `matches_possible() == false` (`hiargs.rs:539`) and prints nothing, while `rg -F ''` prints every line. With `-v` it inverts: `rg --base64 -v ''` prints every line (the 15.0.0 "`rg -vf` on an empty file matches everything" path), `rg -v ''` prints none. `rg --base64 -e '' -e foo` drops the `''` silently. The empty string is a substring of every encoding, so returning `vec![String::new()]` keeps `--base64` consistent with plain `-F`; `empty_query_returns_no_literals` (`base64.rs:197`) would flip with it.

**5. The docs describe a regex the code never builds, and promise a case it misses.**
- `crates/core/flags/defs.rs:364` "transformed into a regex", `defs.rs:372` "The generated regex enumerates", `defs.rs:443` "how the rewritten regex is built": the code emits fixed-string literals, which `defs.rs:376` itself says ("This flag implies \flag{fixed-strings}").
- `crates/core/base64.rs:47` "skip regex parsing entirely": false whenever `-i` or `-S` is set, since `is_fixed_strings` bails out on `case_insensitive || case_smart` (`crates/regex/src/config.rs:106`) and all up-to-264 literals per pattern get escaped and parsed.
- `defs.rs:367` names certificates as a use case. PEM wraps at 64 columns (MIME at 76), so a secret whose encoding straddles a line break isn't found in line-oriented mode. One sentence saying so beats letting users assume a miss means absence.
- The module reads machine-written in places, which the body's disclosure covers but the code still carries: the em dashes at `base64.rs:26` and `base64.rs:28` are the only ones under `crates/core`, and comments like the one in `literals_are_unique` narrate rather than explain.

**6. Lean: about 75 lines can go without making anything harder to read.**
- Two enums for one choice. `Base64Mode` plus `Base64Mode::alphabet()` (`crates/core/flags/lowargs.rs:232-258`) mirror `base64::Alphabet` one to one with an `Off` arm added. `LowArgs` already models "off or one of N" as `Option<T>`: `boundary: Option<BoundaryMode>` at `lowargs.rs:42`. Make the field `base64: Option<base64::Alphabet>` and delete `Base64Mode`; that also reverts the reflowed import block at `defs.rs:26-30`. About -27.
- The tuple-rebinding at `hiargs.rs:145-160` plus the edit at `hiargs.rs:290` collapse to mutating what's already mutable (`low` is `mut` in `from_low_args`), and line 290 goes back to `low.fixed_strings`:
  ```rust
  let mut patterns = Patterns::from_low_args(&mut state, &mut low)?;
  if let Some(alphabet) = low.base64 {
      let pats = std::mem::take(&mut patterns.patterns);
      patterns.patterns = base64::expand_patterns(alphabet, pats);
      low.fixed_strings = true;
  }
  ```
  About -10.
- `url_safe_literals_have_no_standard_only_chars` (`base64.rs:233`) can't fail unless the `URL_SAFE` constant changes, and `encode_url_safe_swaps_chars` (`base64.rs:188`) already pins that constant. `aligned_encoding_is_a_literal` (`base64.rs:203`) is the `prefix = ""`, `suffix = ""`, `q = "foo"` case of `matches_every_alignment`. `literals_are_unique` asserts a false invariant (Nit 3). About -38 together.

Lean: -75 lines possible
