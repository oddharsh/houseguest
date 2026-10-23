#!/usr/bin/env bash
# Does what a report cites exist? Run it in the clone before reproducing anything.
#
#   cites.sh [--ref REF] (--issue N --repo owner/name | --file FILE)
#
# curl ended its bug bounty in 2026 after a flood of AI-written reports; one came with GDB
# sessions and register dumps for a function curl doesn't have. Checking what a report
# names is the cheapest test there is, so do it first. From the issue body (or FILE) it
# pulls the file paths, the functions and identifiers in backticks or followed by "(", and
# version numbers, then checks each against REF (default HEAD):
#   - a path exists (a bare file name may sit anywhere in the tree), and a :line is in range;
#   - an identifier appears as a whole word somewhere in the tree;
#   - a version has a tag.
# Paths outside the repo (node_modules, site-packages, absolute paths, URLs) are skipped.
# MISSING doesn't prove a report wrong: the reporter's own code, or another version, can
# hold it. It's the first question to answer. Exit 1 if anything is missing.

set -uo pipefail
ref="HEAD" issue="" repo="" file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) ref="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --file) file="$2"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "cites.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
git rev-parse --verify -q "$ref^{commit}" >/dev/null || { echo "cites.sh: run it in the clone; $ref isn't a commit here" >&2; exit 2; }
if [ -n "$file" ]; then text=$(cat "$file")
elif [ -n "$issue" ] && [ -n "$repo" ]; then text=$(gh issue view "$issue" -R "$repo" --json title,body --jq '.title + "\n" + .body') || { echo "cites.sh: couldn't read $repo#$issue" >&2; exit 2; }
else echo "cites.sh: pass --file, or --issue with --repo" >&2; exit 2; fi

tree=$(git ls-tree -r --name-only "$ref")
EXT='js|mjs|cjs|ts|tsx|jsx|vue|svelte|astro|py|pyi|rs|go|rb|java|kt|scala|c|h|cc|cpp|hpp|m|mm|zig|swift|php|cs|lua|ex|exs|sh|toml|ya?ml|json'
OUTSIDE='node_modules/|site-packages/|dist-packages/|^/|^[A-Za-z]:\\|://|^~'
missing=0 total=0
row() { total=$((total + 1)); [ "$1" = MISSING ] && missing=$((missing + 1)); echo "- $1 $2${3:+: $3}"; }

echo "# Cited in the report, checked at $(git rev-parse --short "$ref")"
echo
echo "## Files"
paths=$(printf '%s\n' "$text" | grep -o -E "[A-Za-z0-9_@./-]+\.($EXT)(:[0-9]+)?" | grep -v -E "$OUTSIDE" | sort -u)
if [ -z "$paths" ]; then echo "- none cited"; else
  while IFS= read -r p; do
    f=${p%%:*}; ln=""; [ "$f" != "$p" ] && ln=${p##*:}
    f=${f#./}
    hit=$(printf '%s\n' "$tree" | grep -x -F "$f" | head -1)
    [ -z "$hit" ] && hit=$(printf '%s\n' "$tree" | grep -E "(^|/)$(printf '%s' "$f" | sed 's/[.[\*^$]/\\&/g')$" | head -1)
    if [ -z "$hit" ]; then row MISSING "\`$p\`" "no such file in the tree"; continue; fi
    if [ -n "$ln" ]; then
      n=$(git show "$ref:$hit" 2>/dev/null | wc -l | tr -d ' ')
      if [ "$ln" -gt "$n" ]; then row MISSING "\`$p\`" "$hit has only $n lines"; continue; fi
    fi
    row FOUND "\`$p\`" "$hit"
  done <<< "$paths"
fi

echo
echo "## Functions and identifiers"
ids=$( { printf '%s\n' "$text" | grep -o -E '`[A-Za-z_][A-Za-z0-9_.:#]*(\(\))?`' | tr -d '`'
         printf '%s\n' "$text" | grep -o -E '\b[A-Za-z_][A-Za-z0-9_]*(\.|::)?[A-Za-z_][A-Za-z0-9_]*\(\)' ; } \
  | sed -E 's/\(\)$//' | grep -v -E "\.($EXT)$" | awk 'length($0) >= 4' | sort -u)
if [ -z "$ids" ]; then echo "- none cited"; else
  while IFS= read -r id; do
    leaf=$(printf '%s' "$id" | sed -E 's/.*(\.|::|#)//')
    [ ${#leaf} -ge 3 ] || continue
    if git grep -q -w -F -e "$leaf" "$ref" -- 2>/dev/null; then
      all=$(git grep -l -w -F -e "$leaf" "$ref" -- 2>/dev/null | sed "s#^$ref:##")
      where=$( { printf '%s\n' "$all" | grep -v -E '\.(md|rst|txt|adoc)$'; printf '%s\n' "$all"; } | sed '/^$/d' | head -1)
      row FOUND "\`$id\`" "$where"
    else
      row MISSING "\`$id\`" "the name \`$leaf\` appears nowhere in the tree"
    fi
  done <<< "$ids"
fi

echo
echo "## Versions"
vers=$(printf '%s\n' "$text" | grep -o -E '\bv?[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?\b' | sort -u)
tags=$(git tag -l 2>/dev/null)
if [ -z "$tags" ] && [ -n "$repo" ]; then tags=$(gh api "repos/$repo/tags?per_page=100" --jq '.[].name' 2>/dev/null); fi
if [ -z "$vers" ]; then echo "- none cited"
elif [ -z "$tags" ]; then echo "- couldn't list tags (shallow clone without tags; pass --repo to ask GitHub): $(echo $vers)"
else
  while IFS= read -r v; do
    b=${v#v}
    if printf '%s\n' "$tags" | grep -q -E "(^|[^0-9.])v?$(printf '%s' "$b" | sed 's/\./\\./g')$"; then row FOUND "$v" "tagged"
    else row MISSING "$v" "no tag ends in $b; check the package registry before assuming it doesn't exist"; fi
  done <<< "$vers"
fi

echo
echo "CITED: $total, MISSING: $missing"
[ "$missing" -eq 0 ]
