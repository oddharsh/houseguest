#!/usr/bin/env bash
# Read a repo's house rules from the clone you're in: what enforces style, and how.
#
#   house.sh [--files a,b,...] [--machine]
#
# Run from the root of a clone. Reports the languages in play, each formatter and
# linter the repo configures (with the command that checks only your files), the
# .editorconfig rules for your file types, license-header and commit conventions,
# changeset or changelog requirements, and the CI steps that enforce any of it.
# --files narrows everything to the files you're touching.
# --machine prints tab-separated "tool<TAB>check command" lines for housecheck.sh.
# Read-only.

set -uo pipefail
files_arg="" machine=""
while [ $# -gt 0 ]; do
  case "$1" in
    --files) files_arg="$2"; shift 2 ;;
    --machine) machine=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "house.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
git rev-parse --git-dir >/dev/null 2>&1 || { echo "house.sh: run this inside a clone" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)" || exit 2

all=$(git ls-files)
if [ -n "$files_arg" ]; then mine=$(echo "$files_arg" | tr ',' '\n' | sed '/^$/d'); else mine=""; fi
exts() { echo "${1:-$all}" | sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' | tr 'A-Z' 'a-z'; }
has() { echo "$all" | grep -q -E "$1"; }
pkg_has() { [ -f package.json ] && grep -q -E "$1" package.json; }
dep() { [ -f package.json ] && jq -e --arg d "$1" '((.devDependencies // {}) + (.dependencies // {})) | has($d)' package.json >/dev/null 2>&1; }
toml_has() { [ -f pyproject.toml ] && grep -q -E "$1" pyproject.toml; }
want() {  # want <ext-regex>: true if my files (or the repo, without --files) include these
  if [ -n "$mine" ]; then exts "$mine" | grep -q -E "^($1)$"; else exts | grep -q -E "^($1)$"; fi
}
jsrun() {  # jsrun <bin>: prefer the repo's installed copy
  if [ -x "node_modules/.bin/$1" ]; then echo "node_modules/.bin/$1"
  elif [ -f pnpm-lock.yaml ]; then echo "pnpm exec $1"
  elif [ -f yarn.lock ]; then echo "yarn $1"
  else echo "npx --no-install $1"; fi
}
# Where the repo invokes its tools: package.json scripts and CI run lines, "source<TAB>command".
invocations() {
  [ -f package.json ] && jq -r '.scripts // {} | to_entries[] | "package.json script \(.key)\t\(.value)"' package.json 2>/dev/null
  [ -d .github/workflows ] && grep -h -E '^[[:space:]]*(-[[:space:]]*)?run:' .github/workflows/*.y*ml 2>/dev/null \
    | sed -E 's/^[[:space:]]*(-[[:space:]]*)?run:[[:space:]]*/CI	/'
}
# repo_flags <bin> [drop-regex]: the flags the repo's own check script or CI passes to <bin>,
# so housecheck lints the way CI does (oxlint --type-aware catches what plain oxlint can't).
# Skips fix/write modes and drops path arguments, since housecheck passes the changed files.
# Prints "flags<TAB>source", or nothing.
repo_flags() {
  local line src cmd seg out="" prev="" t
  line=$(invocations | grep -E "(^|[[:space:]/])$1([[:space:]]|$)" | grep -v -E -- '--fix|--write|(^|[[:space:]])-w([[:space:]]|$)' \
    | awk -F'\t' '{ p = ($1 ~ /check|lint|ci|test/) ? 0 : 1; print p "\t" $0 }' | sort -s -t$'\t' -k1,1 | head -1 | cut -f2-)
  [ -n "$line" ] || return 0
  src=${line%%	*}; cmd=${line#*	}
  seg=$(echo "$cmd" | sed -E "s#.*(^|[[:space:]/])$1([[:space:]]|$)##; s/(&&|\|\||;|\|).*//")
  for t in $seg; do
    case "$t" in
      -*) echo "$t" | grep -q -E "^(${2:-^$})$" || out="$out $t" ;;
      *) case "$prev" in -*=*|"") ;; -*)
           case "$t" in .|./|*'*'*|*/) ;; *) [ -d "$t" ] || out="$out $t" ;; esac ;; esac ;;
    esac
    prev=$t
  done
  [ -n "$out" ] && printf '%s\t%s\n' "${out# }" "$src"
}
withflags() {  # withflags <bin> [drop-regex]: " <flags>" to splice into the command
  local r; r=$(repo_flags "$1" "${2:-}"); [ -n "$r" ] && printf ' %s' "${r%%	*}"
}
F='{FILES}'   # housecheck.sh substitutes the changed files here
# Config files can sit in a folder above the changed files (wpt keeps flake8's in tools/).
# up <name-regex> [section]: the nearest tracked match in an ancestor folder of my files,
# skipping candidates that lack [section] (a tox.ini without [flake8] isn't flake8's config).
up() {
  local d f c
  for f in ${mine:-.}; do
    d=$(dirname "$f")
    while :; do
      for c in $(echo "$all" | grep -E "^$( [ "$d" = . ] && echo "" || echo "$d/" )($1)$"); do
        if [ -z "${2:-}" ] || cat_tracked "$c" | grep -q -F "[$2]"; then echo "$c"; return; fi
      done
      [ "$d" = . ] && break; d=$(dirname "$d")
    done
  done
}
cat_tracked() { git show "HEAD:$1" 2>/dev/null; }   # works in sparse checkouts too
tools=""
add() { tools="$tools$1	$2
"; }

# --- Formatters and linters, by what the repo configures ----------------------
if want 'js|jsx|ts|tsx|mjs|cjs|mts|cts|json|jsonc|css|scss|md|mdx|yml|yaml|html|vue|svelte|astro'; then
  if has '(^|/)(\.prettierrc[^/]*|prettier\.config\.[a-z]+)$' || dep prettier; then add prettier "$(jsrun prettier) --check$(withflags prettier '--check|-c|--list-different|-l') $F"; fi
  if has '(^|/)\.oxfmtrc\.jsonc?$' || dep oxfmt; then add oxfmt "$(jsrun oxfmt) --check $F"; fi
  if has '(^|/)biome\.jsonc?$' || dep @biomejs/biome; then add biome "$(jsrun biome) check $F"; fi
  if has '(^|/)dprint\.jsonc?$|(^|/)\.dprint\.jsonc?$'; then add dprint "dprint check $F"; fi
  if has '(^|/)deno\.jsonc?$'; then add deno "deno fmt --check $F && deno lint $F"; fi
fi
if want 'js|jsx|ts|tsx|mjs|cjs|mts|cts|vue|svelte'; then
  if has '(^|/)(eslint\.config\.[a-z]+|\.eslintrc[^/]*)$' || pkg_has '"eslintConfig"' || dep eslint; then add eslint "$(jsrun eslint)$(withflags eslint '--cache') $F"; fi
  if has '(^|/)\.?oxlintrc\.json$|(^|/)oxlint\.json$' || dep oxlint; then add oxlint "$(jsrun oxlint)$(withflags oxlint) $F"; fi
  if has '(^|/)tsconfig[^/]*\.json$'; then add tsc "$(jsrun tsc) --noEmit -p ."; fi
fi
# Rust: run each tool the way the CI job that runs it does, on that job's toolchain. Jobs differ
# (jxl-rs formats with `cargo +nightly fmt` and lints with clippy on stable), and lints change
# between releases, so a repo-wide guess fails clean patches.
tcnotes=""
TC_RE='^(stable|beta|nightly(-[0-9]{4}-[0-9]{2}-[0-9]{2})?|[0-9]+\.[0-9]+(\.[0-9]+)?)$'
jobs_of() {  # every workflow job as one record, separated by NUL-free "\036" lines
  for w in .github/workflows/*.y*ml; do
    [ -f "$w" ] || continue
    awk '/^jobs:[[:space:]]*$/ {inj=1; next}
         inj && /^[^[:space:]#]/ {inj=0}
         inj && /^[[:space:]]+[A-Za-z0-9_-]+:[[:space:]]*$/ { match($0, /^[[:space:]]+/); if (ji == "" ) ji = RLENGTH; if (RLENGTH == ji) print "\036" }
         inj {print}' "$w"
  done
}
# job_toolchain: the toolchain a job installs: a `toolchain:` input, a rustup command, then
# dtolnay/rust-toolchain@ref when the ref names one (a SHA, vN, or master just pins the action, so
# its trailing "# stable" comment or stable applies). A job that installs nothing runs on stable.
job_toolchain() {
  local j="$1" t
  t=$(echo "$j" | grep -o -E '^[[:space:]]*toolchain:[[:space:]]*["'"'"']?[A-Za-z0-9._-]+' | sed -E 's/.*:[[:space:]]*["'"'"']?//' | grep -E "$TC_RE" | head -1)
  [ -z "$t" ] && t=$(echo "$j" | grep -o -E 'rustup (toolchain install|default|override set) [A-Za-z0-9._-]+' | awk '{print $NF}' | grep -E "$TC_RE" | head -1)
  [ -z "$t" ] && t=$(echo "$j" | grep -o -E 'dtolnay/rust-toolchain@[A-Za-z0-9._-]+([[:space:]]*#[[:space:]]*[A-Za-z0-9._-]+)?' \
    | awk '{ split($1, a, "@"); r = a[2]; c = ($0 ~ /#/) ? $NF : ""; print (r ~ /^[0-9a-f]{40}$|^v[0-9]+$|^master$/) ? (c != "" ? c : "stable") : r }' | grep -E "$TC_RE" | head -1)
  echo "${t:-stable}"
}
installed_tc() { command -v rustup >/dev/null 2>&1 && rustup toolchain list 2>/dev/null | grep -q -E "^$(printf '%s' "$1" | sed 's/[.]/\\./g')([.-]|$)"; }
# rust_tool <name> <cargo subcommand> <fallback command>
rust_tool() {
  local name="$1" sub="$2" cmd="$3" job="" line="" tc="stable" src="no CI job runs it; using defaults"
  if [ -d .github/workflows ]; then
    job=$(jobs_of | awk -v RS='\036' -v s="$sub" '$0 ~ ("cargo( \\+[A-Za-z0-9._-]+)? " s "([[:space:]]|$)") {print; exit}')
    line=$(echo "$job" | grep -o -E "cargo( \+[A-Za-z0-9._-]+)? $sub([[:space:]].*)?$" | head -1 | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
  fi
  if [ -n "$line" ]; then
    tc=$(echo "$line" | grep -o -E '^cargo \+[A-Za-z0-9._-]+' | sed 's/^cargo +//')
    [ -z "$tc" ] && tc=$(job_toolchain "$job")
    # CI's own flags, minus GitHub expressions and +toolchain (handled below).
    cmd=$(echo "$line" | sed -E 's/^cargo \+[A-Za-z0-9._-]+ /cargo /; s/[^[:space:]]*\$\{\{[^}]*\}\}[^[:space:]]*//g; s/[[:space:]]+/ /g; s/ $//')
    src="from CI: $(echo "$line" | cut -c1-120)"
  fi
  if has '(^|/)rust-toolchain(\.toml)?$'; then
    tcnotes="$tcnotes$name: the repo's rust-toolchain file picks the toolchain ($src)
"
  elif [ -n "${RUSTUP_TOOLCHAIN:-}" ]; then
    tcnotes="$tcnotes$name: using RUSTUP_TOOLCHAIN=$RUSTUP_TOOLCHAIN from the environment; CI uses $tc ($src)
"
  elif installed_tc "$tc"; then
    cmd=$(echo "$cmd" | sed -E "s/^cargo /cargo +$tc /")
    note="$name: $tc, as CI uses ($src)"
    if [ "$tc" = stable ]; then
      # rustup prints "stable-<host> - update available: 1.93.0 (...) -> 1.99.1 (...)"; older
      # versions say "Update available : ...".
      behind=$(rustup check 2>/dev/null | grep -i -E '^stable' | grep -i -o -E 'update available ?: *[0-9.]+[^>]*-> *[0-9.]+' | sed -E 's/.*: *([0-9.]+).*-> *([0-9.]+)/\1 -> \2/')
      [ -n "$behind" ] && note="$note. DRIFT: local stable is behind the current release ($behind) and CI runs the newest; run rustup update stable"
    fi
    tcnotes="$tcnotes$note
"
  else
    tcnotes="$tcnotes$name: DRIFT: CI uses $tc, which isn't installed here (rustup toolchain install $tc); running on the default toolchain ($src)
"
  fi
  add "$name" "$cmd"
}
if want 'rs'; then
  rust_tool rustfmt fmt "cargo fmt --all -- --check"
  rust_tool clippy clippy "cargo clippy --all-targets -- -D warnings"
fi
if want 'go'; then
  add gofmt "gofmt -l $F"
  has '(^|/)\.golangci\.(ya?ml|toml|json)$' && add golangci-lint "golangci-lint run"
fi
if want 'py|pyi'; then
  if has '(^|/)\.?ruff\.toml$' || toml_has '^\[tool\.ruff'; then add ruff "ruff format --check $F && ruff check $F"; fi
  if toml_has '^\[tool\.black\]'; then add black "black --check $F"; fi
  fl8=$(up '\.flake8|flake8\.ini|tox\.ini|setup\.cfg' flake8)
  [ -n "$fl8" ] && add flake8 "flake8 --config $fl8 $F"
  if toml_has '^\[tool\.isort\]' || has '(^|/)\.isort\.cfg$'; then add isort "isort --check-only $F"; fi
  if has '(^|/)\.flake8$' || { [ -f setup.cfg ] && grep -q '^\[flake8\]' setup.cfg; }; then add flake8 "flake8 $F"; fi
  if toml_has '^\[tool\.mypy\]' || has '(^|/)mypy\.ini$'; then add mypy "mypy $F"; fi
fi
if want 'zig'; then add zig-fmt "zig fmt --check $F"; fi
if want 'c|h|cc|cpp|cxx|hpp|hh|m|mm'; then has '(^|/)\.clang-format$' && add clang-format "clang-format --dry-run --Werror $F"; fi
if want 'swift'; then
  has '(^|/)\.swift-format$' && add swift-format "swift-format lint --strict $F"
  has '(^|/)\.swiftlint\.ya?ml$' && add swiftlint "swiftlint lint --strict $F"
fi
if want 'rb'; then has '(^|/)\.rubocop\.ya?ml$' && add rubocop "rubocop $F"; fi
if want 'kt|kts'; then has '(^|/)\.editorconfig$' && grep -q -i ktlint .editorconfig 2>/dev/null && add ktlint "ktlint $F"; fi
if want 'md|mdx'; then has '(^|/)\.markdownlint[^/]*$' && add markdownlint "$(jsrun markdownlint) $F"; fi
has '(^|/)\.pre-commit-config\.ya?ml$' && add pre-commit "pre-commit run --files $F"

# The line width the repo enforces, from the nearest config that sets one.
width=""
for spec in '\.editorconfig:max_line_length *= *([0-9]+)' '\.flake8|flake8\.ini|tox\.ini|setup\.cfg:max-line-length *= *([0-9]+)' 'pyproject\.toml|ruff\.toml|\.ruff\.toml:line-length *= *([0-9]+)' '\.prettierrc|\.prettierrc\.json|\.oxfmtrc\.jsonc?|biome\.jsonc?:"(printWidth|lineWidth)" *: *([0-9]+)' 'deno\.jsonc?:"lineWidth" *: *([0-9]+)' 'rustfmt\.toml|\.rustfmt\.toml:max_width *= *([0-9]+)' '\.clang-format:ColumnLimit *: *([0-9]+)'; do
  case "${spec%%:*}" in *flake8*) cf=$(up "${spec%%:*}" flake8) ;; *) cf=$(up "${spec%%:*}") ;; esac; [ -z "$cf" ] && continue
  w=$(cat_tracked "$cf" | grep -m1 -E "${spec#*:}" | grep -o -E '[0-9]+' | tail -1)
  [ -n "$w" ] && { width="$w"; width_src="$cf"; break; }
