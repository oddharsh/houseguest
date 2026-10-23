#!/usr/bin/env bash
# Collect the raw material for oss-pr recon into one markdown dump on stdout.
#
#   gather.sh [--repo owner/name] [--issue N] [--as-of DATE] [--files a,b,...]
#             [--q "search terms"]... [--search-only] [search terms...]
#
# Run it before you clone: with --repo and no matching local clone, it reads the
# contribution docs through the GitHub API. Inside a clone or fork it reads them
# from disk and defaults to the fork's parent, where issues and PRs live.
#
# --q        one search; repeat it for more. GitHub ANDs the words inside one
#            search, so give each phrasing its own --q. Bare words form one more.
# --files    the files your change touches: lists open PRs touching them and the
#            recent commits on each, which is where lineage and conflicts show up.
# --as-of    YYYY-MM-DD or a full ISO timestamp. Rebuilds the view at that moment:
#            docs at the last commit before it, only issues and PRs created before
#            it, and their state as of then. For replaying recon on a past PR.
# --search-only  skip docs, baselines, and history; rerun just the searches.
# --exclude N    leave PR or issue N out of every list (replaying recon on N itself).
#
# Read-only: it calls `gh`, `git`, and `grep`, and never writes anything remote.
# Sections run in parallel and print in a fixed order. A lookup that fails is marked
# LOOKUP FAILED in its section and listed at the top, and the script exits 3: a failed
# search is unknown, never "none".

set -uo pipefail
. "$(dirname "$0")/lib.sh"

repo="" issue="" asof="" files_arg="" search_only="" bare="" exclude="0"
queries=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --as-of) asof="$2"; shift 2 ;;
    --files) files_arg="$2"; shift 2 ;;
    --q) queries+=("$2"); shift 2 ;;
    --search-only) search_only=1; shift ;;
    --exclude) exclude="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) bare="${bare:+$bare }$1"; shift ;;
  esac
done
[ -n "$bare" ] && queries+=("$bare")

local_repo=$(gh repo view --json nameWithOwner,parent \
  -q 'if .parent then "\(.parent.owner.login)/\(.parent.name)" else .nameWithOwner end' 2>/dev/null)
[ -z "$repo" ] && repo="$local_repo"
if [ -z "$repo" ]; then
  echo "gather.sh: couldn't resolve the upstream repo; pass --repo owner/name" >&2
  exit 1
fi
me=$(gh api user --jq .login 2>/dev/null)

mode="remote"
if [ -z "$asof" ] && [ "$local_repo" = "$repo" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  mode="local"
fi

before="" asof_ts="9999"   # ISO timestamps compare correctly as strings
if [ -n "$asof" ]; then
  case "$asof" in *T*) asof_ts="$asof" ;; *) asof_ts="${asof}T00:00:00Z" ;; esac
  before=" created:<$asof_ts"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
GH_FAILED="$work/failed"; : > "$GH_FAILED"
docroot="$work/docs" poldir="$work/policy"
mkdir -p "$docroot" "$poldir"

section() { printf '\n## %s\n\n' "$1"; }
failed() { echo "- LOOKUP FAILED: $1. This is unknown, not empty; rerun gather.sh before deciding anything from it."; }
capped() {  # capped <shown> <limit>: say so when a list stopped at its limit
  [ "${1:-0}" -ge "$2" ] && echo "- ($1 shown, the most this search returns. More may exist: add a narrower --q.)"
  return 0
}

# Each section runs in the background into its own numbered file; the files print in
# launch order once every job is done, so the dump reads the same as a serial run.
n=0
next_slot() { n=$((n + 1)); slot=$(printf '%s/part.%03d' "$work" "$n"); }
bg() { next_slot; ( "$@" ) > "$slot" 2>>"$work/stderr" & }

