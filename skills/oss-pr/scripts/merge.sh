#!/usr/bin/env bash
# Is this PR ready for you to merge, and can a maintainer take it back out in one step?
#
#   merge.sh [<number> | <url> | <branch>] [-R owner/name] [--squash | --merge | --rebase] [--ledger DIR]
#
# For repos where merging is up to you: you have write access, or the maintainers leave the
# merge to the author. Nobody else reads the PR between your yes and the merge, so this asks
# what a maintainer would, and prints the open review comments first:
#
#   - Every comment someone else left needs a verdict in the ledger's comments.md, one line
#     each, keyed by the comment's URL (for a review thread, its first comment's URL):
#       <url> AGREED <sha>             the PR commit that made the change, committed after the comment
#       <url> DISAGREED <evidence>...  and a reply in the thread after the comment. Evidence is a
#                                      GitHub blob link at a full SHA with #L lines, a link to a
#                                      maintainer's comment, review, issue, or PR, or run:<N>, the
#                                      Nth entry in runs.log (receipt.sh run)
#       <url> NOTHING ASKED            a top-level comment with no question in it ("LGTM", "thanks")
#     A thread someone else resolved needs none. Bots' top-level summaries are skipped; their
#     inline threads aren't.
#   - A change request from anyone with write access blocks until they re-review; a
#     disagreement, however well argued, doesn't overrule one.
#   - The ledger's phases (next.sh --all) hold on the PR's head commit, so a fix pushed for a
#     comment has been proven like the rest.
#   - The revert route: the merge lands as one commit, the PR body says how to revert it, and
#     anything a revert can't undo (migrations, release and version files, workflows) is listed.
#     A PR with any of those also needs an approval from someone else with write access.
#
# Exit 0 when ready, 1 when something blocks, 2 on bad arguments or a failed lookup. Read-only.

set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
sel="" repo="" method="" ledger=""
while [ $# -gt 0 ]; do
  case "$1" in
    -R|--repo) repo="$2"; shift 2 ;;
    -s|--squash) method=SQUASH; shift ;;
    -m|--merge) method=MERGE; shift ;;
    -r|--rebase) method=REBASE; shift ;;
    --ledger) ledger="$2"; shift 2 ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    -*) echo "merge.sh: unknown argument $1" >&2; exit 2 ;;
    *) sel="$1"; shift ;;
  esac
done

pv=$(gh pr view ${sel:+"$sel"} ${repo:+-R "$repo"} --json number,url 2>&1) || { echo "merge.sh: $pv" >&2; exit 2; }
n=$(jq -r .number <<< "$pv")
url=$(jq -r .url <<< "$pv")
repo=$(printf '%s' "$url" | sed -E 's#^https://github.com/([^/]+/[^/]+)/pull/.*#\1#')

q='query($owner: String!, $name: String!, $n: Int!) { viewer { login } repository(owner: $owner, name: $name) {
  viewerDefaultMergeMethod squashMergeAllowed mergeCommitAllowed rebaseMergeAllowed
  pullRequest(number: $n) { state headRefName headRefOid body
    commits(last: 100) { totalCount nodes { commit { oid committedDate } } }
    files(first: 100) { totalCount nodes { path } }
    comments(first: 100) { totalCount nodes { url createdAt body author { __typename login } } }
    reviews(first: 100) { totalCount nodes { url state submittedAt body author { __typename login } } }
    latestOpinionatedReviews(first: 50, writersOnly: true) { nodes { state url author { login } } }
    reviewThreads(first: 100) { totalCount nodes { isResolved resolvedBy { login } path line originalLine
      comments(first: 50) { nodes { url createdAt body author { __typename login } } } } } } } }'
data=$(gh api graphql -f query="$q" -f owner="${repo%%/*}" -f name="${repo#*/}" -F n="$n" --jq .data 2>&1) \
  || { echo "merge.sh: couldn't read $url: $data" >&2; exit 2; }
me=$(jq -r .viewer.login <<< "$data")
pr=$(jq -c .repository.pullRequest <<< "$data")
head_branch=$(jq -r .headRefName <<< "$pr")
head_sha=$(jq -r .headRefOid <<< "$pr")
[ -n "$ledger" ] || ledger="$(git rev-parse --git-dir 2>/dev/null)/houseguest/$head_branch"
[ "$(jq -r .state <<< "$pr")" = "OPEN" ] || { echo "merge.sh: $url is $(jq -r .state <<< "$pr" | tr 'A-Z' 'a-z'), not open" >&2; exit 2; }

