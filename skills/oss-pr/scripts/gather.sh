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

set -uo pipefail

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
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
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

section() { printf '\n## %s\n\n' "$1"; }

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

echo "# Recon dump: $repo"
echo
if [ -n "$asof" ]; then
  echo "As of $asof_ts (replay). Issues, PRs, commits, and docs after that moment are hidden; titles still show as they read today."
else
  echo "Generated $(date -u +%Y-%m-%dT%H:%MZ). Raw data; the recon note interprets it."
fi

# --- Contribution docs ---------------------------------------------------------
DOC_RE='(^|/)((CONTRIBUTING|CODE_OF_CONDUCT|GOVERNANCE|ROADMAP|SECURITY|STYLE|STYLEGUIDE|HACKING|DEVELOPMENT|MAINTAINERS|AI_POLICY|AGENTS|CLAUDE|TRIAGE|DCO|CLA)(\.(md|rst|txt|adoc))?|CODEOWNERS|VOUCHED[^/]*|\.editorconfig)$|^\.github/(PULL_REQUEST_TEMPLATE|ISSUE_TEMPLATE)|pull_request_template'
WF_RE='pr|pull|triage|title|description|semantic|label|close|stale|vouch|cla|lint-pr|welcome|first'

if [ -z "$search_only" ]; then
  section "Repo"
  gh repo view "$repo" --json defaultBranchRef,description,isArchived,stargazerCount \
    -q '"- default branch: \(.defaultBranchRef.name)\n- archived today: \(.isArchived)\n- stars today: \(.stargazerCount)\n- description: \(.description)"'

  if [ "$mode" = "local" ]; then
    ref="HEAD"; files=$(git ls-files 2>/dev/null); docroot="."
  else
    if [ -n "$asof" ]; then
      ref=$(gh api "repos/$repo/commits?until=${asof_ts}&per_page=1" --jq '.[0].sha' 2>/dev/null)
    else
      ref=$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].sha' 2>/dev/null)
    fi
    # Root listing plus the whole .github tree; a full recursive tree truncates on big repos.
    root=$(gh api "repos/$repo/git/trees/$ref" --jq '.tree[] | "\(.type) \(.path) \(.sha)"' 2>/dev/null)
    files=$(echo "$root" | awk '$1=="blob"{print $2}')
    gh_sha=$(echo "$root" | awk '$2==".github"{print $3}')
    if [ -n "$gh_sha" ]; then
      files="$files
