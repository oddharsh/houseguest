#!/usr/bin/env bash
# What changed upstream since recon? Run it right before opening the PR.
#
#   recheck.sh --repo owner/name [--issue N] [--files a,b] [--q "terms"]... [--since DATE] [--save FILE]
#
# The most common reason agent-written PRs go unmerged, after failing CI, is that another
# PR fixed the same issue first. Recon checks once, at the start; this checks again, for
# everything since --since (default: when the ledger's recon.md was last written):
#   - the issue: closed, and by what; PRs that newly link it;
#   - PRs opened since that touch --files, or match a --q search;
#   - commits on the default branch since that touch --files.
# Your own PRs are left out. Ends with STATUS: CLEAR or STATUS: CHANGED, and exits 1 on
# CHANGED. --save writes the report to FILE (the ledger's recheck.md) and seals it (receipt.sh).

set -uo pipefail
. "$(dirname "$0")/lib.sh"
repo="" issue="" files="" since="" save=""
queries=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --files) files="$2"; shift 2 ;;
    --q) queries+=("$2"); shift 2 ;;
    --since) since="$2"; shift 2 ;;
    --save) save="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "recheck.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { echo "recheck.sh: --repo is required" >&2; exit 2; }
if [ -z "$since" ]; then
  recon="$(git rev-parse --git-dir 2>/dev/null)/houseguest/$(git branch --show-current 2>/dev/null)/recon.md"
  [ -f "$recon" ] || { echo "recheck.sh: pass --since, or run it in the clone after recon.md exists" >&2; exit 2; }
  since=$(date -u -r "$recon" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(stat -c %Y "$recon")" +%Y-%m-%dT%H:%M:%SZ)
fi
case "$since" in *T*) ;; *) since="${since}T00:00:00Z" ;; esac
me=$(gh api user --jq .login 2>/dev/null)
changed=0
flag() { changed=1; echo "- $1"; }

# The searches and per-file commit lookups run in parallel; report() reads their lines in order.
search_hits() {  # search_hits <query> -> one line per PR hit, or "FAILED"
  local res
  res=$(gh api graphql -f q="$1" -f query='query($q:String!){search(query:$q,type:ISSUE,first:50){nodes{... on PullRequest{number url state title author{login} files(first:100){nodes{path}}}}}}' --jq '.data.search.nodes' 2>/dev/null) || { echo "FAILED"; return; }
  echo "$res" | jq -r --arg f "$files" --arg me "$me" --arg q "$1" '
    ($f | split(",") | map(select(length > 0))) as $mine
    | .[] | select(.number != null and (.author.login // "") != $me)
    | ([.files.nodes[].path] | map(select(. as $x | $mine | index($x)))) as $hit
    | select(($q | test(" created:>=[^ ]+ ")) or ($hit | length) > 0)
    | "#\(.number) (\(.state | ascii_downcase)) \(.title): \(.url)\(if ($hit | length) > 0 then " touches \($hit | join(", "))" else " matches the search" end)"'
}
file_hits() {  # file_hits <path> -> "<path>: <commit>" per commit since $since
  gh api "repos/$repo/commits?path=$(printf '%s' "$1" | jq -sRr @uri)&since=$since&per_page=20" \
    --jq '.[] | "\(.sha[:10]) \(.commit.author.date[:10]) \(.author.login // .commit.author.name): \(.commit.message | split("\n")[0])"' 2>/dev/null \
    | sed "s#^#$1: #"
}

report() {
  echo "# Recheck: $repo since $since"
  echo "Checked: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [ -n "$issue" ]; then
    echo; echo "## Issue #$issue"
    data=$(gh api graphql -F o="${repo%/*}" -F r="${repo#*/}" -F n="$issue" -f query='
query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){state stateReason closedAt
  timelineItems(last:50,itemTypes:[CLOSED_EVENT,CROSS_REFERENCED_EVENT]){nodes{__typename
    ... on ClosedEvent{createdAt closer{__typename ... on PullRequest{number url} ... on Commit{oid url}}}
    ... on CrossReferencedEvent{createdAt source{__typename ... on PullRequest{number url state author{login}}}}}}}}}' --jq '.data.repository.issue' 2>/dev/null)
    if [ -z "$data" ] || [ "$data" = null ]; then flag "couldn't read issue #$issue; check it by hand"
    else
      hits=$(echo "$data" | jq -r --arg s "$since" --arg me "$me" '
        (if .state == "CLOSED" and (.closedAt // "") >= $s then "closed \(.closedAt[:10]) as \(.stateReason // "closed")\([.timelineItems.nodes[] | select(.__typename == "ClosedEvent" and .closer != null) | .closer | " by " + (.url // "")] | last // "")" else empty end),
        (.timelineItems.nodes[] | select(.__typename == "CrossReferencedEvent" and .createdAt >= $s and .source.__typename == "PullRequest" and (.source.author.login // "") != $me)
          | "newly linked from PR #\(.source.number) (\(.source.state | ascii_downcase)): \(.source.url)")')
      if [ -n "$hits" ]; then while IFS= read -r h; do flag "$h"; done <<< "$hits"; else echo "- still open, and no new PR links it"; fi
    fi
  fi

  echo; echo "## PRs opened since"
  any=""
  qs=()
  [ -n "$files" ] && qs+=("repo:$repo is:pr created:>=$since")
  for q in "${queries[@]+"${queries[@]}"}"; do qs+=("repo:$repo is:pr created:>=$since $q"); done
  for q in "${qs[@]+"${qs[@]}"}"; do
    # One job per search, so a failure stays tied to its query.
    ( hits=$(search_hits "$q"); printf '%s\n' "$hits" > "$tmp/q.$(printf '%s' "$q" | cksum | cut -d' ' -f1)" ) &
  done
  wait
  for q in "${qs[@]+"${qs[@]}"}"; do
    hits=$(cat "$tmp/q.$(printf '%s' "$q" | cksum | cut -d' ' -f1)")
    if [ "$hits" = "FAILED" ]; then flag "search failed: $q"; continue; fi
    [ -n "$hits" ] && while IFS= read -r h; do any=1; flag "$h"; done <<< "$hits"
  done
  [ -n "$any" ] || echo "- none touching your files or matching your searches"

  if [ -n "$files" ]; then
    echo; echo "## Commits on the default branch since"
    anyc=""
    hits=$(echo "$files" | tr ',' '\n' | pmap 6 file_hits)
    [ -n "$hits" ] && while IFS= read -r h; do anyc=1; flag "$h"; done <<< "$hits"
    [ -n "$anyc" ] || echo "- none on your files"
  fi

  echo
  if [ "$changed" = 1 ]; then
    echo "STATUS: CHANGED"
    echo "Read each item above. A merged fix or a closed issue means STOP; an open PR for the same change means JOIN or STOP; a commit to your files means merge the base and rerun the proof."
  else
    echo "STATUS: CLEAR"
  fi
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
out=$(report); echo "$out"
[ -n "$save" ] && echo "$out" > "$save" && bash "$(dirname "$0")/receipt.sh" seal "$save"
echo "$out" | grep -q '^STATUS: CLEAR' || exit 1