done
if [ -n "$machine" ]; then printf '%s' "$tools"; [ -n "$width" ] && printf 'LINEWIDTH\t%s\n' "$width"; printf '%s' "$tcnotes" | sed 's/^/TOOLCHAINNOTE	/'; exit 0; fi

echo "## House rules"
echo
echo "### Languages"
src=${mine:-$all}
exts "$src" | sort | uniq -c | sort -rn | head -6 | awk '{printf "- .%s (%d files)\n", $2, $1}'

echo
echo "### Formatters and linters this repo configures"
if [ -n "$tools" ]; then
  printf '%s' "$tools" | while IFS=$'\t' read -r name cmd; do
    [ -n "$name" ] && echo "- **$name**: \`$(echo "$cmd" | sed "s#{FILES}#<your files>#g")\`"
    case "$name" in prettier|eslint|oxlint) r=$(repo_flags "$name"); [ -n "$r" ] && echo "  (flags from ${r#*	}, so it matches what CI runs)" ;; esac
  done
else
  echo "- none configured: fall back to the conventions of neighboring files, then \`references/defaults.md\`"
fi

echo
echo "### Scripts and CI steps that enforce style"
if [ -f package.json ]; then
  jq -r '.scripts // {} | to_entries[] | select(.key | test("lint|format|fmt|check|style|prettier|typecheck|test"; "i")) | "- npm script `\(.key)`: `\(.value)`"' package.json 2>/dev/null | head -12