$(gh api "repos/$repo/git/trees/$gh_sha?recursive=1" --jq '.tree[] | select(.type=="blob") | ".github/" + .path' 2>/dev/null)"
    fi
    docroot=$(mktemp -d); tmpdirs="$docroot"
    # Mirror doc-like files, plus workflows whose names suggest PR policing, so grep can scan them.
    { echo "$files" | grep -iE "$DOC_RE|^[^/]+\.(md|rst|txt)$|^\.github/[^/]*\.md$|^\.github/(ISSUE_TEMPLATE|DISCUSSION_TEMPLATE)/" | grep -v '^\.github/workflows/' | head -60
      echo "$files" | grep -E '^\.github/workflows/' | grep -iE "$WF_RE" | head -25; } \
    | while IFS= read -r f; do
        mkdir -p "$docroot/$(dirname "$f")"
        gh api -H "Accept: application/vnd.github.raw" "repos/$repo/contents/$f?ref=$ref" > "$docroot/$f" 2>/dev/null
      done
  fi

  section "Contribution docs ($mode, at ${ref:0:10})"
  docs=$(echo "$files" | grep -iE "$DOC_RE")
  if [ -n "$docs" ]; then echo "$docs" | sed 's/^/- /'; else echo "- (none found)"; fi
  wf=$(echo "$files" | grep -E '^\.github/workflows/' | sed 's#.*/##' | tr '\n' ' ')
  [ -n "$wf" ] && echo "- CI workflows: $wf"
  [ "$mode" = "remote" ] && echo "- (remote mode lists root and .github only; per-directory AGENTS.md and docs/ or website/ pages show up once you clone, or fetch them by path)"

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

  echo
  poldir=$(mktemp -d); tmpdirs="${tmpdirs:-} $poldir"
  # Remove only directories this script made with mktemp; never the clone (local mode's docroot is ".").
  trap 'for d in $tmpdirs; do case "$d" in "${TMPDIR:-/tmp}"*|/tmp/*|/var/folders/*) rm -rf "$d" ;; esac; done' EXIT
  bash "$(dirname "$0")/policy.sh" --repo "$repo" ${asof:+--as-of "$asof_ts"} --keep "$poldir"
  echo

  section "Contributor gates (discussion-first, DCO, CLA, vouching)"
  GATE_RE='engage (on|in|with) the (issue|discussion)|(open|create|file|start) an? (issue|discussion|feature request)[^.]{0,60}(first|before|prior)|before (writing|starting|you (write|start)|opening|submitting|sending) (any |your )?(code|a PR|a pull request|work)|discuss[^.]{0,40}(first|before|prior)|non-trivial|signed-off-by|developer certificate of origin|\bDCO\b|contributor license agreement|\bCLA\b|vouch|unsolicited|drive-by'
  gates=$( { docgrep 'engage (on|in|with) the (issue|discussion)|(open|create|file|start) an? (issue|discussion|feature request)[^.]{0,60}(first|before|prior)|before (writing|starting|you (write|start)|opening|submitting|sending) (any |your )?(code|a PR|a pull request|work)|discuss[^.]{0,40}(first|before|prior)|non-trivial|signed-off-by|developer certificate of origin|\bDCO\b|contributor license agreement|\bCLA\b|vouch|unsolicited|drive-by' \
    ; (cd "$poldir" && grep -rn -i -E "$GATE_RE" . 2>/dev/null | grep -v '/\.github/[^:]*:' | sed 's#^\./#(linked or org) #'); } | sort -u | cut -c1-300 | head -30)
  if [ -n "$gates" ]; then echo '```'; echo "$gates"; echo '```'; else echo "- none found by pattern; read CONTRIBUTING's section on issues and PRs anyway"; fi

  section "Workflows that police PRs (body, title, labels, auto-close)"
  pol=$(wfgrep 'pull_request(_target)?\.(body|title)|github\.event\.pull_request\.body|validate[-_ ]?pr|pr[-_ ]?(description|title|body)|semantic-pull-request|auto[-_ ]?close|close[-_ ]?(pr|pull)|actions/stale|vouch|cla[-_ ]?(assistant|bot)|required.*(heading|section|checkbox)' \
    | cut -c1-240 | head -20)
  if [ -n "$pol" ]; then echo '```'; echo "$pol"; echo '```'; else echo "- none found"; fi
fi

