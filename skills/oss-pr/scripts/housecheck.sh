#!/usr/bin/env bash
# Check your branch against the repo's house rules before a maintainer does.
#
#   housecheck.sh [--base REF] [--full] [--fetch-tools]
#
# Runs the repo's own formatters and linters on only the files you changed (see
# house.sh), then diff-level checks that catch what review comments usually catch:
#   W  whitespace, final newlines, indentation style, line length
#   C  comments: narration, placement unlike the file's, density above the file's
#   S  structure: new public symbols, constants that already exist, removed guards,
#      test assertions the file doesn't use, formatting-only changes
#   K  changelog and commits: missing or long changesets, commit subject format
#   L  license headers that neighboring files carry
# FAIL items must be fixed. FLAG items must be fixed, or acknowledged with a reason
# in <ledger>/house-ack.md as "KEY: reason" (KEY is printed with each flag).
# --full also runs whole-project tools (clippy, tsc, golangci-lint).
# --fetch-tools lets npx download a JS formatter the repo hasn't installed.
# Writes <ledger>/house.md with STATUS: PASS | REVIEW | INCOMPLETE | FAIL and SHA.

set -uo pipefail
base="" full="" fetch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --full) full=1; shift ;;
    --fetch-tools) fetch=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "housecheck.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
git rev-parse --git-dir >/dev/null 2>&1 || { echo "housecheck.sh: run inside a clone" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)" || exit 2
here="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$base" ]; then
  for c in upstream/HEAD origin/HEAD upstream/main origin/main upstream/master origin/master; do
    git rev-parse --verify -q "$c" >/dev/null && { base="$c"; break; }
  done
fi
[ -n "$base" ] || { echo "housecheck.sh: pass --base <ref>" >&2; exit 2; }
mb=$(git merge-base "$base" HEAD) || { echo "housecheck.sh: no merge-base with $base" >&2; exit 2; }
head_sha=$(git rev-parse HEAD)
branch=$(git branch --show-current); [ -n "$branch" ] || branch="detached-${head_sha:0:8}"
ledger="$(git rev-parse --git-dir)/houseguest/$branch"; mkdir -p "$ledger"
ack="$ledger/house-ack.md"; [ -f "$ack" ] || : > "$ack"
tmp=$(mktemp -d); trap '[ -n "${HOUSE_DEBUG:-}" ] && cp -R "$tmp" "$HOUSE_DEBUG"; rm -rf "$tmp"' EXIT

GEN_RE='(^|/)(__snapshots__|dist|build|vendor|third_party|node_modules|generated|gen)/|\.snap$|\.min\.[a-z]+$|(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock|Cargo\.lock|go\.sum|poetry\.lock|uv\.lock|Gemfile\.lock|bun\.lockb?)$'
changed=$(git diff --name-only --diff-filter=ACMR "$mb" HEAD | grep -v -E "$GEN_RE" | while IFS= read -r f; do [ -f "$f" ] && head -5 "$f" | grep -q -E '@generated|DO NOT EDIT|auto-?generated' && continue; echo "$f"; done)
added_files=$(git diff --name-only --diff-filter=A "$mb" HEAD)
alladded=$(git diff -U0 "$mb" HEAD | grep -E '^\+[^+]' | sed 's/^+//')   # every added line, any file
[ -n "$changed" ] || { echo "housecheck.sh: no changes against $base"; exit 0; }