fi
for mk in Makefile justfile Justfile; do
  [ -f "$mk" ] && grep -E '^[A-Za-z0-9_-]*(lint|fmt|format|check|style|test)[A-Za-z0-9_-]*:' "$mk" | cut -d: -f1 | sed "s#^#- $mk target: #" | head -8
done
if [ -d .github/workflows ]; then
  grep -h -E '^\s*(-\s*)?run:\s*.*(fmt|format|lint|clippy|prettier|biome|eslint|oxlint|ruff|black|gofmt|golangci|rubocop|swiftlint|check)' .github/workflows/*.y*ml 2>/dev/null \
    | sed -E 's/^\s*(-\s*)?run:\s*//' | sort -u | head -10 | sed 's/^/- CI runs: `/; s/$/`/'
fi

echo
echo "### Line width"
if [ -n "$width" ]; then echo "- $width columns, from \`$width_src\`"; else echo "- not configured; match neighboring files"; fi

echo
echo "### Tool versions CI pins (use these; newer versions can break the repo's own scripts)"
pins=$( { [ -d .github/workflows ] && grep -h -E '^\s*[A-Za-z_-]*(VERSION|version)\s*:' .github/workflows/*.y*ml 2>/dev/null | grep -i -E 'node|deno|python|go|rust|zig|bun|pnpm|ruby|java|swift|toolchain' | grep -v -F '${{' | sed -E 's/^[[:space:]]+//' | sort -u | head -8
  for f in .nvmrc .node-version .python-version .tool-versions rust-toolchain rust-toolchain.toml .zig-version; do [ -f "$f" ] && echo "$f: $(tr '\n' ' ' < "$f" | cut -c1-80)"; done
  [ -f package.json ] && jq -r '"packageManager: \(.packageManager // empty)", (.engines // {} | to_entries[] | "engines.\(.key): \(.value)")' package.json 2>/dev/null; } | sed '/^packageManager: $/d')
if [ -n "$pins" ]; then echo "$pins" | sed 's/^/- /'; else echo "- none found"; fi

echo
echo "### .editorconfig for your file types"
if [ -f .editorconfig ]; then
  awk '/^\[/{sec=$0} /^[a-z_]+ *=/{print sec " " $0}' .editorconfig | head -24 | sed 's/^/- /'
else
  echo "- none; match the indentation and line length of neighboring files"
fi
for f in rustfmt.toml .rustfmt.toml; do [ -f "$f" ] && echo "- $f: $(tr '\n' ' ' < "$f" | cut -c1-200)"; done
for f in .prettierrc .prettierrc.json; do [ -f "$f" ] && echo "- $f: $(tr '\n' ' ' < "$f" | tr -s ' ' | cut -c1-200)"; done
toml_has 'line-length' && echo "- pyproject line-length: $(grep -m1 -E 'line-length' pyproject.toml)"

echo
echo "### License headers"
dirs=$( { [ -n "$mine" ] && echo "$mine" | xargs -n1 dirname; } | sort -u | head -6)
[ -z "$dirs" ] && dirs="."
for d in $dirs; do
  sample=$(echo "$all" | grep -E "^${d%/}/[^/]+\.[a-z]+$" | head -12)
  [ "$d" = "." ] && sample=$(echo "$all" | grep -v / | head -12)
  [ -z "$sample" ] && continue
  n=0; withh=0; first=""
  for f in $sample; do
    [ -f "$f" ] || continue; n=$((n+1))
    h=$(head -5 "$f" | grep -m1 -i -E 'SPDX-License-Identifier|copyright|licensed under')
    if [ -n "$h" ]; then withh=$((withh+1)); [ -z "$first" ] && first="$h"; fi
  done
  [ "$n" -gt 0 ] && echo "- \`$d\`: $withh of $n files start with a license header${first:+ (e.g. \`$(echo "$first" | cut -c1-100)\`)}"
done

echo
echo "### Commit subjects"
subj=$(git log -40 --no-merges --format=%s 2>/dev/null)
total=$(echo "$subj" | sed '/^$/d' | wc -l | tr -d ' ')
cc=$(echo "$subj" | grep -c -E '^[a-z]+(\([^)]+\))?!?: ')
area=$(echo "$subj" | grep -c -E '^[a-z0-9._/-]+: ')
brk=$(echo "$subj" | grep -c -E '^\[[^]]+\] ')
fixd=$(echo "$subj" | grep -c -E '^(Fixed|Refs) #[0-9]+ -- ')
echo "- of the last $total: conventional-commits $cc, 'area: subject' $area, '[area] subject' $brk, Django-style 'Fixed #N --' $fixd"
echo "$subj" | head -5 | sed 's/^/  - /'
grep -q -i -E 'signed-off-by|DCO' CONTRIBUTING* .github/*.md 2>/dev/null && echo "- sign-off required: commit with \`git commit -s\`"

echo
echo "### Changelog conventions"
if [ -d .changeset ]; then
  med=$(for f in $(ls .changeset/*.md 2>/dev/null | grep -v README); do sed '1,/^---$/d' "$f" | sed '1,/^---$/d' | wc -c; done | sort -n | awk '{a[NR]=$1} END {if (NR) print a[int((NR+1)/2)]}')
  echo "- changesets: add one under \`.changeset/\`${med:+ (median body of pending changesets: $med chars)}"
fi
for c in CHANGELOG.md CHANGES.md CHANGELOG HISTORY.md NEWS.md; do [ -f "$c" ] && echo "- \`$c\` at the root; check whether contributors edit it (recent merged PRs) or maintainers do at release"; done
true
