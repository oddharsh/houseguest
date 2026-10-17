#!/usr/bin/env bash
# Check PR titles against the repo's own title conventions.
#
#   title.sh --repo owner/name [--as-of DATE] [--stats FILE] [--save FILE] "<title>" ["<title>"...]
#
# Learns the house style from up to 100 merged PRs by other people (bots and
# release PRs left out): prefix pattern, length, and how often titles use each
# feature below. A feature in your title that the repo's titles rarely use is
# flagged, because that's what makes a title read as foreign:
#   prefix pattern, length past the repo's 90th percentile, commas, semicolons,
#   ", as ..." clauses, comparisons to other products, "not"/"instead" contrasts,
#   parentheses, quotes, a colon mid-title, a trailing period, em dashes.
# Prints the conventions, then FLAG lines per title. Exit 1 if anything is flagged.
# --save writes the learned conventions as JSON; --stats reuses them offline.

set -uo pipefail
repo="" asof="" stats="" save=""
titles=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --as-of) asof="$2"; shift 2 ;;
    --stats) stats="$2"; shift 2 ;;
    --save) save="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) titles+=("$1"); shift ;;
  esac
done

# Feature name, regex (jq/Oniguruma, case-insensitive), and what to tell the writer.
FEATURES='[
 ["comma",       ",",                                            "commas, so it reads as several clauses"],
 ["two_commas",  ",[^,]*,",                                     "two or more commas"],
 ["semicolon",   ";",                                            "a semicolon"],
 ["as_clause",   ", as |\\bas [a-z]+ as\\b",                   "an \"as ...\" clause or comparison"],
 ["compares",    "\\b(as in|like|than|as [a-z]+ as) [A-Z][A-Za-z]+", "a comparison to another product or project"],
 ["negation",    ", not |\\bnot [a-z]+ (anew|again|each time)\\b", "a \", not X\" contrast"],
 ["instead",     "\\binstead of\\b|\\brather than\\b",      "an \"instead of\" contrast"],
 ["parens",      "(?<![A-Za-z0-9_])\\((?!#?[0-9]+\\))",     "a parenthetical"],
 ["quotes",      "[\"\u201c\u201d]",                            "quotation marks"],
 ["mid_colon",   "^[^:]{25,}: ",                                 "a colon after a long lead-in"],
 ["period",      "\\.$",                                         "a trailing period"],
 ["emdash",      "\u2014",                                       "an em dash"]
]'
PREFIXES='[
 ["conventional", "^[a-z]+(\\([^)]+\\))?!?: "],
 ["bracket_area", "^\\[[^\\]]+\\] "],
 ["area_colon",   "^[A-Za-z0-9._/-]+: "],
 ["django_fixed", "^(Fixed|Refs) #[0-9]+ -- "]
]'

if [ -n "$stats" ]; then
  conv=$(cat "$stats")
else
  [ -n "$repo" ] || { echo "title.sh: --repo or --stats is required" >&2; exit 2; }
  me=$(gh api user --jq .login 2>/dev/null)
  q="is:merged"
  if [ -n "$asof" ]; then
    asof_ts="$asof"; [ "${asof#*T}" = "$asof" ] && asof_ts="${asof}T00:00:00Z"
    q="$q merged:<$asof_ts"
  fi
  raw=$(gh pr list -R "$repo" --state merged --search "$q" --limit 100 --json title,author 2>/dev/null)
  conv=$(echo "$raw" | jq --arg me "$me" --argjson F "$FEATURES" --argjson P "$PREFIXES" '
    [.[] | select((.author.is_bot // false) | not)
         | select((.author.login // "") | test("\\[bot\\]$|^app/|dependabot|renovate|github-actions|changeset|release-please"; "i") | not)
         | select(.author.login != $me)
         | .title | sub(" \\(#[0-9]+\\)$"; "")
         | select(test("^(Version Packages|chore\\(release\\)|Release v?[0-9])"; "i") | not)] as $t
    | ($t | length) as $n
    | if $n == 0 then {n: 0} else
      { n: $n,
        median_words: ([$t[] | split(" ") | length] | sort | .[length/2|floor]),
        p90_words: ([$t[] | split(" ") | length] | sort | .[(length*0.9)|floor]),
        prefix: ([$P[] | . as $p | {name: $p[0], rx: $p[1], share: (([$t[] | select(test($p[1]))] | length) / $n)}] | max_by(.share)),
        rates: ([$F[] | . as $f | {key: $f[0], value: (([$t[] | select(test($f[1]))] | length) / $n)}] | from_entries),
        examples: $t[:8] } end')
fi
[ -n "$save" ] && echo "$conv" > "$save"

n=$(echo "$conv" | jq -r '.n')
if [ "$n" = "0" ] || [ -z "$n" ]; then echo "title.sh: couldn't learn title conventions (no merged PRs by others, or the lookup failed); check the title by hand against the repo's commit subjects" >&2; exit 2; fi
echo "$conv" | jq -r '
  "Title conventions from \(.n) merged PRs by others: median \(.median_words) words, 90th percentile \(.p90_words).",
  (if .prefix.share >= 0.6 then "Prefix: \(.prefix.name) in \((.prefix.share*100)|floor)% of titles." else "Prefix: none dominant (top is \(.prefix.name) at \((.prefix.share*100)|floor)%)." end),
  "Examples:", (.examples[] | "  - \(.)")'

flagged=0
for t in ${titles[@]+"${titles[@]}"}; do
  out=$(echo "$conv" | jq -r --arg t "$t" --argjson F "$FEATURES" '
    . as $c
    | ($t | split(" ") | length) as $w
    | [ (if $c.prefix.share >= 0.6 and ($t | test($c.prefix.rx) | not) then "doesn'"'"'t start with the repo'"'"'s \($c.prefix.name) prefix (\(($c.prefix.share*100)|floor)% of titles use it)" else empty end),
        (if $w > $c.p90_words then "\($w) words; the repo'"'"'s titles run \($c.median_words) (90% are \($c.p90_words) or fewer)" else empty end),
        ($F[] | . as $f | select($t | test($f[1])) | select(($c.rates[$f[0]] // 0) < 0.10)
          | "has \($f[2]); \((($c.rates[$f[0]] // 0)*100)|floor)% of the repo'"'"'s titles do") ] | .[]')
  echo
  if [ -n "$out" ]; then flagged=$((flagged + 1)); echo "FLAG \"$t\""; echo "$out" | sed 's/^/  - /'; else echo "ok   \"$t\""; fi
done
[ "$flagged" -eq 0 ]