: > "$tmp/out"; fails=0; flags=0; acked=0; notrun=0
key() { printf '%s:%s:%s' "$1" "$2" "$(printf '%s' "$3" | cksum | cut -d' ' -f1)"; }
# A removed guard can only be acked by a test in this diff that fails with the guard
# in place. Neighbors that don't guard are no reason: reviewers ask for the check back anyway.
ack_ok() {  # ack_ok CODE REASON
  [ "$1" = S3 ] || return 0
  local t; for t in $changed; do is_test "$t" && case "$2" in *"$t"*) return 0 ;; esac; done
  return 1
}
emit() {  # emit LEVEL CODE FILE MESSAGE
  local k r; k=$(key "$2" "$3" "$4")
  r=$(grep -m1 -F "$k:" "$ack" | sed "s/^[^ ]*: *//")
  case "$1" in
    FAIL) fails=$((fails+1)); printf -- '- **FAIL** %s `%s`: %s\n' "$2" "$3" "$4" >> "$tmp/out" ;;
    FLAG)
      if [ -n "$r" ] && ! ack_ok "$2" "$r"; then fails=$((fails+1)); printf -- '- **FAIL** %s `%s`: %s. The ack in house-ack.md names no test from your diff that fails with the condition wrapping your new code, so restore the condition\n' "$2" "$3" "$4" >> "$tmp/out"
      elif [ -n "$r" ]; then acked=$((acked+1)); printf -- '- acked %s `%s`: %s (%s)\n' "$2" "$3" "$4" "$r" >> "$tmp/out"
      else flags=$((flags+1)); printf -- '- **FLAG** %s `%s`: %s  \n  key `%s`\n' "$2" "$3" "$4" "$k" >> "$tmp/out"; fi ;;
    NOTRUN) notrun=$((notrun+1)); printf -- '- **NOT RUN** %s: %s\n' "$2" "$4" >> "$tmp/out" ;;
    OK) printf -- '- ok %s: %s\n' "$2" "$4" >> "$tmp/out" ;;
  esac
}
ext_of() { echo "${1##*.}" | tr 'A-Z' 'a-z'; }
csyn() {  # comment syntax for a file: "//", "#", "--", or ""
  case "$(ext_of "$1")" in
    js|jsx|ts|tsx|mjs|cjs|mts|cts|rs|go|c|h|cc|cpp|cxx|hpp|hh|java|kt|kts|swift|zig|scala|cs|dart|m|mm|php|css|scss) echo "//" ;;
    py|pyi|rb|sh|bash|zsh|yml|yaml|toml|pl|r|ex|exs|nix|cmake|mk|make|dockerfile|conf|ini|gd) echo "#" ;;
    lua|sql|hs|elm) echo "--" ;;
    *) case "$(basename "$1")" in Makefile|Dockerfile|*.mk) echo "#" ;; *) echo "" ;; esac ;;
  esac
}
is_test() { echo "$1" | grep -q -E '(^|/)(tests?|__tests__|spec|testdata)/|[._-](test|spec)\.[a-z]+$|_test\.(go|py|rs)$|(^|/)test_[^/]+\.py$'; }
# added lines of a file as "lineno<TAB>text"
added() { git diff -U0 "$mb" HEAD -- "$1" | awk '/^@@/{split($3,a,","); n=substr(a[1],2)+0; next} /^\+\+\+/{next} /^\+/{print n "\t" substr($0,2); n++}'; }
removed() { git diff -U0 "$mb" HEAD -- "$1" | awk '/^---/{next} /^-/{print substr($0,2)}'; }

# --- Tools: the repo's own formatters and linters --------------------------------
toolfiles() {  # toolfiles <tool>: changed files that tool understands
  local re
  case "$1" in
    prettier|biome|dprint|deno) re='js|jsx|ts|tsx|mjs|cjs|mts|cts|json|jsonc|css|scss|md|mdx|yml|yaml|html|vue|svelte|astro' ;;
    eslint|oxlint) re='js|jsx|ts|tsx|mjs|cjs|mts|cts|vue|svelte' ;;
    gofmt) re='go' ;; ruff|black|isort|flake8|mypy) re='py|pyi' ;; zig-fmt) re='zig' ;;
    clang-format) re='c|h|cc|cpp|cxx|hpp|hh|m|mm' ;; swift-format|swiftlint) re='swift' ;;
    rubocop) re='rb' ;; ktlint) re='kt|kts' ;; markdownlint) re='md|mdx' ;; *) re='.*' ;;
  esac
  for f in $changed; do [ -f "$f" ] && echo "$f" | grep -q -i -E "\.($re)$" && printf '%s ' "$f"; done
}
bash "$here/house.sh" --machine --files "$(echo "$changed" | tr '\n' ',')" > "$tmp/tools"
cfg_width=$(awk -F'\t' '$1=="LINEWIDTH"{print $2}' "$tmp/tools"); sed -i.bak '/^LINEWIDTH	/d' "$tmp/tools"
# Which toolchain each Rust tool runs on, and why (house.sh resolves it from the CI job running it).
toolchain_note=$(awk -F'\t' '$1=="TOOLCHAINNOTE"{print $2}' "$tmp/tools"); sed -i.bak '/^TOOLCHAINNOTE	/d' "$tmp/tools"
owned=""   # files a configured formatter owns: width and indentation are its job
while IFS=$'\t' read -r name cmd; do
  case "$name" in prettier|oxfmt|biome|dprint|deno|rustfmt|gofmt|ruff|black|zig-fmt|clang-format|swift-format|rubocop|ktlint) owned="$owned $(toolfiles "$name")" ;; esac
  [ "$name" = rustfmt ] && owned="$owned $(for f in $changed; do case "$f" in (*.rs) printf '%s ' "$f" ;; esac; done)"