# --- The issue -----------------------------------------------------------------
if [ -n "$issue" ]; then
  section "Issue #$issue"
  gh issue view "$issue" -R "$repo" \
    --json title,state,stateReason,closedAt,author,labels,createdAt,url,comments \
    | jqa '
      ([.comments[] | select(.createdAt < $t)]) as $c
      | ([$c[] | select(maint and ((.author.login // "") | test("bot"; "i") | not))]) as $m
      | (if $t == "9999" then now else ($t | fromdateiso8601) end) as $now
      | (($now - (.createdAt | fromdateiso8601)) / 3600) as $h
      | "- \(.title)\n- opened \(.createdAt[:16])Z by \(.author.login)\(if .author.login == $me then " (you)" else "" end), \(if $h < 48 then "\($h | floor) hours" else "\($h / 24 | floor) days" end) before this view\n- state then: \(state_asof($t))\(reason_asof($t))\n- labels: \([.labels[].name] | join(", "))\n- comments before then: \($c | length), from maintainers (OWNER/MEMBER/COLLABORATOR, non-bot): \($m | length)\n- url: \(.url)\n\nLast 6 comments before then:",
        (if ($c | length) == 0 then "- (none)" else ($c[-6:][] | "- **\(.author.login)**\(if .author.login == $me then " (you)" else "" end) (\(.authorAssociation), \(.createdAt[:10])): \(.body | gsub("\\s+"; " ") | .[:600])") end)'
  echo
  echo "(authorAssociation can understate: an active maintainer may show as CONTRIBUTOR. Check who merges PRs in the list below.)"

  section "PRs mentioning #$issue"
  gh pr list -R "$repo" --state all --search "\"#$issue\"$before" --limit 15 \
    --json number,title,state,mergedAt,closedAt,isCrossRepository,author,url | drop_ex \
    | jqa 'if length == 0 then "- (none)" else .[] | "- #\(.number) [\(state_asof($t))] \(.title) (by \(.author.login)\(if .isCrossRepository then ", from fork" else "" end)) \(.url)" end'
fi

# --- Open PRs and recent commits touching your files ----------------------------
if [ -n "$files_arg" ]; then
  section "Open PRs touching your files"
  # Every PR open at that moment: still open and created before it, or closed after it.
  if [ -n "$asof" ]; then qs="repo:$repo is:pr is:open created:<$asof_ts|repo:$repo is:pr is:closed closed:>$asof_ts created:<$asof_ts"
  else qs="repo:$repo is:pr is:open"; fi
  allopen="[]"
  IFS='|'; for q in $qs; do unset IFS
    cursor="null"
    for page in $(seq 1 20); do  # GitHub search stops at 1,000 results
      res=$(gh api graphql -f query='query($q:String!,$c:String){search(query:$q,type:ISSUE,first:50,after:$c){pageInfo{hasNextPage endCursor} nodes{... on PullRequest{number title url state createdAt mergedAt closedAt author{login} files(first:100){nodes{path}}}}}}' -f q="$q" $( [ "$cursor" != "null" ] && echo -f c="$cursor" ) 2>/dev/null) || break
      allopen=$(jq -s '.[0] + [.[1].data.search.nodes[] | select(.number != null)]' <(echo "$allopen") <(echo "$res"))
      [ "$(echo "$res" | jq -r .data.search.pageInfo.hasNextPage)" = "true" ] || break
      cursor=$(echo "$res" | jq -r .data.search.pageInfo.endCursor)
    done
  done; unset IFS
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
      (if ($rows | length) == 0 then "- none" else ($rows[:12][] | "- #\(.number) \(.title) (by \(.who)) touches \(if (.core | length) > 0 then (.core | join(", ")) else "only busy files: " + (.hit | join(", ")) end) \(.url)") end)'
  echo
  echo "Recent commits on each file (lineage: who shaped these lines, and why):"
  echo "$files_arg" | tr ',' '\n' | while IFS= read -r f; do
    [ -z "$f" ] && continue
    url="repos/$repo/commits?path=$f&per_page=5"
    [ -n "$asof" ] && url="$url&until=$asof_ts"
    echo "- \`$f\`"
    gh api "$url" --jq '.[] | "  - \(.sha[:10]) \(.commit.author.date[:10]) \(.author.login // .commit.author.name): \(.commit.message | split("\n")[0])"' 2>/dev/null || echo "  - (lookup failed)"
  done
fi

# --- Duplicates and rejected attempts ------------------------------------------
for qq in ${queries[@]+"${queries[@]}"}; do
  section "Issues matching: $qq"
  gh issue list -R "$repo" --state all --search "$qq$before" --limit 20 \
    --json number,title,state,stateReason,closedAt,url | drop_ex \
    | jqa 'if length == 0 then "- (none)" else .[] | "- #\(.number) [\(state_asof($t))\(reason_asof($t))] \(.title) \(.url)" end'

  section "PRs matching: $qq"
  prs=$(gh pr list -R "$repo" --state all --search "$qq$before" --limit 20 \
    --json number,title,state,mergedAt,closedAt,isCrossRepository,author,url | drop_ex \
    | jq --arg t "$asof_ts" "$JQLIB"'map(.asof = state_asof($t))')
  echo "$prs" | jq -r 'if length == 0 then "- (none)" else .[] | "- #\(.number) [\(.asof)] \(.title) (by \(.author.login)\(if .isCrossRepository then ", from fork" else "" end)) \(.url)" end'

  # Open matches may already be doing your change. Show what they touch and how review stands.
  open=$(echo "$prs" | jq -r '.[] | select(.asof == "OPEN") | .number' | head -6)
  if [ -n "$open" ]; then
    echo
    echo "Open matches in detail (files, and reviews before then):"
    for n in $open; do
      gh pr view "$n" -R "$repo" --json files,reviews,comments \
        | jqa --arg n "$n" '"- #\($n): \([.files[].path][:8] | join(", "))\(if (.files | length) > 8 then " (+\((.files | length) - 8) more)" else "" end); reviews: \([.reviews[] | select(.submittedAt < $t) | "\(.author.login) \(.state)"] | if length == 0 then "none" else join(", ") end)",
          ([.comments[] | select(.createdAt < $t) | select(maint) | select((.author.login // "") | test("bot"; "i") | not)][-2:][] | "    - maintainer **\(.author.login)** (\(.createdAt[:10])): \(.body | gsub("\\s+"; " ") | .[:300])")'
    done
  fi

  # Closed-without-merge PRs are the rejected attempts. The last comment before
  # then is usually the maintainer's reason: the most valuable line in recon.
  echo
  echo "Last comment on each closed, unmerged match (likely the rejection reason):"
  closed=$(echo "$prs" | jq -r '.[] | select(.asof == "CLOSED") | .number' | head -6)
  [ -z "$closed" ] && echo "- (none)"
  for n in $closed; do
    gh pr view "$n" -R "$repo" --json comments \
      | jqa --arg n "$n" '[.comments[] | select(.createdAt < $t)]
        | if length > 0 then .[-1] | "- #\($n) **\(.author.login)** (\(.authorAssociation)): \(.body | gsub("\\s+"; " ") | .[:500])" else "- #\($n) (closed with no comment)" end'
  done
done

[ -n "$search_only" ] && exit 0

# --- Your history here ---------------------------------------------------------
section "Your PRs in this repo before then"
mine=$(gh pr list -R "$repo" --author "@me" --state all --search "sort:created-desc$before" --limit 10 \
  --json number,title,state,mergedAt,closedAt,url | drop_ex | jq --arg t "$asof_ts" "$JQLIB"'map(.asof = state_asof($t))')
echo "$mine" | jq -r 'if length == 0 then "- none (first contribution)" else .[] | "- #\(.number) [\(.asof)] \(.title) \(.url)" end'
for n in $(echo "$mine" | jq -r '.[] | select(.asof == "CLOSED") | .number' | head -4); do
  gh pr view "$n" -R "$repo" --json comments | jqa --arg n "$n" '[.comments[] | select(.createdAt < $t) | select(.author.login != $me)] | if length > 0 then .[-1] | "  - why #\($n) closed, last word from **\(.author.login)**: \(.body | gsub("\\s+"; " ") | .[:300])" else "  - #\($n) closed with no comment from others" end'
done

# --- What this team accepts ----------------------------------------------------
section "Last 30 merged PRs (what this team accepts)"
merged_q="is:merged"
[ -n "$asof" ] && merged_q="is:merged merged:<$asof_ts"
merged=$(gh pr list -R "$repo" --state merged --search "$merged_q" --limit 30 \
  --json number,title,author,isCrossRepository,additions,deletions,changedFiles,body,mergedAt)
echo "$merged" | jqa '.[] | select(human) | "- #\(.number) \(.mergedAt[:10]) \(.title) | by \(.author.login)\(if .isCrossRepository then " (fork)" else "" end) | +\(.additions)/-\(.deletions) in \(.changedFiles) files | body \(.body | length) chars"'
echo
echo "$merged" | jqa '
  [.[] | select(human)] as $h | [$h[] | select(.isCrossRepository)] as $o
  | "Bots and release PRs left out: \(length - ($h | length)) of \(length).",
    "Human median body: \([$h[].body | length] | median // "n/a") chars (n=\($h | length)). Outside-contributor median: \([$o[].body | length] | median // "n/a") chars (n=\($o | length)).",
    "Last merged PR from a fork: \(if ($o | length) > 0 then $o[0].mergedAt[:10] else "none in this window" end)."'

section "Pre-LLM baseline: outside contributors' merged PRs before Dec 2022"
# ChatGPT launched 2022-11-30. PR text before then is the cleanest sample of how
# this repo's human contributors wrote, and the length target for PR copy.
pre=$(gh search prs --repo "$repo" --merged --created "2015-01-01..2022-11-29" --sort created --order desc \
  --limit 80 --json title,body,author,authorAssociation,url 2>/dev/null \
  | jq "$JQLIB"'[.[] | select(human) | select(.authorAssociation | IN("CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE"))
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

section "Issues outsiders filed that maintainers acted on"
# Calibration for issue copy: closed-as-completed issues from non-members.
iss_q="is:issue is:closed reason:completed"
[ -n "$asof" ] && iss_q="$iss_q created:<$asof_ts"
gh issue list -R "$repo" --state closed --search "$iss_q" --limit 40 --json body,author,authorAssociation 2>/dev/null \
  | jq -r "$JQLIB"'[.[] | select(human) | select(.authorAssociation | IN("CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE")) | (.body // "" | gsub("<!--[\\s\\S]*?-->"; "") | length)] as $l
    | if ($l | length) == 0 then "- none in the sample" else "Median body of outsiders\u0027 completed issues: \($l | median) chars (n=\($l | length))." end'
pre_i=$(gh search issues --repo "$repo" --created "2015-01-01..2022-11-29" --state closed --limit 60 --json body,authorAssociation 2>/dev/null \
  | jq "$JQLIB"'[.[] | select(.authorAssociation | IN("CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE")) | (.body // "" | gsub("<!--[\\s\\S]*?-->"; "") | length)] | median' 2>/dev/null)
[ -n "$pre_i" ] && [ "$pre_i" != "null" ] && echo "Pre-LLM (before Dec 2022) median for closed outsider issues: $pre_i chars."

section "Last 25 commit subjects on the default branch"
url="repos/$repo/commits?per_page=25"
[ -n "$asof" ] && url="$url&until=$asof_ts"
gh api "$url" --jq '.[] | "- \(.commit.author.date[:10]) " + (.commit.message | split("\n")[0])'

section "Open milestones"
if [ -n "$asof" ]; then
  echo "- (not reconstructible for a past date)"
else
  gh api "repos/$repo/milestones?state=open" \
    --jq 'if length == 0 then "- none" else .[] | "- \(.title) (due \(.due_on // "n/a"), \(.open_issues) open / \(.closed_issues) closed)" end'
fi

section "Latest releases"
# Monorepos tag every package, so page back until 3 releases predate the view.
found=""
for page in 1 2 3 4 5 6 7 8 9 10; do
  batch=$(gh api "repos/$repo/releases?per_page=100&page=$page" 2>/dev/null) || break
  [ "$(echo "$batch" | jq length)" -eq 0 ] && break
  found=$(printf '%s\n%s' "$found" "$(echo "$batch" | jq -r --arg t "$asof_ts" '.[] | select(.published_at != null and .published_at < $t) | "- \(.name // .tag_name) (\(.tag_name), \(.published_at[:10]))\(if .prerelease then ", prerelease" else "" end)"')" | sed '/^$/d')
  [ "$(echo "$found" | sed '/^$/d' | wc -l)" -ge 3 ] && break
done
if [ -n "$found" ]; then echo "$found" | head -3
else
  # No GitHub releases: fall back to tags, dated by their commits.
  gh api graphql -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){refs(refPrefix:"refs/tags/",first:40,orderBy:{field:TAG_COMMIT_DATE,direction:DESC}){nodes{name target{... on Commit{committedDate} ... on Tag{target{... on Commit{committedDate}}}}}}}}' -f o="${repo%/*}" -f r="${repo#*/}" 2>/dev/null \
    | jq -r --arg t "$asof_ts" '[.data.repository.refs.nodes[] | {name, d: (.target.committedDate // .target.target.committedDate // "")} | select(.d != "" and .d < $t)][:3]
      | if length == 0 then "- none (no releases or tags)" else .[] | "- tag \(.name) (\(.d[:10]))" end'
fi
