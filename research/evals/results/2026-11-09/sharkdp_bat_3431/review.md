Important: 5, Nit: 2, Pre-existing: 0

## Important

**1. The arch list marks the most common architectures, and any macro, as `invalid`.** Your own fixture shows it.

`assets/syntaxes/02_Extra/RPMSpec.sublime-syntax:65` is the only thing allowed after `BuildArch`/`ExclusiveArch`/`ExcludeArch` (line 12) and `%ifarch`/`%ifnarch` (line 38). Anything else falls through to `[^\s,]+` with scope `invalid.spec` (lines 19-20 and 45-46). The list has no `x86_64`, `aarch64`, `armv7hl`, `ppc64le` or `riscv64`, and it carries typos from the source:
- `sparc64armv3l` is missing a `|`, so neither `sparc64` nor `armv3l` matches.
- `ips` should be `mips`, `iseries` should be `ppciseries`, and `armv4lm` isn't an arch.
- `ppc|ppc` is listed twice.

Cases that go wrong:
- `ExclusiveArch: x86_64 aarch64` highlights both words as invalid.
- `%ifarch %{ix86} x86_64` highlights both arguments as invalid.
- `ExclusiveArch:  %{rust_arches}` is already wrong in the committed fixture: `tests/syntax-tests/highlighted/RPMSpec/bat.spec:32` renders `%{rust_arches}` in `38;2;248;248;240`, Monokai Extended's `invalid` foreground (the same color `sorry` gets in `highlighted/Lean/test.lean:79`). Every other `%{...}` in the file is `255;255;255`.

`doc/assets.md` step 6 of "Syntax tests" asks you to "make sure that the syntax highlighting looks correct", and the regression fixture now pins this as correct. Fix the list, let `%{...}` and `%name` match inside the arch context before the invalid fallback (or drop the fallback), and regenerate the fixture with an `x86_64` line in it.

**2. The syntax is pasted in as a loose file: it isn't a submodule, and it isn't listed as a non-submodule addition.**

`doc/assets.md` step 1: "Find a Sublime Text syntax for the given language, preferably in a separate Git repository which can be included as a submodule (under `assets/syntaxes`)". The body links one, https://github.com/dreadatour/RPMSpec. Your previous syntax PR did it this way: `.gitmodules:281-283` adds `assets/syntaxes/02_Extra/Gomod`. Where upstream only ships a `.tmLanguage`, the repo keeps the submodule plus a converted file beside it (`02_Extra/Crystal/` with `Crystal.sublime-syntax`, `02_Extra/Apache/` with `Apache.sublime-syntax`).

If there's a reason it can't be a submodule, `doc/assets.md:92` ("### Non-submodule additions") is where every other loose file records its source and that reason; this PR adds no entry. If you edited the file after converting it, it also belongs under "### Manual modifications". A submodule brings upstream's LICENSE with it too, which `src/assets/build_assets/acknowledgements.rs` picks up for `bat --acknowledgements`; a loose file drops it.

**3. `^(Source|Patch)` at lines 31-35 can swallow the rest of the file as `keyword.spec`.**

Line 27 already scopes `Source\d*:` and `Patch\d*:`, and it wins the tie at column 0 because it comes first. So line 31 only fires on a line that starts with `Source` or `Patch` and isn't a tag. It then pushes a context whose only exit is a `:`, with no `$` pop. Case:

```
%description
Patched build of foo for openSUSE.
More text here.

%prep
%setup -q
```

Everything from `Patched` to the next colon anywhere below, across sections, is highlighted as a keyword, and macros inside it lose their scope. The fixture never reaches this rule, since `Source0:`/`Source1:` hit line 27. Delete lines 31-35.

**4. The tag rules aren't anchored to the start of a line, so tags match mid-line in prose and scriptlets.**

RPM tags only count at the start of a line, but these rules have no `^`:
- line 10 (`Icon|ExclusiveOs|ExcludeOs`)
- line 12 (`BuildArch|...`)
- line 21 (`Conflicts|...|Requires|...`)
- line 23 (`Epoch|...`)
- line 25 (`AutoReq|...`)
- line 27 (`Copyright|License|Summary|...`)
- line 29 (`Name|Version|Release|Url|URL`)

Cases:
- `%description` text `Set the mirror URL: https://example.com` highlights `URL:` as a keyword.
- In `%install`, `echo "Version: %{version}" > VERSION` highlights `Version:`.
- `See BuildArch: in the docs` in a description pushes the arch context from line 12, and `in`, `the` and `docs` come out as `invalid`.

Add `^` (or `^\s*`) to each of the seven.

**5. The body doesn't show the syntax meets the inclusion criterion.**

`doc/assets.md`: "**Important:** Before proceeding, verify that the syntax you wish to add meets the criteria for inclusion", and the criterion is "More than 10,000 downloads at Package Control". The body links the GitHub repo but gives no Package Control page or install count. Please add it, or say why this one should be an exception.

## Nits

- **`ifos`/`ifnos` at line 51 are unreachable.** `if` comes first in the alternation and there's no `\b`, so `%ifos linux` highlights only `%if` and leaves `os` plain. `%elif`, `%elifarch` and `%elifos` (RPM 4.15+) aren't listed, so they fall to line 58 as plain macros. Fix it with `'%(ifos|ifnos|if|elifarch|elifos|elif|else|endif|define|global|undefine)\b'`.
- **The changelog rule and the fixture miss real input.** Line 62 (`^\* .*\)$`) only matches changelog headers that end in `)`, so a standard `* Mon Nov 09 2026 Jane Doe <jane@example.com> - 0.25.0-1` gets no scope. The fixture's `%changelog` is empty, so nothing tests that rule. Nothing tests `%ifarch`, `%define`/`%global`, `%else`, `%pre`/`%post`, `Requires(post):` or line 31 either. `doc/assets.md` says a comprehensive file is "not strictly necessary", but a few lines covering these would have caught 1, 3 and this one.

Lean: -11 lines possible
- Delete lines 31-35 (finding 3): -5.
- Lines 15-20 and 41-46 are the same push body. Make one named context (say `arch-list`) and use `push: arch-list` from both: -4.
- `captures: 0: keyword.spec` (lines 13-14) and `captures: 0: keyword.control.spec` (lines 39-40) are just `scope:` on the match: -2.

Requesting changes for 1 through 4. I'd merge once those are fixed and 5 is answered.