done < "$tmp/tools"
if [ ! -s "$tmp/tools" ]; then emit OK T0 "" "the repo configures no formatter or linter for these files; conventions and defaults.md apply"; fi
while IFS=$'\t' read -r name cmd; do
  [ -z "$name" ] && continue
  case "$name" in clippy|tsc|golangci-lint) [ -z "$full" ] && { emit NOTRUN "T:$name" "" "whole-project check; rerun with --full before opening the PR"; continue; } ;; esac
  fl=$(toolfiles "$name"); [ -z "$fl" ] && continue
  run=$(echo "$cmd" | sed "s#{FILES}#$fl#g")
  bin=$(echo "$run" | awk '{print $1}')
  if [ "$bin" = "npx" ] && [ -n "$fetch" ]; then run=$(echo "$run" | sed 's/npx --no-install /npx -y /')
  elif [ "$bin" = "npx" ] && ! npx --no-install "$(echo "$run" | awk '{print $3}')" --version >/dev/null 2>&1; then emit NOTRUN "T:$name" "" "not installed here; install the repo's dev dependencies (or pass --fetch-tools) and rerun"; continue
  elif { [ "$bin" = "pnpm" ] || [ "$bin" = "yarn" ]; } && [ ! -x "node_modules/.bin/$(echo "$run" | awk '{print ($1=="pnpm") ? $3 : $2}')" ]; then emit NOTRUN "T:$name" "" "not installed here; run the repo's install (pnpm install / yarn) and rerun"; continue
  elif [ "$bin" != "npx" ] && [ "$bin" != "pnpm" ] && [ "$bin" != "yarn" ] && ! command -v "$bin" >/dev/null 2>&1 && [ ! -x "$bin" ]; then emit NOTRUN "T:$name" "" "\`$bin\` isn't installed; install it and rerun"; continue; fi
  if out=$(bash -c "$run" 2>&1); then emit OK "T:$name" "" "\`$(echo "$run" | cut -c1-90)\` clean"
  else
    # gofmt -l lists files instead of failing
    # A toolchain that differs from CI's can fail code CI accepts (lints come and go between releases).
    drift=$(echo "$toolchain_note" | grep -E "^$name: " | grep -o 'DRIFT: .*' | sed 's/^DRIFT: //')
    emit FAIL "T:$name" "" "\`$(echo "$run" | cut -c1-90)\` reported: $(echo "$out" | tail -8 | tr '\n' ' ' | cut -c1-300)${drift:+. This may differ from CI because $drift; rerun on the CI toolchain before treating it as a problem in your code}"
  fi
  [ "$name" = "gofmt" ] && [ -n "${out:-}" ] && emit FAIL "T:gofmt" "" "unformatted: $out"
done < "$tmp/tools"

