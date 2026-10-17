#!/usr/bin/env bash
# Read the defaults an existing PR has already set, before you add to it.
#
#   prdefaults.sh --repo owner/name --pr N [--as-of DATE] [--save FILE]
#
# Someone else's open PR is its own small house: the author picked names, a test style, a
# commit style, and an approach that reviewers then shaped. Work added to it should extend
# those choices, so this prints them:
#   - who may change the branch (author invitations, maintainer edits, forks), and how active it is,
#   - the approach as reviewed: review decision, open threads with the reviewer's words,
#   - commit conventions on the branch: subject pattern, sign-off, co-authors, merge or rebase,
#     force pushes,
#   - the PR's own code style from its added lines: test assertions, comment density, naming,
#     and changelog files it already carries,
#   - CI checks failing now.
# --save writes the same report to FILE (the ledger's pr-defaults.md).
# --as-of filters commits, comments, reviews, and threads by date; the file list and thread
# resolution are always current.

set -uo pipefail
repo="" pr="" asof="" save=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --pr) pr="$2"; shift 2 ;;
    --as-of) asof="$2"; shift 2 ;;
    --save) save="$2"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "prdefaults.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] && [ -n "$pr" ] || { echo "prdefaults.sh: --repo and --pr are required" >&2; exit 2; }
T="9999"; [ -n "$asof" ] && { case "$asof" in *T*) T="$asof" ;; *) T="${asof}T00:00:00Z" ;; esac; }
me=$(gh api user --jq .login 2>/dev/null)

data=$(gh api graphql -F o="${repo%/*}" -F r="${repo#*/}" -F n="$pr" -f query='
query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  title state isDraft createdAt mergedAt closedAt author{login} baseRefName headRefName headRepository{nameWithOwner}
  isCrossRepository maintainerCanModify reviewDecision labels(first:20){nodes{name}}
  commits(last:100){nodes{commit{oid messageHeadline message committedDate parents(first:2){totalCount} author{user{login}}
    statusCheckRollup{contexts(first:50){nodes{... on CheckRun{name conclusion} ... on StatusContext{context state}}}}}}}
  files(first:100){nodes{path additions deletions}}
  reviewThreads(first:60){nodes{isResolved isOutdated path line comments(first:3){nodes{author{login} authorAssociation createdAt body}}}}
  comments(last:60){nodes{author{login} authorAssociation createdAt body}}
  reviews(last:30){nodes{author{login} authorAssociation state submittedAt body}}
  timelineItems(last:50,itemTypes:[HEAD_REF_FORCE_PUSHED_EVENT,ASSIGNED_EVENT]){nodes{__typename ... on HeadRefForcePushedEvent{createdAt} ... on AssignedEvent{createdAt assignee{... on User{login}}}}}
}}}' --jq '.data.repository.pullRequest') || { echo "prdefaults.sh: couldn't read $repo#$pr" >&2; exit 2; }
[ -n "$data" ] && [ "$data" != null ] || { echo "prdefaults.sh: $repo#$pr not found" >&2; exit 2; }
author=$(echo "$data" | jq -r .author.login)