blocks=0
block() { blocks=$((blocks + 1)); }

# Each comment that wants an answer, as: key, who, where, when it last wanted one, whether
# NOTHING ASKED can answer it, whether you replied after, and an excerpt.
items=$(jq -r --arg me "$me" '
  def who: .author.login // "ghost";
  def isbot: (.author.__typename // "") == "Bot" or (who | test("\\[bot\\]$"));
  def short: (.body // "") | gsub("\\s+"; " ") | .[:160];
  ([.comments.nodes[], .reviews.nodes[] | select(who == $me) | .createdAt // .submittedAt]) as $mine
  | (.reviewThreads.nodes[]
      | select(.comments.nodes[0] | who != $me)
      | select((.isResolved and ((.resolvedBy.login // $me) != $me)) | not)
      | .comments.nodes as $c
      | ([$c[] | select(who != $me) | .createdAt] | max) as $last
      | [$c[0].url, ($c[0] | who), "thread \(.path):\(.line // .originalLine // "?")", $last, "0",
         (if any($c[]; who == $me and .createdAt > $last) then "1" else "0" end), ($c[0] | short)]),
    ((.comments.nodes[] | select(who != $me and (isbot | not)) | {url, who: who, kind: "comment", at: .createdAt, body, cr: false}),
     (.reviews.nodes[] | select(who != $me and (isbot | not)) | select((.body // "") != "" or .state == "CHANGES_REQUESTED")
       | {url, who: who, kind: "review, \(.state | ascii_downcase | gsub("_"; " "))", at: .submittedAt, body, cr: (.state == "CHANGES_REQUESTED")})
     | . as $it
     | [.url, .who, .kind, .at, (if .cr or ((.body // "") | test("\\?")) then "0" else "1" end),
        (if any($mine[]; . > $it.at) then "1" else "0" end), short])
  | @tsv' <<< "$pr")
commits=$(jq -r '.commits.nodes[] | "\(.commit.oid)\t\(.commit.committedDate)"' <<< "$pr")

verdict() { awk -v k="$1" '$1 == k { v = $0 } END { sub(/^[^ ]+ +/, "", v); print v }' "$ledger/comments.md" 2>/dev/null; }

# check_evidence <token>: prints what it found; returns 0 only when the token checks out.
check_evidence() {
  local t="$1" r path from to lines kind id api assoc login
  if [[ "$t" =~ ^run:([0-9]+)$ ]]; then
    lines=$(bash "$here/receipt.sh" verify "$ledger/runs.log" 2>&1) || { echo "$t: runs.log: $lines"; return 1; }
    from=$(printf '%s\n' "$lines" | sed -n "${BASH_REMATCH[1]}p")
    [ -n "$from" ] || { echo "$t: runs.log has no entry ${BASH_REMATCH[1]}"; return 1; }
    echo "$t: $from"; return 0
  fi
  if [[ "$t" =~ ^https://github\.com/([^/]+/[^/]+)/blob/([0-9a-f]{40})/([^#]+)#L([0-9]+)(-L([0-9]+))?$ ]]; then
    r="${BASH_REMATCH[1]}" path="${BASH_REMATCH[3]}" from="${BASH_REMATCH[4]}" to="${BASH_REMATCH[6]:-${BASH_REMATCH[4]}}"
    lines=$(gh api -H "Accept: application/vnd.github.raw" "repos/$r/contents/$path?ref=${BASH_REMATCH[2]}" 2>/dev/null | awk 'END { print NR }')
    [ "${lines:-0}" -ge "$to" ] && [ "$from" -ge 1 ] && { echo "$t: lines $from-$to exist"; return 0; }
    echo "$t: $path has ${lines:-no} lines at that commit"; return 1
  fi
  if [[ "$t" =~ ^https://github\.com/([^/]+/[^/]+)/(issues|pull)/([0-9]+)(#(issuecomment-|discussion_r|pullrequestreview-)([0-9]+))?$ ]]; then
    r="${BASH_REMATCH[1]}" kind="${BASH_REMATCH[5]}" id="${BASH_REMATCH[6]}"
    case "$kind" in
      issuecomment-) api="repos/$r/issues/comments/$id" ;;
      discussion_r) api="repos/$r/pulls/comments/$id" ;;
      pullrequestreview-) api="repos/$r/pulls/${BASH_REMATCH[3]}/reviews/$id" ;;
      *) api="repos/$r/issues/${BASH_REMATCH[3]}" ;;
    esac
    read -r assoc login < <(gh api "$api" --jq '"\(.author_association) \(.user.login)"' 2>/dev/null)
    case "$assoc" in
      OWNER|MEMBER|COLLABORATOR)
        [ "$login" != "$me" ] && { echo "$t: by $login ($assoc)"; return 0; }
        echo "$t: that's your own words, which can't settle your own disagreement"; return 1 ;;
      "") echo "$t: couldn't read it"; return 1 ;;
      *) echo "$t: by $login ($assoc), not a maintainer"; return 1 ;;
    esac
  fi
  echo "$t: not checkable (use a blob link at a full SHA with #L lines, a maintainer's link, or run:<N>)"; return 1
}

echo "PR: $url ($head_branch, $(jq -r .commits.totalCount <<< "$pr") commits)"
echo "Ledger: $ledger"
echo

# Comments come first: they're what a maintainer would ask about before anything else.
for what in reviewThreads comments reviews; do
  c=$(jq -r ".$what.totalCount" <<< "$pr")
  [ "$c" -gt 100 ] && { echo "Read only 100 of $c $what; the rest are unknown, not answered. Answer them on the PR, then rerun."; block; }
done
open_out="" open_n=0
while IFS=$'\t' read -r key who where at askable replied excerpt; do
  [ -n "$key" ] || continue
  v=$(verdict "$key") problem="" found=""
  case "$v" in
    "") problem="no verdict in comments.md" ;;
    AGREED*)
      sha=$(printf '%s' "$v" | awk '{print $2}')
      if [ "${#sha}" -lt 7 ]; then problem="AGREED needs the fixing commit's SHA (7 characters or more)"
      else
        when=$(printf '%s\n' "$commits" | awk -F'\t' -v s="$sha" 'index($1, s) == 1 { print $2; exit }')
        if [ -z "$when" ]; then problem="$sha isn't a commit on this PR"
        elif [[ ! "$when" > "$at" ]]; then problem="$sha was committed at $when, before the comment ($at)"
        fi
      fi ;;
    DISAGREED*)
      ok=""
      for t in $(printf '%s' "$v" | cut -d' ' -f2-); do
        line=$(check_evidence "$t") && ok=1
        found="${found}      $line
"
      done
      if [ -z "$ok" ]; then problem="DISAGREED with no evidence that checks out"
      elif [ "$replied" != 1 ]; then problem="no reply from you after the comment: post the disagreement and its evidence there first"
      fi ;;
    "NOTHING ASKED"*) [ "$askable" = 1 ] || problem="NOTHING ASKED doesn't fit an inline thread, a change request, or a comment with a question in it" ;;
    *) problem="unknown verdict '$v': use AGREED, DISAGREED, or NOTHING ASKED" ;;
  esac
  [ -n "$problem" ] || continue
  open_n=$((open_n + 1)); block
  open_out="${open_out}- $key
    $who, $where, $at: $excerpt
    blocks: $problem
${found}"
done <<< "$items"
echo "OPEN COMMENTS: $open_n"
[ -n "$open_out" ] && printf '%s' "$open_out"

cr=$(jq -r --arg me "$me" '.latestOpinionatedReviews.nodes[] | select(.state == "CHANGES_REQUESTED" and .author.login != $me) | "- \(.author.login): \(.url)"' <<< "$pr")
if [ -n "$cr" ]; then
  echo
  echo "CHANGES REQUESTED, still standing (ask each to re-review; a disagreement doesn't overrule them):"
  echo "$cr"
  block
fi

echo
if [ ! -d "$ledger" ]; then
  echo "LEDGER: no oss-pr ledger at $ledger"; block
elif [ "$(git branch --show-current 2>/dev/null)" != "$head_branch" ]; then
  echo "LEDGER: check out $head_branch so the ledger can be checked against the PR's head"; block
elif [ "$(git rev-parse HEAD)" != "$head_sha" ]; then
  echo "LEDGER: local HEAD $(git rev-parse --short HEAD) isn't the PR's head ${head_sha:0:7}: push or pull, then rerun"; block
elif phases=$(bash "$here/next.sh" --all "$ledger"); then
  echo "LEDGER: every phase holds on ${head_sha:0:7}"
else
  echo "LEDGER: phases that don't hold on ${head_sha:0:7}:"
  printf '%s\n' "$phases" | sed '/^$/d; s/^/- /'
  block
fi

# The revert route. A merge that lands as one commit comes back out as one revert, through the
# PR's Revert button or one command. Anything that acts outside the repo stays done after it.
echo
echo "REVERT ROUTE:"
[ -n "$method" ] || method=$(jq -r .repository.viewerDefaultMergeMethod <<< "$data")
allowed=$(jq -r '.repository | [if .squashMergeAllowed then "SQUASH" else empty end, if .mergeCommitAllowed then "MERGE" else empty end, if .rebaseMergeAllowed then "REBASE" else empty end] | join(" ")' <<< "$data")
ncommits=$(jq -r .commits.totalCount <<< "$pr")
case " $allowed " in *" $method "*) ;; *) echo "- $method merges aren't allowed here (allowed: $allowed)"; block ;; esac
case "$method" in
  SQUASH) echo "- lands as one squash commit: the PR's Revert button, or \`git revert <that commit>\`, takes all of it out" ;;
  MERGE) echo "- lands as one merge commit: the PR's Revert button, or \`git revert -m 1 <that commit>\`, takes all of it out" ;;
  REBASE)
    if [ "$ncommits" -gt 1 ]; then echo "- rebasing lands $ncommits commits, so taking it out means $ncommits reverts in order: squash the branch to one commit, or merge with --squash"; block
    else echo "- lands as one commit: the PR's Revert button, or \`git revert <that commit>\`, takes all of it out"; fi ;;
esac
[ "$(jq -r .files.totalCount <<< "$pr")" -gt 100 ] && { echo "- read only 100 of the changed files; check the rest for migrations and release files by hand"; block; }
lasting=$(jq -r '.files.nodes[].path' <<< "$pr" | awk '
  /(^|\/)(migrations?|migrate|alembic)\// || /\.sql$/ { print "- " $0 ": a migration that ran stays run"; next }
  /^\.changeset\// { print "- " $0 ": queues a release; a published version stays published"; next }
  /^\.github\/workflows\// { print "- " $0 ": a workflow change; whatever it ran or deployed stays done"; next }')
bumps=$(gh pr diff "$n" -R "$repo" 2>/dev/null | awk '
  /^diff --git / { f = $NF; sub(/^b\//, "", f); next }
  f ~ /(^|\/)(package\.json|Cargo\.toml|pyproject\.toml)$/ && /^\+[[:space:]]*"?version"?[[:space:]]*[:=]/ { print "- " f ": bumps the version; a release cut from it stays out" }' | sort -u)
lasting=$(printf '%s\n%s\n' "$lasting" "$bumps" | sed '/^$/d')
if [ -n "$lasting" ]; then
  echo "- a revert can't undo what these do once merged; the PR body's revert sentence should name them:"
  printf '%s\n' "$lasting" | sed 's/^/  /'
  # With no one-step way back, the merge isn't one to make before a maintainer has looked.
  approved=$(jq -r --arg me "$me" '[.latestOpinionatedReviews.nodes[] | select(.state == "APPROVED" and .author.login != $me) | .author.login] | join(", ")' <<< "$pr")
  if [ -n "$approved" ]; then echo "- approved by a maintainer with write access: $approved"
  else echo "- so a maintainer with write access approves it before you merge; none has yet"; block; fi
else
  echo "- nothing in the diff acts outside the repo (no migrations, release files, version bumps, or workflows)"
fi
if jq -r .body <<< "$pr" | grep -q -i 'revert'; then
  echo "- the PR body says how to revert"
else
  echo "- the PR body doesn't say how to revert: add \"The revert sentence\" from pr-copy.md"; block
fi

echo
if [ "$blocks" -eq 0 ]; then
  echo "STATUS: READY. Show the user the merge command and wait for a yes."
  exit 0
fi
echo "STATUS: BLOCKED ($blocks)"
exit 1