# --- W: whitespace -------------------------------------------------------------
dc=$(git diff --check "$mb" HEAD 2>&1 | head -12)
if [ -n "$dc" ]; then emit FAIL W1 "(diff)" "whitespace errors: $(echo "$dc" | tr '\n' ' ' | cut -c1-240)"; else emit OK W1 "" "no whitespace errors"; fi
maxlen=""
[ -f .editorconfig ] && maxlen=$(grep -m1 -E '^max_line_length *= *[0-9]+' .editorconfig | grep -o '[0-9]*')
for f in $changed; do
  [ -f "$f" ] || continue
  if [ -s "$f" ] && [ "$(tail -c1 "$f" | od -An -c | tr -d ' ')" != '\n' ]; then
    git show "$mb:$f" >/dev/null 2>&1 && [ "$(git show "$mb:$f" | tail -c1 | od -An -c | tr -d ' ')" != '\n' ] || emit FLAG W2 "$f" "no final newline"
  fi
  a=$(added "$f"); [ -z "$a" ] && continue
  case " $owned " in *" $f "*) continue ;; esac
  if git show "$mb:$f" >/dev/null 2>&1; then
    tabs=$(git show "$mb:$f" | grep -c $'^\t'); spaces=$(git show "$mb:$f" | grep -c '^  ')
    if [ "$spaces" -gt $((tabs * 4 + 5)) ] && echo "$a" | cut -f2- | grep -q $'^\t'; then emit FLAG W3 "$f" "tab-indented lines in a space-indented file"; fi
    if [ "$tabs" -gt $((spaces * 4 + 5)) ] && echo "$a" | cut -f2- | grep -q '^  [^ *]'; then emit FLAG W3 "$f" "space-indented lines in a tab-indented file"; fi
  fi
  lim="${cfg_width:-$maxlen}"
  if [ -z "$lim" ] && git show "$mb:$f" >/dev/null 2>&1; then
    # infer the file's own limit: the 99th-percentile line length, if lines cluster under a round number
    p99=$(git show "$mb:$f" | awk '{print length($0)}' | sort -n | awk '{a[NR]=$1} END{if(NR>40) print a[int(NR*0.99)]}')
    for r in 80 88 100 120; do [ -n "$p99" ] && [ "$p99" -le "$r" ] && [ "$p99" -gt $((r - 12)) ] && { lim=$r; break; }; done
  fi
  if [ -n "$lim" ]; then
    long=$(echo "$a" | awk -F'\t' -v L="$lim" 'length(substr($0, index($0,"\t")+1)) > L {print $1}' | head -5 | tr '\n' ',')
    [ -n "$long" ] && emit FLAG W4 "$f" "lines over the file's ${lim}-column width at ${long%,}"
  fi
done

# --- C: comments ------------------------------------------------------------------
NARR='^(now|added|adds|add|updated|update|changed|change|fixed|fix(es)?( for)?|new|this (function|method|code|block|line|change)|here we|we now|increment|decrement|loop (over|through)|iterate (over|through)|set the|get the|call the|return the|check if|initiali[sz]e the|import|helper (function|method)?)\b'
for f in $changed; do
  [ -f "$f" ] || continue
  s=$(csyn "$f"); [ -z "$s" ] && continue
  a=$(added "$f"); [ -z "$a" ] && continue
  esc=$(printf '%s' "$s" | sed 's#/#\\/#g')
  full_new=$(echo "$a" | cut -f2- | grep -c -E "^[[:space:]]*$s")
  trail_new=$(echo "$a" | cut -f2- | grep -v -E "^[[:space:]]*$s" | grep -c -E "[^:\"'][[:space:]]+$s[[:space:]]")
  code_new=$(echo "$a" | cut -f2- | grep -v -E "^[[:space:]]*($s|$)" | wc -l | tr -d ' ')
  echo "$a" | while IFS=$'\t' read -r ln text; do
    body=$(printf '%s\n' "$text" | awk -v s="$s" '{ sub(/^[[:space:]]*/, ""); while (index($0, s) == 1) $0 = substr($0, length(s) + 1); sub(/^!?[[:space:]]*/, ""); print }')
    echo "$text" | grep -q -E "^[[:space:]]*$s" || continue
    echo "$body" | grep -q -i -E "$NARR" && echo "C1	$ln	narrating comment: \"$(echo "$body" | cut -c1-80)\""
    echo "$body" | grep -q -i -E '(per|from) (the )?(review|issue|discussion|conversation|chat)|as (discussed|requested|suggested)|(claude|chatgpt|copilot|llm|the ai)\b' && echo "C1	$ln	comment refers to the conversation or tooling: \"$(echo "$body" | cut -c1-80)\""
  done > "$tmp/c1"
  while IFS=$'\t' read -r code ln msg; do [ -n "$code" ] && emit FLAG "$code" "$f:$ln" "$msg"; done < "$tmp/c1"
  # C4: a comment block sitting above a multi-line list whose items it explains
  echo "$a" | awk -F'\t' -v s="$s" '
    { t=$0; sub(/^[^\t]*\t/, "", t); u=t; sub(/^[[:space:]]+/, "", u) }
    index(u, s) == 1 { if (run == 0) start=$1; run++; next }
    run >= 2 && u ~ /\[[[:space:]]*$/ && u !~ /^(for|if|while|switch|match|fn|def|function)[[:space:](]/ { open=1; items=0; from=start; n=run; run=0; next }
    open && u ~ /^["'"'"'A-Za-z0-9_.-]/ { items++; next }
    open && u ~ /^[\]\)\}]/ { if (items >= 2) print from "\t" n "\t" items; open=0; next }
    { run=0 }' > "$tmp/c4"
  while IFS=$'\t' read -r ln n items; do [ -n "$ln" ] && emit FLAG C4 "$f:$ln" "a ${n}-line comment sits above a list of ${items} items; put each part of it above the item it explains"; done < "$tmp/c4"
  if git show "$mb:$f" >/dev/null 2>&1; then
    old=$(git show "$mb:$f")
    full_old=$(echo "$old" | grep -c -E "^[[:space:]]*$s")
    trail_old=$(echo "$old" | grep -v -E "^[[:space:]]*$s" | grep -c -E "[^:\"'][[:space:]]+$s[[:space:]]")
    code_old=$(echo "$old" | grep -v -E "^[[:space:]]*($s|$)" | wc -l | tr -d ' ')
    if [ "$trail_new" -gt 0 ] && [ $((full_old)) -ge 10 ] && [ $((trail_old * 10)) -lt "$full_old" ]; then
      emit FLAG C2 "$f" "$trail_new trailing comment(s) added; this file puts comments on their own line ($full_old own-line vs $trail_old trailing)"
    fi
    if [ "$code_new" -ge 3 ] && [ "$code_old" -ge 20 ]; then
      new_pct=$(( (full_new + trail_new) * 100 / code_new )); old_pct=$(( (full_old + trail_old) * 100 / code_old ))
      [ "$new_pct" -gt $(( old_pct * 2 + 10 )) ] && [ $((full_new + trail_new)) -ge 5 ] && emit FLAG C3 "$f" "you added ${new_pct} comment lines per 100 lines of code; this file has ${old_pct}. Keep the ones a reader needs"
    fi
  fi