report() {
echo "# PR defaults: $repo#$pr"
echo
echo "$data" | jq -r --arg t "$T" --arg me "$me" '
  def maint: .authorAssociation | test("OWNER|MEMBER|COLLABORATOR");
  "\(.title)",
  "",
  "- State: \(if $t == "9999" then (.state | ascii_downcase) elif (.mergedAt // "9999") < $t then "merged" elif (.closedAt // "9999") < $t then "closed" else "open" end)\(if .isDraft then ", draft" else "" end); opened \(.createdAt[:10]) by \(.author.login)\(if .author.login == $me then " (you)" else "" end); base \(.baseRefName); head \(.headRepository.nameWithOwner // "?"):\(.headRefName)",
  "- Labels: \([.labels.nodes[].name] | join(", ") | if . == "" then "none" else . end)",
  "- Review decision: \(.reviewDecision // "none yet")",
  "- Last commit: \([.commits.nodes[].commit | select(.committedDate < $t)] | last | .committedDate[:10] // "none")",
  "- Author last spoke: \([(.comments.nodes[], .reviews.nodes[]) | select(.author.login == $ARGS.named.a) | (.createdAt // .submittedAt) | select(. < $t)] | max | if . then .[:10] else "never in the thread" end)"
' --arg a "$author"

echo
echo "## Who may change this branch"
echo "$data" | jq -r --arg t "$T" --arg a "$author" '
  "- Head lives in \(if .isCrossRepository then "the author'"'"'s fork" else "the upstream repo" end); maintainers can push to it: \(.maintainerCanModify)",
  ([.comments.nodes[], .reviews.nodes[] | select(.author.login == $a and ((.createdAt // .submittedAt) < $t))
     | select((.body // "") | test("feel free to (push|take|pick|commit)|happy for (someone|anyone)|anyone (wants|is welcome)|take (it|this) over|help wanted|push (to|on top of) (my|this) branch|can.t finish|don.t have time|abandon"; "i"))
     | "- The author invited help (\((.createdAt // .submittedAt)[:10])): \(.body | gsub("\\s+"; " ") | .[:240])"] | if length == 0 then "- The author hasn'"'"'t invited anyone to push or take over. Offer in a comment first." else .[] end),
  ([.timelineItems.nodes[] | select(.__typename == "AssignedEvent" and .createdAt < $t) | "- Assigned to \(.assignee.login) on \(.createdAt[:10])"] | .[])'

echo
echo "## The approach as reviewed (follow these; don't reopen settled ones)"
[ "$T" != 9999 ] && echo "(Thread resolution is as of now; GitHub doesn't record when a thread was resolved.)"
echo "$data" | jq -r --arg t "$T" '
  def maint: (.authorAssociation // "") | test("OWNER|MEMBER|COLLABORATOR");
  ([.reviews.nodes[] | select(.submittedAt < $t and maint and (.state == "CHANGES_REQUESTED" or .state == "APPROVED" or ((.body // "") | length > 0)))
     | "- \(.author.login) \(.state | ascii_downcase | gsub("_"; " ")) (\(.submittedAt[:10]))\(if (.body // "") != "" then ": \(.body | gsub("\\s+"; " ") | .[:300])" else "" end)"] | .[-6:][]),
  "",
  "Open review threads:",
  ([.reviewThreads.nodes[] | select(.isResolved | not) | select(.comments.nodes[0].createdAt < $t)
     | "- \(.path)\(if .line then ":\(.line)" else "" end)\(if .isOutdated then " (outdated)" else "" end), \(.comments.nodes[0].author.login)\(if (.comments.nodes[0] | maint) then " (maintainer)" else "" end): \(.comments.nodes[0].body | gsub("\\s+"; " ") | .[:300])"]
   | if length == 0 then "- none" else .[] end),
  "",
  "Settled in resolved threads (the PR already went this way):",
  ([.reviewThreads.nodes[] | select(.isResolved) | select(.comments.nodes[0].createdAt < $t) | select(.comments.nodes[0] | maint)
     | "- \(.path): \(.comments.nodes[0].body | gsub("\\s+"; " ") | .[:200])"] | if length == 0 then "- none" else .[-8:][] end),
  "",
  "Maintainer comments in the conversation:",
  ([.comments.nodes[] | select(.createdAt < $t and maint) | select((.author.login // "") | test("bot"; "i") | not)
     | "- \(.author.login) (\(.createdAt[:10])): \(.body | gsub("\\s+"; " ") | .[:300])"] | if length == 0 then "- none" else .[-5:][] end)'

echo
echo "## Commit conventions on this branch"
echo "$data" | jq -r --arg t "$T" '
  [.commits.nodes[].commit | select(.committedDate < $t)] as $c | ($c | length) as $n
  | if $n == 0 then "- no commits before then" else
    "- \($n) commits. Subjects:",
    ($c[-8:][] | "    - \(.messageHeadline)"),
    "- Conventional prefixes (feat:, fix(x):): \([$c[] | select(.messageHeadline | test("^[a-z]+(\\([^)]+\\))?!?: "))] | length) of \($n)",
    "- Signed-off-by (DCO): \([$c[] | select(.message | test("Signed-off-by:"))] | length) of \($n)",
    "- Co-authored-by trailers: \([$c[] | select(.message | test("Co-authored-by:"; "i"))] | length) of \($n)",
    "- Merge commits from the base (updated by merging): \([$c[] | select(.parents.totalCount > 1)] | length)",
    "- Commit authors: \([$c[].author.user.login // "unknown"] | unique | join(", "))"
  end'
echo "$data" | jq -r --arg t "$T" '"- Force pushes: \([.timelineItems.nodes[] | select(.__typename == "HeadRefForcePushedEvent" and .createdAt < $t)] | length) (more than 0 means the author rewrites history; add commits on top and let them squash)"'

echo
echo "## What the PR already carries"
echo "$data" | jq -r '
  [.files.nodes[]] as $f
  | "- \($f | length) files, +\([$f[].additions] | add // 0) -\([$f[].deletions] | add // 0)",
    ([$f[] | select(.path | test("(^|/)\\.changeset/|CHANGELOG|(^|/)changelog\\.d/|(^|/)newsfragments/|(^|/)\\.changes/"; "i"))] | if length > 0 then "- Changelog entries already in the PR (edit these; don'"'"'t add a second): \(map(.path) | join(", "))" else "- No changelog entry yet" end),
    ([$f[] | select(.path | test("(^|/)(tests?|__tests__|spec)/|[._-](test|spec)\\.[a-z]+$|_test\\.(go|py|rs)$"))] | if length > 0 then "- Test files: \(map(.path) | join(", "))" else "- No test files yet" end),
    "- Other files: \([$f[] | select(.path | test("(^|/)(tests?|__tests__|spec)/|[._-](test|spec)\\.[a-z]+$|_test\\.(go|py|rs)$|\\.changeset/|CHANGELOG"; "i") | not) | .path] | .[:15] | join(", "))"'

# The PR's own code style, from its added lines (only when the PR is still current; a diff is today's view).
if [ "$T" = 9999 ]; then
  diff=$(gh pr diff "$pr" -R "$repo" 2>/dev/null)
  if [ -n "$diff" ]; then
    added=$(echo "$diff" | grep -E '^\+[^+]' | sed 's/^+//')
    tests=$(echo "$diff" | awk '/^\+\+\+ b\//{f=$2} /^\+[^+]/{ if (f ~ /(^|\/)(tests?|__tests__|spec)\/|[._-](test|spec)\.[a-z]+$|_test\.(go|py|rs)$/) print substr($0,2) }')
    echo
    echo "## The PR's own style (match it in what you add)"
    n=$(echo "$added" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
    c=$(echo "$added" | grep -c -E '^[[:space:]]*(//|#|/\*|\*|--)' )
    echo "- Added lines: $n, comment lines among them: $c"
    forms=$(echo "$tests" | grep -o -E '\.(to[A-Z][A-Za-z]+|toMatchSnapshot|toMatchInlineSnapshot)\(|\bassert\.[a-z][A-Za-z_]*\(|\bassert(_eq|_ne|_matches)?!\(|\bself\.assert[A-Z][A-Za-z]*\(|\bt\.(Errorf|Fatalf|Error|Fatal)\(|\brequire\.[A-Z][A-Za-z]*\(|\bassert[A-Z][A-Za-z]*\(' | sed 's/($//' | sort | uniq -c | sort -rn | head -5 | awk '{printf "%s (%s) ", $2, $1}')
    [ -n "$forms" ] && echo "- Test assertions the PR uses: $forms"
    tnames=$(echo "$tests" | grep -o -E '\b(it|test|describe)\(["'"'"'`][^"'"'"'`]{0,60}' | head -4 | sed 's/^/    - /')
    [ -n "$tnames" ] && { echo "- Test names, for phrasing:"; echo "$tnames"; }
    syms=$(echo "$added" | grep -o -E '^(export )?(async )?(function|const|let|class|interface|type|enum|def|fn|pub fn|pub\(crate\) fn|func) +[A-Za-z_][A-Za-z0-9_]*' | awk '{print $NF}' | head -10 | tr '\n' ' ')
    [ -n "$syms" ] && echo "- New names it introduces: $syms"
  fi
fi

echo "$data" | jq -r '[.commits.nodes[-1].commit.statusCheckRollup.contexts.nodes[]? | select((.conclusion // .state // "") | test("FAILURE|ERROR|TIMED_OUT|ACTION_REQUIRED"; "i")) | (.name // .context)] | if length > 0 then "\n## CI failing on the head commit\n" + (map("- " + .) | join("\n")) else empty end'
}

if [ -n "$save" ]; then report | tee "$save"; else report; fi
