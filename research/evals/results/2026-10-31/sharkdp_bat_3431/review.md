Important: 3, Nit: 1, Pre-existing: 0

## Important

**1. Nothing shows RPMSpec meets the inclusion criteria for new syntaxes.**

`doc/assets.md` puts this ahead of every other step: "**Important:** Before proceeding, verify that the syntax you wish to add meets the criteria for inclusion", and the criterion is "More than 10,000 downloads at Package Control" (`doc/assets.md`, "Criteria for inclusion of new syntaxes"). The syntax request template asks for the evidence directly, under "Guideline Criteria: [packagecontrol.io link here]" (`.github/ISSUE_TEMPLATE/syntax_request.md`).

The body links `https://github.com/dreadatour/RPMSpec` and closes #2605, but gives no Package Control link or download count. Please add the packagecontrol.io link and the number to the description. If the package is under 10,000, this is a close, and the user-local syntax route in the README is the answer for anyone who wants it.

**2. The syntax is vendored as a loose file from a standalone Git repo, with no provenance or license recorded.**

- `doc/assets.md` step 1: "Find a Sublime Text syntax for the given language, preferably in a separate Git repository which can be included as a submodule". The source the body cites, dreadatour/RPMSpec, is exactly that kind of repo. The Go modules syntax added just before this one in `CHANGELOG.md` went in as a submodule (`.gitmodules:281`, `assets/syntaxes/02_Extra/Gomod`).
- When a syntax is added by hand, the repo records where it came from and why it isn't a submodule under "Non-submodule additions" in `doc/assets.md` (Nim, Rego, SML, Cabal, Lean all have an entry). This PR adds `assets/syntaxes/02_Extra/RPMSpec.sublime-syntax` and no entry. The file's header (`# http://www.sublimetext.com/docs/syntax.html`) suggests it was converted from a `.tmLanguage`, which is also undocumented.
- The vendored file carries no license or attribution, and nothing in the PR says what license dreadatour/RPMSpec is under or that it's compatible with bat's.

Fix: add dreadatour/RPMSpec as a submodule under `assets/syntaxes/02_Extra/`. If there's a reason it can't be one, keep the file but add a "Non-submodule additions" entry naming the source commit, the reason, and the upstream license.

**3. The syntax mis-scopes ordinary spec content, and the test fixture locks one of those mis-scopes in.**

Class: rules that don't match what real spec files contain.

- `assets/syntaxes/02_Extra/RPMSpec.sublime-syntax:65`, the `archs` list has no `x86_64`, `aarch64`, `ppc64le`, `riscv64`, or `armv7hl`, and it holds upstream typos: `sparc64armv3l` (two arches fused, so neither `sparc64` nor `armv3l` matches), `ips` for `mips`, and `ppc` listed twice. Since anything in the list that doesn't match falls to `'[^\s,]+'` scoped `invalid.spec` (lines 19-20 and 45-46), `ExclusiveArch: x86_64 aarch64` and `%ifarch x86_64` paint the two most common arches as invalid. Any macro hits the same rule: `ExclusiveArch:  %{rust_arches}` in the new fixture renders as `invalid.spec` (color `248;248;240`) at `tests/syntax-tests/highlighted/RPMSpec/bat.spec:32`, while `%{name}` everywhere else renders as `variable.other.spec` (`255;255;255`). The fixture's only real arch is `noarch`, so it can't catch a regression in this list.
- `RPMSpec.sublime-syntax:31-35`, `^(Source|Patch)` pushes `keyword.spec` until the next `:`, with no end-of-line pop. The `Source\d*`/`Patch\d*` alternatives at line 27 already win for every `Source0:`/`Patch1:` header (same match position, earlier rule), so this rule only fires on prose. A `%description` line like `Source code lives on GitHub.` followed by `See https://github.com/sharkdp/bat` scopes both lines as a keyword up to the colon in `https:`.
- `RPMSpec.sublime-syntax:10-30`, none of the preamble tag rules is anchored with `^`, so `Name:`, `URL:`, `License:`, `Patch1:` and the rest match anywhere on a line. `%changelog` entries such as `- Rebase Patch1: fix build` and description prose like `Project URL: https://...` get keyword scope mid-sentence.
- `RPMSpec.sublime-syntax:51`, the alternation `%(if|else|endif|define|global|undefine|ifos|ifnos)` tries `if` first, so `%ifos linux` scopes `%if` as the keyword and leaves `os` plain. Putting `ifos|ifnos` before `if` (or adding `\b`) fixes it.

Please fix the arch list (or match any `[^\s,]+` as a plain value instead of `invalid`), and add an `ExclusiveArch: x86_64 aarch64` line plus a description line starting with "Source" to `tests/syntax-tests/source/RPMSpec/bat.spec` so the fixture would catch these.

## Nit

**4. The test fixture is copied from openSUSE without the `LICENSE.md` the guide asks for.**

`tests/syntax-tests/source/RPMSpec/bat.spec` is SUSE's packaging file ("Copyright (c) 2025 SUSE LLC"), which by its own header falls under bat's MIT/Apache license. `doc/assets.md` (Syntax tests, step 4) says: "If it requires attribution, please add a `LICENSE.md` in the same folder". MIT requires attribution, and `tests/syntax-tests/source/Lean/LICENSE.md` shows the expected form. One short file fixes it.

## Lean

- `RPMSpec.sublime-syntax:31-35`: delete the `^(Source|Patch)` rule. Line 27 already covers `SourceN:`/`PatchN:`, and this rule only causes the prose bug in finding 3. (-5)
- `RPMSpec.sublime-syntax:15-20` and `41-46`: the two push bodies are identical. Move them to one named context (say `arch_values`) and use `push: arch_values` in both places. (-4)
- `RPMSpec.sublime-syntax:13-14` and `39-40`: `captures: {0: ...}` on a whole match is just `scope:`. (-2)

Lean: -11 lines possible