done

# --- S: structure -----------------------------------------------------------------
for f in $changed; do
  [ -f "$f" ] || continue
  a=$(added "$f"); r=$(removed "$f")
  case "$(ext_of "$f")" in
    js|jsx|ts|tsx|mjs|cjs|mts|cts) pub='^[[:space:]]*export[[:space:]]+(default[[:space:]]+)?(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+([A-Za-z0-9_$]+)' ;;
    rs) pub='^[[:space:]]*pub[[:space:]]+(async[[:space:]]+)?(fn|struct|enum|trait|type|const|static|mod)[[:space:]]+([A-Za-z0-9_]+)' ;;
    go) pub='^func[[:space:]]+(\([^)]*\)[[:space:]]*)?[A-Z][A-Za-z0-9_]*|^type[[:space:]]+[A-Z]' ;;
    py) pub='^(def|class)[[:space:]]+[A-Za-z][A-Za-z0-9_]*' ;;
    swift) pub='^[[:space:]]*(public|open)[[:space:]]+' ;;
    zig) pub='^[[:space:]]*pub[[:space:]]+(fn|const|var)' ;;
    *) pub='' ;;
  esac
  if [ -n "$pub" ] && ! is_test "$f"; then
    echo "$a" | cut -f2- | grep -E "$pub" | grep -v -F -x -f <(echo "$r") | head -4 | while IFS= read -r l; do
      sym=$(echo "$l" | grep -o -E '(function|const|let|class|type|interface|enum|fn|struct|trait|mod|static|def|var)[[:space:]]+[A-Za-z0-9_$]+' | head -1 | awk '{print $2}')
      [ -n "$sym" ] && git show "$mb:$f" 2>/dev/null | grep -q -w -- "$sym" && continue
      echo "S1	new public symbol: \`$(echo "$l" | sed 's/^[[:space:]]*//' | cut -c1-90)\`. Check how neighbors expose things (an inline option type, an internal helper) before making it public"
    done > "$tmp/s1"
    while IFS=$'\t' read -r code msg; do [ -n "$code" ] && emit FLAG "$code" "$f" "$msg"; done < "$tmp/s1"
  fi
  echo "$a" | cut -f2- | grep -o -E '(^|[^A-Za-z0-9_.])(const|let|var|static|pub const|final)?[[:space:]]*[A-Z][A-Z0-9_]{3,}[[:space:]]*(:[^=]+)?=[^=>]' \
    | grep -o -E '[A-Z][A-Z0-9_]{3,}' | sort -u | while IFS= read -r name; do
      where=$(git grep -l -w -E "(const|let|var|static|final|pub const|def)?[[:space:]]*$name[[:space:]]*(:[^=]*)?=" "$mb" -- . 2>/dev/null | sed "s#^$mb:##" | grep -v -x -F "$f" | head -2 | tr '\n' ' ')
      [ -n "$where" ] && echo "S2	\`$name\` is already defined in $where; import it instead of redefining"
    done > "$tmp/s2"
  while IFS=$'\t' read -r code msg; do [ -n "$code" ] && emit FLAG "$code" "$f" "$msg"; done < "$tmp/s2"
  # Removed guards. A condition that reappears anywhere in the diff moved (into another function or
  # file) and stays; an `if` whose condition changed in place is the change itself, noted with both
  # versions. Only a condition that's gone everywhere is flagged.
  changed_ifs=$(git diff -U0 "$mb" HEAD -- "$f" | awk '
    function isg(s) { return s ~ /^[ \t]*(\}[ \t]*)?(else[ \t]+)?(if|elif|guard|unless)([ \t(]|$)/ }
    function ind(s) { match(s, /^[ \t]*/); return RLENGTH }
    function flush(  i, j) { for (i = 1; i <= nr; i++) if (isg(rm[i])) for (j = 1; j <= na; j++) if (isg(ad[j]) && !used[j] && ind(rm[i]) == ind(ad[j])) { print rm[i] "\t" ad[j]; used[j] = 1; break }
                             nr = 0; na = 0; split("", rm); split("", ad); split("", used) }
    /^@@/ { flush(); next } /^---|^\+\+\+/ { next }
    /^-/ { rm[++nr] = substr($0, 2) } /^\+/ { ad[++na] = substr($0, 2) }
    END { flush() }')
  [ -n "$changed_ifs" ] && echo "$changed_ifs" | head -3 | while IFS=$'\t' read -r o n; do
    emit OK S3 "$f" "\`$f\` condition changed: \`$(echo "$o" | sed 's/^[[:space:]]*//' | cut -c1-80)\` became \`$(echo "$n" | sed 's/^[[:space:]]*//' | cut -c1-80)\`; say why in the PR if it isn't the point of the change"
  done
  guards=$(echo "$r" | grep -E '^[[:space:]]*(if|guard|unless|elif|else if|} else if)\b|^[[:space:]]*if[[:space:]]*\(' | grep -v -F -x -f <(echo "$a" | cut -f2-) | while IFS= read -r g; do
    [ -n "$changed_ifs" ] && echo "$changed_ifs" | cut -f1 | grep -q -x -F -- "$g" && continue
    cond=$(echo "$g" | sed -E 's/^[[:space:]]*(\}[[:space:]]*)?(else[[:space:]]+)?(if|elif|guard|unless)[[:space:]]*\(?//; s/\)?[[:space:]]*(\{|:|then|return.*)?[[:space:]]*$//' | cut -c1-60)
    [ -n "$cond" ] && echo "$alladded" | grep -q -F -- "$cond" && continue
    echo "$g"
  done | head -3)
  [ -n "$guards" ] && emit FLAG S3 "$f" "removed condition(s): $(echo "$guards" | sed 's/^[[:space:]]*//' | tr '\n' ' ' | cut -c1-160). Restore the condition around your new code (the old body may be gone; the check stays). Only a test in your diff that fails with that condition wrapping your new code justifies dropping it; name it in the ack"
  if is_test "$f" && git show "$mb:$f" >/dev/null 2>&1; then
    forms() { grep -o -E '\.(to[A-Z][A-Za-z]+|matchSnapshot|toMatchInlineSnapshot)\(|\bassert\.[a-z][A-Za-z_]*\(|\bassert(_eq|_ne|_matches)?!\(|\bself\.assert[A-Z][A-Za-z]*\(|\bt\.(Errorf|Fatalf|Error|Fatal)\(|\brequire\.[A-Z][A-Za-z]*\(|\bassert[A-Z][A-Za-z]*\(|\bexpect\(.*\)\.to\.[a-z]+' | sed -E 's/\($//' | sort -u; }
    new=$(echo "$a" | cut -f2- | forms); old=$(git show "$mb:$f" | forms)
    if [ -n "$old" ]; then
      novel=$(comm -23 <(echo "$new") <(echo "$old") | tr '\n' ' ')
      top=$(git show "$mb:$f" | grep -o -E '\.(to[A-Z][A-Za-z]+|matchSnapshot)\(|\bassert\.[a-z][A-Za-z_]*\(|\bassert(_eq|_ne)?!\(|\bself\.assert[A-Z][A-Za-z]*\(' | sed 's/($//' | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s (%d) ", $2, $1}')
      dir_old=$(for s in $(git ls-tree --name-only "$mb" "$(dirname "$f")/" | grep -E '[._-](test|spec)\.[a-z]+$|_test\.(go|py|rs)$|/test_[^/]+\.py$'); do git show "$mb:$s" 2>/dev/null; done | forms)
      novel_dir=$(comm -23 <(echo "$new") <(echo "$dir_old") | tr '\n' ' ')
      [ -n "${novel// /}" ] && emit FLAG S4 "$f" "assertions this file doesn't use elsewhere: ${novel}. Its usual ones: ${top}. Mirror the tests that exercise the same function"
      [ -z "${novel// /}" ] && [ -n "${novel_dir// /}" ] && emit FLAG S4 "$f" "assertions no test in $(dirname "$f")/ uses: ${novel_dir}"
    fi
  fi
  if git show "$mb:$f" >/dev/null 2>&1 && [ -z "$(git diff -w --ignore-blank-lines "$mb" HEAD -- "$f")" ]; then
    emit FLAG S5 "$f" "formatting-only change; revert it unless the formatter requires it"
  fi
done

# S2b: a literal list repeated where a named constant already holds it
for f in $changed; do added "$f" | sed "s#^#$f	#"; done | awk -F'\t' '
  function strs(s,   out) { out=""; while (match(s, /"[^"]*"|'"'"'[^'"'"']*'"'"'/)) { out=out substr(s, RSTART+1, RLENGTH-2) "\034"; s=substr(s, RSTART+RLENGTH) } return out }
  {
    file=$1; ln=$2; text=$0; sub(/^[^\t]*\t[^\t]*\t/, "", text)
    if (name != "" && file == nfile) { list=list strs(text); if (text ~ /[\]\)}]/) { print "N\t" nfile "\t" name "\t" list; name="" }; next }
    if (match(text, /[A-Z][A-Z0-9_][A-Z0-9_]+[[:space:]]*(:[^=]*)?=[[:space:]]*[\[\(\{]/)) {
      name=substr(text, RSTART); sub(/[[:space:]:=].*/, "", name); nfile=file; list=strs(text)
      if (text ~ /[\]\)}][[:space:]]*(as const)?[;,]?[[:space:]]*$/ && list != "") { print "N\t" nfile "\t" name "\t" list; name="" }
      next
    }
    s=strs(text); n=gsub(/\034/, "\034", s); if (n >= 3) print "I\t" file ":" ln "\t-\t" s
  }' | while IFS=$'\t' read -r kind loc nm lst; do
    printf '%s\t%s\t%s\t%s\n' "$kind" "$loc" "$nm" "$(printf '%s' "$lst" | tr '\034' '\n' | sed '/^$/d' | sort -u | tr '\n' '|')"
  done > "$tmp/lists"