# jq helpers shared by every section.
JQLIB='
def state_asof($t):
  if (.mergedAt // "") != "" and .mergedAt < $t then "MERGED"
  elif (.closedAt // "") != "" and .closedAt < $t then (if .state == "MERGED" then "CLOSED" else .state end)
  elif .state == "OPEN" or ((.closedAt // "") >= $t) then "OPEN"
  else .state end;
def reason_asof($t): if state_asof($t) == .state and (.stateReason // "") != "" then " " + .stateReason else "" end;
def human: ((.author.is_bot // false) | not)
  and (((.author.login // "") | test("\\[bot\\]$|^app/|dependabot|renovate|github-actions|changeset|release-please"; "i")) | not)
  and (((.title // "") | test("^(Version Packages|chore\\(release\\)|Release v?[0-9])"; "i")) | not);
def median: if length == 0 then null else sort | .[length/2|floor] end;
def maint: (.authorAssociation // "") | IN("OWNER","MEMBER","COLLABORATOR");
'
jqa() {  # jqa [jq args...] <program>: jq -r with $t, $me, and the helpers above
  local n=$# prog; prog="${!n}"
  local extra=("${@:1:$((n-1))}")
  jq -r --arg t "$asof_ts" --arg me "$me" --argjson ex "$exclude" ${extra[@]+"${extra[@]}"} "$JQLIB $prog"
}
drop_ex() { jq --argjson ex "$exclude" 'if type == "array" then map(select((.number // 0) != $ex)) else . end'; }

# --- Contribution docs ---------------------------------------------------------
DOC_RE='(^|/)((CONTRIBUTING|CODE_OF_CONDUCT|GOVERNANCE|ROADMAP|SECURITY|STYLE|STYLEGUIDE|HACKING|DEVELOPMENT|MAINTAINERS|AI_POLICY|AGENTS|CLAUDE|TRIAGE|DCO|CLA)(\.(md|rst|txt|adoc))?|CODEOWNERS|VOUCHED[^/]*|\.editorconfig)$|^\.github/(PULL_REQUEST_TEMPLATE|ISSUE_TEMPLATE)|pull_request_template'
WF_RE='pr|pull|triage|title|description|semantic|label|close|stale|vouch|cla|lint-pr|welcome|first'

s_repo() {
  section "Repo"
  ghf "repo view" gh repo view "$repo" --json defaultBranchRef,description,isArchived,stargazerCount \
    -q '"- default branch: \(.defaultBranchRef.name)\n- archived today: \(.isArchived)\n- stars today: \(.stargazerCount)\n- description: \(.description)"' \
    || failed "couldn't read the repo"
}

fetch_doc() {
  mkdir -p "$docroot/$(dirname "$1")"
  ghf "doc $1" gh api -H "Accept: application/vnd.github.raw" "repos/$repo/contents/$1?ref=$(cat "$work/ref")" > "$docroot/$1"
}
fetch_docs() {  # writes $work/ref and $work/files, and mirrors docs into $docroot
  if [ "$mode" = "local" ]; then
    echo HEAD > "$work/ref"; git ls-files > "$work/files" 2>/dev/null; return
  fi
  local ref root gh_sha files u="repos/$repo/commits?per_page=1"
  [ -n "$asof" ] && u="repos/$repo/commits?until=${asof_ts}&per_page=1"
  ref=$(ghf "default branch commit" gh api "$u" --jq '.[0].sha') || return
  echo "$ref" > "$work/ref"
  # Root listing plus the whole .github tree; a full recursive tree truncates on big repos.
  root=$(ghf "root tree" gh api "repos/$repo/git/trees/$ref" --jq '.tree[] | "\(.type) \(.path) \(.sha)"') || return
  files=$(echo "$root" | awk '$1=="blob"{print $2}')
  gh_sha=$(echo "$root" | awk '$2==".github"{print $3}')
  if [ -n "$gh_sha" ]; then
    files="$files
$(ghf ".github tree" gh api "repos/$repo/git/trees/$gh_sha?recursive=1" --jq '.tree[] | select(.type=="blob") | ".github/" + .path')"
  fi
  echo "$files" > "$work/files"
  # Mirror doc-like files, plus workflows whose names suggest PR policing, so grep can scan them.
  { echo "$files" | grep -iE "$DOC_RE|^[^/]+\.(md|rst|txt)$|^\.github/[^/]*\.md$|^\.github/(ISSUE_TEMPLATE|DISCUSSION_TEMPLATE)/" | grep -v '^\.github/workflows/' | head -60
    echo "$files" | grep -E '^\.github/workflows/' | grep -iE "$WF_RE" | head -25; } \
  | pmap 8 fetch_doc
}

s_docs() {
  local ref files docs wf
  ref=$(cat "$work/ref" 2>/dev/null); files=$(cat "$work/files" 2>/dev/null)
  section "Contribution docs ($mode, at ${ref:0:10})"
  if [ -z "$files" ]; then failed "couldn't list the repo's files"; echo; return; fi
  docs=$(echo "$files" | grep -iE "$DOC_RE")
  if [ -n "$docs" ]; then echo "$docs" | sed 's/^/- /'; else echo "- (none found)"; fi
  wf=$(echo "$files" | grep -E '^\.github/workflows/' | sed 's#.*/##' | tr '\n' ' ')
  [ -n "$wf" ] && echo "- CI workflows: $wf"
  [ "$mode" = "remote" ] && echo "- (remote mode lists root and .github only; per-directory AGENTS.md and docs/ or website/ pages show up once you clone, or fetch them by path)"
  echo
}

s_policy() {
  bash "$(dirname "$0")/policy.sh" --repo "$repo" ${asof:+--as-of "$asof_ts"} --keep "$poldir"
  echo
}

docgrep() {  # docgrep <regex> -> path:line:text across docs (not workflows)
  if [ "$mode" = "local" ]; then
    git grep -n -i -E "$1" -- '*.md' '*.rst' '*.txt' '.github/*' ':!.github/workflows/*' 2>/dev/null
  else
    (cd "$docroot" && grep -rn -i -E "$1" --exclude-dir=workflows . 2>/dev/null | sed 's#^\./##')
  fi
}
wfgrep() {
  if [ "$mode" = "local" ]; then
    git grep -n -i -E "$1" -- '.github/workflows/*' 2>/dev/null
  else
    [ -d "$docroot/.github/workflows" ] && (cd "$docroot" && grep -rn -i -E "$1" .github/workflows 2>/dev/null)
  fi
}

s_gates() {
  section "Contributor gates (discussion-first, DCO, CLA, vouching)"
  local GATE_RE gates
  GATE_RE='engage (on|in|with) the (issue|discussion)|(open|create|file|start) an? (issue|discussion|feature request)[^.]{0,60}(first|before|prior)|before (writing|starting|you (write|start)|opening|submitting|sending) (any |your )?(code|a PR|a pull request|work)|discuss[^.]{0,40}(first|before|prior)|non-trivial|signed-off-by|developer certificate of origin|\bDCO\b|contributor license agreement|\bCLA\b|vouch|unsolicited|drive-by'
  gates=$( { docgrep "$GATE_RE"
    (cd "$poldir" && grep -rn -i -E "$GATE_RE" . 2>/dev/null | grep -v '/\.github/[^:]*:' | sed 's#^\./#(linked or org) #'); } | sort -u | cut -c1-300 | head -30)
  if [ -n "$gates" ]; then echo '```'; echo "$gates"; echo '```'; else echo "- none found by pattern; read CONTRIBUTING's section on issues and PRs anyway"; fi
}

s_workflows() {
  section "Workflows that police PRs (body, title, labels, auto-close)"
  local pol
  pol=$(wfgrep 'pull_request(_target)?\.(body|title)|github\.event\.pull_request\.body|validate[-_ ]?pr|pr[-_ ]?(description|title|body)|semantic-pull-request|auto[-_ ]?close|close[-_ ]?(pr|pull)|actions/stale|vouch|cla[-_ ]?(assistant|bot)|required.*(heading|section|checkbox)' \
    | cut -c1-240 | head -20)
  if [ -n "$pol" ]; then echo '```'; echo "$pol"; echo '```'; else echo "- none found"; fi
}

# --- The issue -----------------------------------------------------------------
s_issue() {
  section "Issue #$issue"
  local j
  j=$(ghf "issue #$issue" gh issue view "$issue" -R "$repo" \
    --json title,state,stateReason,closedAt,author,labels,createdAt,url,comments) || { failed "couldn't read issue #$issue"; return; }
  echo "$j" | jqa '
      ([.comments[] | select(.createdAt < $t)]) as $c
      | ([$c[] | select(maint and ((.author.login // "") | test("bot"; "i") | not))]) as $m
      | (if $t == "9999" then now else ($t | fromdateiso8601) end) as $now
      | (($now - (.createdAt | fromdateiso8601)) / 3600) as $h
      | "- \(.title)\n- opened \(.createdAt[:16])Z by \(.author.login)\(if .author.login == $me then " (you)" else "" end), \(if $h < 48 then "\($h | floor) hours" else "\($h / 24 | floor) days" end) before this view\n- state then: \(state_asof($t))\(reason_asof($t))\n- labels: \([.labels[].name] | join(", "))\n- comments before then: \($c | length), from maintainers (OWNER/MEMBER/COLLABORATOR, non-bot): \($m | length)\n- url: \(.url)\n\nLast 6 comments before then:",
        (if ($c | length) == 0 then "- (none)" else ($c[-6:][] | "- **\(.author.login)**\(if .author.login == $me then " (you)" else "" end) (\(.authorAssociation), \(.createdAt[:10])): \(.body | gsub("\\s+"; " ") | .[:600])") end)'
  echo
  echo "(authorAssociation can understate: an active maintainer may show as CONTRIBUTOR. Check who merges PRs in the list below.)"
}

s_mentions() {
  section "PRs mentioning #$issue"
  local j
  j=$(ghf "PRs mentioning #$issue" gh pr list -R "$repo" --state all --search "\"#$issue\"$before" --limit 15 \
    --json number,title,state,mergedAt,closedAt,isCrossRepository,author,url) || { failed "PR search for #$issue"; return; }
  echo "$j" | drop_ex \
    | jqa 'if length == 0 then "- (none)" else .[] | "- #\(.number) [\(state_asof($t))] \(.title) (by \(.author.login)\(if .isCrossRepository then ", from fork" else "" end)) \(.url)" end'
  capped "$(echo "$j" | jq length)" 15
}

# The issue's links, then the links into each PR that fixed it: a regression or a
# follow-up often cites the fix PR rather than the issue it closed.
LINKED='__typename
  ... on Issue{number title url state stateReason createdAt closedAt repository{nameWithOwner}}
  ... on PullRequest{number title url state createdAt closedAt mergedAt author{login} repository{nameWithOwner}}'
s_linked() {
  section "Work linked to #$issue (fixes, regressions, follow-ups)"
  local j prs q seen
  j=$(ghf "timeline of #$issue" gh api graphql -F o="${repo%/*}" -F r="${repo#*/}" -F n="$issue" -f query='
query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){
  timelineItems(first:100,itemTypes:[CROSS_REFERENCED_EVENT,CONNECTED_EVENT,CLOSED_EVENT,MARKED_AS_DUPLICATE_EVENT]){pageInfo{hasNextPage} nodes{__typename
    ... on CrossReferencedEvent{createdAt source{'"$LINKED"'}}
    ... on ConnectedEvent{createdAt subject{'"$LINKED"'}}
    ... on MarkedAsDuplicateEvent{createdAt canonical{'"$LINKED"'}}
    ... on ClosedEvent{createdAt closer{__typename ... on PullRequest{number}}}}}}}}' --jq '.data.repository.issue') \
    || { failed "couldn't read what links to #$issue"; return; }
  # One row per linked item, earliest link first. Rows carry the fields state_asof reads.
  LJQ='def ref($r): (if .repository.nameWithOwner == $r then "" else .repository.nameWithOwner end) + "#\(.number)";
    def kind: if .__typename == "PullRequest" then "PR" else "issue" end;
    def revert: if (.title // "") | test("^revert"; "i") then " (a revert)" else "" end;'
  echo "$j" | jq -r --arg t "$asof_ts" --arg r "$repo" --argjson ex "$exclude" "$JQLIB$LJQ"'
    . as $issue
    | [.timelineItems.nodes[] | select((.createdAt // "") < $t)] as $ev
    | [$ev[] | select(.__typename == "ClosedEvent" and .closer.__typename == "PullRequest") | .closer.number] as $closers
    | [$ev[] | {at: .createdAt, how: (if .__typename == "MarkedAsDuplicateEvent" then "dup" else "link" end), s: (.source // .subject // .canonical)}
       | select(.s.number != null and .s.createdAt < $t and (.s.number != $ex or .s.repository.nameWithOwner != $r))]
    | group_by(.s.repository.nameWithOwner + "#" + (.s.number | tostring)) | map(min_by(.at)) | sort_by(.at) as $rows
    | ([$rows[].s | select(.__typename == "PullRequest" and .repository.nameWithOwner == $r and state_asof($t) == "MERGED") | .mergedAt] | min) as $fix
    | if ($rows | length) == 0 then "- none linked before then"
      else $rows[] | .s as $s
        | "- \($s | kind) \($s | ref($r)) [\($s | state_asof($t))\($s | reason_asof($t))] \($s.title)\($s | revert)"
          + (if $s.author then " (by \($s.author.login))" else "" end)
          + (if .how == "dup" then ", and this issue was marked a duplicate of it"
             elif $s.__typename == "PullRequest" and ($s.number | IN($closers[])) and $s.repository.nameWithOwner == $r then ", closed this issue"
             elif $fix != null and .at > $fix and $s.mergedAt != $fix then ", linked \(.at[:10]), after the fix merged"
             else ", linked \(.at[:10])" end)
          + " \($s.url)"
      end,
    (if $issue.timelineItems.pageInfo.hasNextPage then "- (stopped at 100 linked events; links past that were not read)" else empty end)'
  prs=$(echo "$j" | jq -r --arg t "$asof_ts" --arg r "$repo" "$JQLIB"'
    [.timelineItems.nodes[] | select((.createdAt // "") < $t) | (.source // .subject // .canonical // empty)
     | select(.__typename == "PullRequest" and .repository.nameWithOwner == $r and state_asof($t) == "MERGED") | .number] | unique | .[]')
  [ -z "$prs" ] && return
  echo
  echo "Linking to the merged PRs above (depth 2):"
  q='query($o:String!,$r:String!){repository(owner:$o,name:$r){'
  for p in $(echo "$prs" | head -6); do
    q="$q p$p: pullRequest(number:$p){number mergedAt timelineItems(first:50,itemTypes:[CROSS_REFERENCED_EVENT]){pageInfo{hasNextPage} nodes{... on CrossReferencedEvent{createdAt source{$LINKED}}}}}"
  done
  q="$q }}"
  seen=$(echo "$j" | jq -c --arg r "$repo" --arg n "$issue" '[$r + "#" + $n] + [.timelineItems.nodes[] | (.source // .subject // .canonical // empty) | select(.number != null) | .repository.nameWithOwner + "#" + (.number | tostring)]')
  ghf "PRs linking to the fix PRs" gh api graphql -F o="${repo%/*}" -F r="${repo#*/}" -f query="$q" --jq '.data.repository' \
    | jq -r --arg t "$asof_ts" --arg r "$repo" --argjson seen "$seen" "$JQLIB$LJQ"'
      . as $prs
      | [to_entries[] | .value as $p | $p.timelineItems.nodes[] | select(.source.number != null and .createdAt < $t and .source.createdAt < $t)
       | {pr: $p.number, merged: $p.mergedAt, at: .createdAt, s: .source}
       | select((.s.repository.nameWithOwner + "#" + (.s.number | tostring)) | IN($seen[]) | not)]
      | group_by(.s.repository.nameWithOwner + "#" + (.s.number | tostring)) | map(min_by(.at)) | sort_by(.at) as $rows
      | (if ($rows | length) == 0 then "- nothing else links to them" else empty end),
        ($rows[] | .s as $s | "- #\(.pr) <- \($s | kind) \($s | ref($r)) [\($s | state_asof($t))\($s | reason_asof($t))] \($s.title)\($s | revert)"
          + (if $s.createdAt > .merged then ", opened \($s.createdAt[:10]), after #\(.pr) merged" else ", linked \(.at[:10])" end) + " \($s.url)"),
        ([$prs | to_entries[] | select(.value.timelineItems.pageInfo.hasNextPage) | .value.number] | if length > 0 then "- (stopped at 50 links on \(map("#\(.)") | join(", ")); later links were not read)" else empty end)' \
    || failed "couldn't read what links to the fix PRs"
  [ "$(echo "$prs" | wc -l)" -gt 6 ] && echo "- (followed 6 of $(echo "$prs" | wc -l | tr -d ' ') merged PRs)"
  echo
  echo "An open issue, a revert, or a regression linked after a fix merged means that fix didn't cover every case. Read it before assuming the fix covers yours."
}

# --- Open PRs and recent commits touching your files ----------------------------
s_openprs() {
  section "Open PRs touching your files"
  local qs q allopen cursor page res stop=""
  # Every PR open at that moment: still open and created before it, or closed after it.
  if [ -n "$asof" ]; then qs="repo:$repo is:pr is:open created:<$asof_ts|repo:$repo is:pr is:closed closed:>$asof_ts created:<$asof_ts"
  else qs="repo:$repo is:pr is:open"; fi
  allopen="[]"
  IFS='|'; for q in $qs; do unset IFS
    cursor="null"
    for page in $(seq 1 20); do  # GitHub search stops at 1,000 results
      res=$(ghf "open PR search, page $page" gh api graphql -f query='query($q:String!,$c:String){search(query:$q,type:ISSUE,first:50,after:$c){pageInfo{hasNextPage endCursor} nodes{... on PullRequest{number title url state createdAt mergedAt closedAt author{login} files(first:100){nodes{path}}}}}}' -f q="$q" $( [ "$cursor" != "null" ] && echo -f c="$cursor" )) \
        || { stop="page $page of \"$q\""; break; }
      allopen=$(jq -s '.[0] + [.[1].data.search.nodes[] | select(.number != null)]' <(echo "$allopen") <(echo "$res"))
      [ "$(echo "$res" | jq -r .data.search.pageInfo.hasNextPage)" = "true" ] || break
      cursor=$(echo "$res" | jq -r .data.search.pageInfo.endCursor)
    done
  done; unset IFS
  if [ -n "$stop" ]; then
    failed "the open-PR search stopped at $stop$( [ "$allopen" != "[]" ] && echo ", so the list below is partial")"
    [ "$allopen" = "[]" ] && return
  fi
  echo "$allopen" | jq -r --arg f "$files_arg" '
    ($f | split(",")) as $mine | length as $n
    | ([.[] | [.files.nodes[].path] | map(select(. as $x | $mine | index($x)))[]] | group_by(.) | map({k: .[0], v: length})) as $counts
    | ([$counts[] | select(.v >= 5 or (.k | test("(^|/)(tests?|__tests__|spec)/|[._-](test|spec)\\.|(^|/)lib\\.rs$|(^|/)index\\.(ts|js)$"))) | .k]) as $hot
    | [.[] | . as $p | ([.files.nodes[].path] | map(select(. as $x | $mine | index($x)))) as $hit
       | select(($hit | length) > 0)
       | {number, title, url, who: .author.login, hit: $hit, core: ($hit - $hot)}]
    | sort_by(-(.core | length), -(.hit | length)) as $rows
    | "Checked \($n) PRs open at that moment\(if $n >= 1000 then " (GitHub search caps at 1,000 per query, so older open PRs may be missing; the searches below cover them by topic)" else "" end).",
      (if ($hot | length) > 0 then "Busy files (touched by 5+ open PRs, or shared test files; ranked last): \($hot | join(", "))" else empty end),
      (if ($rows | length) == 0 then "- none" else ($rows[:12][] | "- #\(.number) \(.title) (by \(.who)) touches \(if (.core | length) > 0 then (.core | join(", ")) else "only busy files: " + (.hit | join(", ")) end) \(.url)") end),
      (if ($rows | length) > 12 then "- (12 of \($rows | length) shown)" else empty end)'
}

file_commits() {
  local url="repos/$repo/commits?path=$1&per_page=5"
  [ -n "$asof" ] && url="$url&until=$asof_ts"
  echo "- \`$1\`"
  ghf "commits on $1" gh api "$url" --jq '.[] | "  - \(.sha[:10]) \(.commit.author.date[:10]) \(.author.login // .commit.author.name): \(.commit.message | split("\n")[0])"' \
    || echo "  - LOOKUP FAILED: unknown, not empty"
}
s_filecommits() {
  echo
  echo "Recent commits on each file (lineage: who shaped these lines, and why):"
  echo "$files_arg" | tr ',' '\n' | pmap 6 file_commits
}

# --- Duplicates and rejected attempts ------------------------------------------
s_qissues() {
  section "Issues matching: $1"
  local j
  j=$(ghf "issue search: $1" gh issue list -R "$repo" --state all --search "$1$before" --limit 20 \
    --json number,title,state,stateReason,closedAt,url) || { failed "issue search for \"$1\""; return; }
  echo "$j" | drop_ex \
    | jqa 'if length == 0 then "- (none)" else .[] | "- #\(.number) [\(state_asof($t))\(reason_asof($t))] \(.title) \(.url)" end'
  capped "$(echo "$j" | jq length)" 20
}

open_detail() {
  ghf "PR #$1 detail" gh pr view "$1" -R "$repo" --json files,reviews,comments \
    | jqa --arg n "$1" '"- #\($n): \([.files[].path][:8] | join(", "))\(if (.files | length) > 8 then " (+\((.files | length) - 8) more)" else "" end); reviews: \([.reviews[] | select(.submittedAt < $t) | "\(.author.login) \(.state)"] | if length == 0 then "none" else join(", ") end)",
      ([.comments[] | select(.createdAt < $t) | select(maint) | select((.author.login // "") | test("bot"; "i") | not)][-2:][] | "    - maintainer **\(.author.login)** (\(.createdAt[:10])): \(.body | gsub("\\s+"; " ") | .[:300])")' \
    || echo "- #$1: LOOKUP FAILED"
}
closed_reason() {
  ghf "PR #$1 comments" gh pr view "$1" -R "$repo" --json comments \
    | jqa --arg n "$1" '[.comments[] | select(.createdAt < $t)]
      | if length > 0 then .[-1] | "- #\($n) **\(.author.login)** (\(.authorAssociation)): \(.body | gsub("\\s+"; " ") | .[:500])" else "- #\($n) (closed with no comment)" end' \
    || echo "- #$1: LOOKUP FAILED"
}
s_qprs() {
  section "PRs matching: $1"
  local j prs open closed
  j=$(ghf "PR search: $1" gh pr list -R "$repo" --state all --search "$1$before" --limit 20 \
    --json number,title,state,mergedAt,closedAt,isCrossRepository,author,url) || { failed "PR search for \"$1\""; return; }
  prs=$(echo "$j" | drop_ex | jq --arg t "$asof_ts" "$JQLIB"'map(.asof = state_asof($t))')
  echo "$prs" | jq -r 'if length == 0 then "- (none)" else .[] | "- #\(.number) [\(.asof)] \(.title) (by \(.author.login)\(if .isCrossRepository then ", from fork" else "" end)) \(.url)" end'
  capped "$(echo "$j" | jq length)" 20

  # Open matches may already be doing your change. Show what they touch and how review stands.
  open=$(echo "$prs" | jq -r '.[] | select(.asof == "OPEN") | .number')
  if [ -n "$open" ]; then
    echo
    echo "Open matches in detail (files, and reviews before then):"
    echo "$open" | head -6 | pmap 6 open_detail
    [ "$(echo "$open" | wc -l)" -gt 6 ] && echo "- (6 of $(echo "$open" | wc -l | tr -d ' ') open matches shown)"
  fi

  # Closed-without-merge PRs are the rejected attempts. The last comment before
  # then is usually the maintainer's reason: the most valuable line in recon.
  echo
  echo "Last comment on each closed, unmerged match (likely the rejection reason):"
  closed=$(echo "$prs" | jq -r '.[] | select(.asof == "CLOSED") | .number')
  [ -z "$closed" ] && echo "- (none)"
  echo "$closed" | head -6 | pmap 6 closed_reason
  [ "$(echo "$closed" | sed '/^$/d' | wc -l)" -gt 6 ] && echo "- (6 of $(echo "$closed" | wc -l | tr -d ' ') closed matches shown)"
  return 0
}

# --- Your history here ---------------------------------------------------------
my_closed() {
  ghf "PR #$1 comments" gh pr view "$1" -R "$repo" --json comments | jqa --arg n "$1" '[.comments[] | select(.createdAt < $t) | select(.author.login != $me)] | if length > 0 then .[-1] | "  - why #\($n) closed, last word from **\(.author.login)**: \(.body | gsub("\\s+"; " ") | .[:300])" else "  - #\($n) closed with no comment from others" end' \
    || echo "  - #$1: LOOKUP FAILED"
}
s_mine() {
  section "Your PRs in this repo before then"
  local j mine
  j=$(ghf "your PRs" gh pr list -R "$repo" --author "@me" --state all --search "sort:created-desc$before" --limit 10 \
    --json number,title,state,mergedAt,closedAt,url) || { failed "couldn't list your PRs here"; return; }
  mine=$(echo "$j" | drop_ex | jq --arg t "$asof_ts" "$JQLIB"'map(.asof = state_asof($t))')
  echo "$mine" | jq -r 'if length == 0 then "- none (first contribution)" else .[] | "- #\(.number) [\(.asof)] \(.title) \(.url)" end'
  echo "$mine" | jq -r '.[] | select(.asof == "CLOSED") | .number' | head -4 | pmap 4 my_closed
}

# --- What this team accepts ----------------------------------------------------
s_merged() {
  section "Last 30 merged PRs (what this team accepts)"
  local merged merged_q="is:merged"
  [ -n "$asof" ] && merged_q="is:merged merged:<$asof_ts"
  merged=$(ghf "merged PRs" gh pr list -R "$repo" --state merged --search "$merged_q" --limit 30 \
    --json number,title,author,isCrossRepository,additions,deletions,changedFiles,body,mergedAt) || { failed "couldn't list merged PRs"; return; }
  echo "$merged" | jqa '.[] | select(human) | "- #\(.number) \(.mergedAt[:10]) \(.title) | by \(.author.login)\(if .isCrossRepository then " (fork)" else "" end) | +\(.additions)/-\(.deletions) in \(.changedFiles) files | body \(.body | length) chars"'
  echo
  echo "$merged" | jqa '
    [.[] | select(human)] as $h | [$h[] | select(.isCrossRepository)] as $o
    | "Bots and release PRs left out: \(length - ($h | length)) of \(length).",
      "Human median body: \([$h[].body | length] | median // "n/a") chars (n=\($h | length)). Outside-contributor median: \([$o[].body | length] | median // "n/a") chars (n=\($o | length)).",
      "Last merged PR from a fork: \(if ($o | length) > 0 then $o[0].mergedAt[:10] else "none in this window" end)."'
}

s_pre() {
  section "Pre-LLM baseline: outside contributors' merged PRs before Dec 2022"
  # ChatGPT launched 2022-11-30. PR text before then is the cleanest sample of how
  # this repo's human contributors wrote, and the length target for PR copy.
  local raw pre
  raw=$(ghf "pre-LLM PR search" gh search prs --repo "$repo" --merged --created "2015-01-01..2022-11-29" --sort created --order desc \
    --limit 80 --json title,body,author,authorAssociation,url) || { failed "couldn't search pre-LLM PRs"; return; }
  pre=$(echo "$raw" | jq "$JQLIB"'[.[] | select(human) | select(.authorAssociation | IN("CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE"))
         | .body = ((.body // "") | gsub("<!--[\\s\\S]*?-->"; "") | gsub("(?m)^\\s*- \\[[ xX]\\].*$"; "") | gsub("^\\s+|\\s+$"; ""))]')
  if [ "$(echo "${pre:-[]}" | jq length)" -eq 0 ]; then
    echo "- none (repo too new, or private before Dec 2022). Use the outside-contributor median above."
  else
    echo "$pre" | jq -r "$JQLIB"'
      "n=\(length). Median body \([.[].body | length] | median) chars, \([.[].body | split(" ") | length] | median) words. With headings: \(([.[] | select(.body | test("(?m)^#{1,4} "))] | length) * 100 / length | floor)%. Empty: \(([.[] | select(.body == "")] | length) * 100 / length | floor)%."'
    echo
    echo "Exemplars (read for voice, never copy):"
    echo "$pre" | jq -r '[.[] | select((.body | length) > 120 and (.body | length) < 900)][:5][]
      | "\n> **\(.title)** \(.url)\n" + (.body | .[:600] | split("\n") | map("> " + .) | join("\n"))'
  fi
}

s_outsider() {
  section "Issues outsiders filed that maintainers acted on"
  # Calibration for issue copy: closed-as-completed issues from non-members.
  # `gh issue list` can't return authorAssociation, so this goes through search.
  local j pre_i
  j=$(ghf "completed issues" gh search issues --repo "$repo" --state closed --sort created --order desc --limit 40 \
    ${asof:+--created "<$asof_ts"} --json body,author,authorAssociation,title -- "reason:completed") \
    || { failed "couldn't list completed issues"; return; }
  echo "$j" | jq -r "$JQLIB"'[.[] | select(human) | select(.authorAssociation | IN("CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE")) | (.body // "" | gsub("<!--[\\s\\S]*?-->"; "") | length)] as $l
    | if ($l | length) == 0 then "- none in the sample" else "Median body of completed issues filed by outsiders: \($l | median) chars (n=\($l | length))." end'
  pre_i=$(ghf "pre-LLM issue search" gh search issues --repo "$repo" --created "2015-01-01..2022-11-29" --state closed --limit 60 --json body,authorAssociation \
    | jq "$JQLIB"'[.[] | select(.authorAssociation | IN("CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE")) | (.body // "" | gsub("<!--[\\s\\S]*?-->"; "") | length)] | median' 2>/dev/null)
  [ -n "$pre_i" ] && [ "$pre_i" != "null" ] && echo "Pre-LLM (before Dec 2022) median for closed outsider issues: $pre_i chars."
  return 0
}

s_subjects() {
  section "Last 25 commit subjects on the default branch"
  local url="repos/$repo/commits?per_page=25"
  [ -n "$asof" ] && url="$url&until=$asof_ts"
  ghf "commit subjects" gh api "$url" --jq '.[] | "- \(.commit.author.date[:10]) " + (.commit.message | split("\n")[0])' \
    || failed "couldn't list commits"
}

s_milestones() {
  section "Open milestones"
  if [ -n "$asof" ]; then
    echo "- (not reconstructible for a past date)"
  else
    ghf "milestones" gh api "repos/$repo/milestones?state=open" \
      --jq 'if length == 0 then "- none" else .[] | "- \(.title) (due \(.due_on // "n/a"), \(.open_issues) open / \(.closed_issues) closed)" end' \
      || failed "couldn't list milestones"
  fi
}

s_releases() {
  section "Latest releases"
  # Monorepos tag every package, so page back until 3 releases predate the view.
  local found="" page batch
  for page in 1 2 3 4 5 6 7 8 9 10; do
    batch=$(ghf "releases page $page" gh api "repos/$repo/releases?per_page=100&page=$page") || { failed "couldn't list releases (page $page)"; return; }
    [ "$(echo "$batch" | jq length)" -eq 0 ] && break
    found=$(printf '%s\n%s' "$found" "$(echo "$batch" | jq -r --arg t "$asof_ts" '.[] | select(.published_at != null and .published_at < $t) | "- \(.name // .tag_name) (\(.tag_name), \(.published_at[:10]))\(if .prerelease then ", prerelease" else "" end)"')" | sed '/^$/d')
    [ "$(echo "$found" | sed '/^$/d' | wc -l)" -ge 3 ] && break
  done
  if [ -n "$found" ]; then echo "$found" | head -3
  else
    # No GitHub releases: fall back to tags, dated by their commits.
    ghf "tags" gh api graphql -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){refs(refPrefix:"refs/tags/",first:40,orderBy:{field:TAG_COMMIT_DATE,direction:DESC}){nodes{name target{... on Commit{committedDate} ... on Tag{target{... on Commit{committedDate}}}}}}}}' -f o="${repo%/*}" -f r="${repo#*/}" \
      | jq -r --arg t "$asof_ts" '[.data.repository.refs.nodes[] | {name, d: (.target.committedDate // .target.target.committedDate // "")} | select(.d != "" and .d < $t)][:3]
        | if length == 0 then "- none (no releases or tags)" else .[] | "- tag \(.name) (\(.d[:10]))" end' \
      || failed "couldn't list tags"
  fi
}

# --- Launch, in the order the dump prints ------------------------------------------
if [ -z "$search_only" ]; then
  bg s_repo
  fetch_docs > /dev/null 2>>"$work/stderr" &
  next_slot; docs_slot=$slot
  bg s_policy
  next_slot; gates_slot=$slot
  next_slot; wf_slot=$slot
fi
if [ -n "$issue" ]; then
  bg s_issue
  bg s_mentions
  bg s_linked
fi
if [ -n "$files_arg" ]; then
  bg s_openprs
  bg s_filecommits
fi
for qq in ${queries[@]+"${queries[@]}"}; do
  bg s_qissues "$qq"
  bg s_qprs "$qq"
done
if [ -z "$search_only" ]; then
  bg s_mine
  bg s_merged
  bg s_pre
  bg s_outsider
  bg s_subjects
  bg s_milestones
  bg s_releases
fi
wait
if [ -z "$search_only" ]; then
  s_docs > "$docs_slot"
  s_gates > "$gates_slot"
  s_workflows > "$wf_slot"
fi

echo "# Recon dump: $repo"
echo
if [ -n "$asof" ]; then
  echo "As of $asof_ts (replay). Issues, PRs, commits, and docs after that moment are hidden; titles still show as they read today."
else
  echo "Generated $(date -u +%Y-%m-%dT%H:%MZ). Raw data; the recon note interprets it."
fi
if [ -s "$GH_FAILED" ]; then
  echo
  echo "**LOOKUPS FAILED: $(wc -l < "$GH_FAILED" | tr -d ' ').** The sections marked LOOKUP FAILED below are unknown, not empty. Rerun gather.sh, and check any lookup that fails twice by hand, before deciding GO:"
  sed 's/^/- /' "$GH_FAILED" | head -20
fi
cat "$work"/part.* 2>/dev/null
[ -s "$work/stderr" ] && sed 's/^/gather.sh: /' "$work/stderr" | sort -u | head -20 >&2
[ -s "$GH_FAILED" ] && exit 3
exit 0
