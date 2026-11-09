Important: 3, Nit: 3, Pre-existing: 0

## Important

**1. The arch list marks the most common arches and every arch macro as `invalid`, and the new test pins that.**

`assets/syntaxes/02_Extra/RPMSpec.sublime-syntax:12-20` and `:38-46` push a context after `BuildArch:`/`ExclusiveArch:`/`ExcludeArch:` and `%ifarch`/`%ifnarch` where anything that isn't in `archs` (`:65`) falls through to `[^\s,]+` with scope `invalid.spec`. The `archs` list has no `x86_64`, `aarch64`, `armv7hl`, `ppc64le`, or `riscv64`, and it never allows a macro. Inputs that go wrong:

- `ExclusiveArch: x86_64 aarch64` scopes both words `invalid.spec` (red background in most themes).
- `%ifarch x86_64` does the same.
- `ExclusiveArch: %{rust_arches}` (or `%{ix86}`, `%{arm}`) scopes the macro `invalid.spec`. The PR's own fixture shows it: `tests/syntax-tests/highlighted/RPMSpec/bat.spec:32` renders `%{rust_arches}` as `38;2;248;248;240`, while every other `%{...}` in the file is `38;2;255;255;255`. The regression test now locks the wrong highlight in.

The list also has typos that break real arches: `sparc64armv3l` is one token (missing `|`), so `sparc64` alone is invalid; `ips` looks like `mips`; `ppcpseries` and `armv4lm` don't match RPM's names; `ppc` appears twice.

Fix: add the current arches, let `%\{...\}` and `%name` macros through inside the arch context (include the variable rules before the `invalid` fallback), and regenerate the highlighted file so line 32 stops showing `invalid`. If the grammar is vendored as-is from upstream, that edit needs an entry under "Manual modifications" in `doc/assets.md` (see finding 2).

**2. Where this grammar came from isn't recorded the way `doc/assets.md` asks, and nothing carries its license.**

`doc/assets.md` step 1: "Find a Sublime Text syntax for the given language, preferably in a separate Git repository which can be included as a submodule". The body links a standalone repo (`https://github.com/dreadatour/RPMSpec`), yet the PR commits a loose `RPMSpec.sublime-syntax`. Your previous syntax PR in this same CHANGELOG block (Gomod, #3424) went in as a submodule (`.gitmodules:281-283`), so I'd expect the same here unless upstream only ships a `.tmLanguage`. The header at `RPMSpec.sublime-syntax:3` looks like Sublime's converter output, which suggests that's the case. If so, say so, and follow the repo's convention for manual adds: `doc/assets.md` lists each one under "Non-submodule additions" with its source (Nim, Rego, SML, Cabal, Lean, Assembly x86_64). This PR adds no entry, and if you changed anything from upstream, no "Manual modifications" entry either.

License: `bat --acknowledgements` is built from `LICENSE`/`NOTICE` files found under the assets dir (`src/assets/build_assets/acknowledgements.rs:15-45`). A submodule brings upstream's license along; a loose file brings nothing. The body doesn't name upstream's license, so I can't tell whether we're allowed to ship it or what attribution it needs.

**3. No evidence the syntax meets the inclusion bar.**

`doc/assets.md`: "**Important:** Before proceeding, verify that the syntax you wish to add meets the criteria for inclusion", and the criterion is "More than 10,000 downloads at Package Control". The body gives no Package Control link or download count. Please add both.

## Nits

**1. Tag rules aren't anchored to line start.** `RPMSpec.sublime-syntax:10, 21, 23, 25, 27, 29` match `Name:`, `URL:`, `License:` and the rest anywhere on a line. A `%description` line like `Upstream URL: https://example.org` or an `%install` line like `echo "Version: %{version}"` gets `keyword.spec` mid-sentence. Prefixing each with `^` matches how RPM reads preamble tags.

**2. `^(Source|Patch)` (`:31-35`) is dead for every normal tag and wrong when it fires.** Line 27 already matches `Source0:`/`Patch1:` at the same column and is listed first, so this rule only runs when that one fails, for example a `%description` paragraph starting `Patches from upstream are applied.`. Then its `meta_scope: keyword.spec` stays open until the next `:`, which can be lines later. Deleting the rule loses nothing.

**3. `ifos|ifnos` in `:51` can't match.** The alternation tries `if` first, so `%ifos linux` highlights `%if` as a keyword and leaves `os` plain. Put the longer names first: `%(ifos|ifnos|if|else|endif|define|global|undefine)`.

Lean: -5 lines possible