awk -F'\t' '$1=="N"{n[$4]=$3" in "$2} $1=="I"{i[NR]=$0} END{for (k in i){split(i[k],p,"\t"); if (p[4] in n) print p[2] "\t" n[p[4]]}}' "$tmp/lists" | while IFS=$'\t' read -r loc named; do
  emit FLAG S2 "$loc" "inline list repeats the one named $named; import and reuse it"
done

# --- K: changelog and commits ---------------------------------------------------------
if git ls-tree -d "$mb" .changeset >/dev/null 2>&1 && [ -n "$(git ls-tree "$mb" .changeset/)" ]; then
  mine_cs=$(echo "$added_files" | grep -E '^\.changeset/[^/]+\.md$' | grep -v README)
  if [ -z "$mine_cs" ]; then emit FLAG K1 ".changeset" "no changeset added; this repo uses changesets"
  else
    med=$(git log -60 --diff-filter=A --name-only --format= "$mb" -- .changeset/ | grep -E '\.md$' | grep -v README | sort -u | head -40 | while read -r c; do
      git log -1 --format=%H --diff-filter=A -- "$c" | xargs -I{} git show "{}:$c" 2>/dev/null | awk 'BEGIN{d=0} /^---$/{d++; next} d>=2' | wc -c; done | sort -n | awk '{a[NR]=$1} END{if(NR) print a[int((NR+1)/2)]}')
    for c in $mine_cs; do
      n=$(awk 'BEGIN{d=0} /^---$/{d++; next} d>=2' "$c" | wc -c | tr -d ' ')
      if [ -n "$med" ] && [ "$med" -gt 0 ] && [ "$n" -gt $((med * 2)) ]; then emit FLAG K1 "$c" "changeset body is $n chars; the repo's recent ones run about $med. Keep the essentials"
      else emit OK K1 "" "changeset present ($n chars${med:+, repo median $med})"; fi
    done
  fi
fi
subj=$(git log -60 --no-merges --format=%s "$mb")
tot=$(echo "$subj" | sed '/^$/d' | wc -l | tr -d ' ')
pat=""
for p in '^[a-z]+(\([^)]+\))?!?: ' '^[a-z0-9._/-]+: ' '^\[[^]]+\] ' '^(Fixed|Refs) #[0-9]+ -- '; do
  n=$(echo "$subj" | grep -c -E "$p"); [ "$tot" -gt 10 ] && [ $((n * 10)) -ge $((tot * 6)) ] && { pat="$p"; break; }
done
if [ -n "$pat" ]; then
  git log --no-merges --format=%s "$mb..HEAD" | while IFS= read -r s; do echo "$s" | grep -q -E "$pat" || echo "K2	commit \"$(echo "$s" | cut -c1-80)\" doesn't follow the repo's subject pattern \`$pat\`"; done > "$tmp/k2"
  while IFS=$'\t' read -r code msg; do [ -n "$code" ] && emit FLAG "$code" "(commits)" "$msg"; done < "$tmp/k2"
fi

# --- L: license headers ---------------------------------------------------------------
for f in $added_files; do
  [ -f "$f" ] || continue; d=$(dirname "$f"); e=$(ext_of "$f")
  sib=$(git ls-tree --name-only "$mb" "$d/" 2>/dev/null | grep -E "\.$e$" | head -12)
  n=0; h=0
  for s in $sib; do n=$((n+1)); git show "$mb:$s" 2>/dev/null | head -5 | grep -q -i -E 'SPDX-License-Identifier|copyright|licensed under' && h=$((h+1)); done
  if [ "$n" -ge 3 ] && [ $((h * 10)) -ge $((n * 8)) ] && ! head -5 "$f" | grep -q -i -E 'SPDX-License-Identifier|copyright|licensed under'; then
    emit FLAG L1 "$f" "$h of $n neighboring .$e files open with a license header; this new file doesn't"
  fi
done

# --- Report -----------------------------------------------------------------------------
if [ "$fails" -gt 0 ]; then status="FAIL ($fails to fix)"
elif [ "$notrun" -gt 0 ]; then status="INCOMPLETE ($notrun check(s) not run)"
elif [ "$flags" -gt 0 ]; then status="REVIEW ($flags flag(s) to fix or acknowledge)"
else status="PASS"; fi
{
  echo "# House rules check: $branch"
  echo "STATUS: $status"
  echo "SHA: $head_sha"
  echo "BASE: $base ($(git rev-parse --short "$mb"))"
  [ -n "$toolchain_note" ] && echo "$toolchain_note" | sed 's/^/Toolchain: /'
  echo
  echo "Files: $(echo "$changed" | tr '\n' ' ')"
  echo
  cat "$tmp/out"
  [ "$acked" -gt 0 ] && echo && echo "$acked flag(s) acknowledged in house-ack.md."
  echo
  echo "To acknowledge a flag you've decided to keep, add a line to $ack: \`KEY: why this is right for this repo\`."
} > "$ledger/house.md"
cat "$ledger/house.md"
case "$status" in PASS) exit 0 ;; *) exit 1 ;; esac
