#!/usr/bin/env bash
# What did each houseguest job spend, and how did its PR end?
#
#   outcomes.sh [--json] [--log FILE]
#
# Joins the phase log hooks/meter.sh keeps to GitHub. A job is one repo and branch that ran a
# phase. Each row gives the PR you opened from that branch, how it ended, the days until it
# merged or closed, how many reviews asked for changes, and what the phases spent: runs, review
# rounds, output tokens, input tokens (fresh plus cache writes), and cache reads. The last line
# is output tokens per merged PR across every job listed, the number a prompt or phase change
# should move.
#
# LANDED is a PR the maintainers closed after committing it by hand: a commit in their repo,
# authored by you, cites the PR. On driceroland/Search that was 59 of 82 closed PRs, beside 12
# merged with the button (2026-11-10), so GitHub's own state misses 5 of every 6 that got in.
#
# A branch with no PR of yours upstream says "none": an issue-only job, a job recon stopped, or a
# PR not opened yet. A run whose prompt named no ledger, in a session that named several, sits
# under the branch its session started on, so a job's tokens are a floor in a session that ran
# more than one. A job with no clone on GitHub says "no GitHub remote". Jobs on repos you own are
# counted and left out.
# --json prints one object per job. Read-only; needs gh and jq. Exits 3 when a GitHub lookup
# failed, and marks that job LOOKUP FAILED, since a failed lookup isn't "none".

set -uo pipefail
. "$(dirname "$0")/lib.sh"
json="" log="${HOUSEGUEST_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/houseguest}/phases.jsonl"
while [ $# -gt 0 ]; do
  case "$1" in
    --json) json=1; shift ;;
    --log) log="$2"; shift 2 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "outcomes.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -s "$log" ] || { echo "outcomes.sh: no phase log at $log (hooks/meter.sh writes it as phases finish)" >&2; exit 1; }
me=$(gh api user --jq .login 2>/dev/null)
[ -n "$me" ] || { echo "outcomes.sh: gh isn't authenticated" >&2; exit 1; }
GH_FAILED=$(mktemp); parents=$(mktemp -d); trap 'rm -rf "$GH_FAILED" "$parents"' EXIT
export GH_FAILED

# A run measured twice keeps its last counts, and the first job any of its lines knew: a later
# measurement can come after the worktree is gone. A run with no ledger joins its session's job
# when the session named exactly one. Runs with no remote group by the directory they ran in.
jobs=$(jq -s -c '
  def at: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
  def job: {remote, branch, ledger};
  group_by(.agent) | map(.[-1] + ((map(select(.ledger)) + map(select(.remote)) + .)[0] | job))
  | (map(select(.ledger)) | group_by(.session) | map({key: .[0].session, value: (map(job) | unique)}) | from_entries) as $named
  | map(if .ledger == null and ($named[.session] | length) == 1 then . + $named[.session][0] else . end)
  | group_by([.remote // .cwd, .branch]) | map({
      remote: .[0].remote, cwd: .[0].cwd, branch: .[0].branch, first: (map(.start) | min),
      runs: length, rounds: (map(select(.phase == "review")) | length),
      seconds: (map((.end | at) - (.start | at)) | add),
      out: (map(.tokens[] | .out) | add // 0),
      in: (map(.tokens[] | .in + .cache_write) | add // 0),
      cache_read: (map(.tokens[] | .cache_read) | add // 0)})
  | sort_by(.first) | .[]' "$log")

# Your PRs from one head branch, newest first, with the commits in any repo that cite each.
PRS='query($o: String!, $r: String!, $b: String!) { repository(owner: $o, name: $r) {
  pullRequests(headRefName: $b, first: 20, orderBy: {field: CREATED_AT, direction: DESC}) { nodes {
    number url state createdAt mergedAt closedAt author { login }
    reviews(states: CHANGES_REQUESTED) { totalCount }
    timelineItems(itemTypes: [REFERENCED_EVENT], first: 50) { nodes { ... on ReferencedEvent {
      commitRepository { nameWithOwner } commit { oid author { user { login } } } } } } } } } }'

own=0 rows=""
while IFS= read -r job; do
  [ -z "$job" ] && continue
  branch=$(jq -r '.branch // empty' <<<"$job")
  slug=$(jq -r '.remote // empty' <<<"$job" \
    | sed -n -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//')
  repo="" pr='{"state": "no GitHub remote"}'
  if [ -n "$slug" ]; then
    # The PR lives on the fork's parent, as gather.sh resolves it. One lookup per repo.
    parent="$parents/$(printf '%s' "$slug" | tr / _)"
    [ -f "$parent" ] || ghf "repo $slug" gh repo view "$slug" --json nameWithOwner,parent \
      -q 'if .parent then "\(.parent.owner.login)/\(.parent.name)" else .nameWithOwner end' > "$parent"
    repo=$(cat "$parent")
    if [ -z "$repo" ]; then
      repo="$slug" pr='{"state": "LOOKUP FAILED"}'
    elif [ "${repo%%/*}" = "$me" ]; then
      own=$((own + 1)); continue
    elif [ -z "$branch" ]; then
      pr='{"state": "none"}'
    elif prs=$(ghf "PRs from $branch on $repo" gh api graphql -f o="${repo%%/*}" -f r="${repo#*/}" -f b="$branch" -f query="$PRS"); then
      pr=$(jq -c --arg me "$me" --arg repo "$repo" '
        [.data.repository.pullRequests.nodes[] | select(.author.login == $me)][0]
        | if . == null then {state: "none"} else
            ([.timelineItems.nodes[] | select((.commitRepository.nameWithOwner | ascii_downcase) == ($repo | ascii_downcase)
              and .commit.author.user.login == $me) | .commit.oid][0]) as $landed
            | {number, url, state: (if .state == "CLOSED" and $landed then "LANDED" else .state end),
               landed: (if .state == "CLOSED" then $landed else null end),
               days: ((.mergedAt // .closedAt) as $end | if $end then (($end | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 8640 | round / 10 else null end),
               changes_requested: .reviews.totalCount}
          end' <<<"$prs")
    else
      pr='{"state": "LOOKUP FAILED"}'
    fi
  fi
  rows+=$(jq -c --arg repo "$repo" --argjson pr "$pr" \
    '{repo: (if $repo == "" then null else $repo end), branch, cwd, pr: $pr, runs, rounds, seconds, out, in, cache_read}' <<<"$job")$'\n'
done <<EOF
$jobs
EOF

K='def k: if . >= 1000000 then "\(. / 100000 | round / 10)M" elif . >= 1000 then "\(. / 1000 | round)k" else tostring end;'
if [ -n "$json" ]; then
  printf '%s' "$rows"
else
  printf '%s' "$rows" | jq -r -s "$K"'
    (["REPO", "BRANCH", "PR", "STATE", "DAYS", "CHANGES", "RUNS", "ROUNDS", "OUT", "IN", "CACHED"],
     (.[] | [.repo // "(\(.cwd | split("/") | .[-1]))", .branch // "-", (.pr.number // "-"), .pr.state, (.pr.days // "-"),
       (.pr.changes_requested // "-"), .runs, .rounds, (.out | k), (.in | k), (.cache_read | k)])) | @tsv' | column -t -s "$(printf '\t')"
  echo
  printf '%s' "$rows" | jq -r -s --argjson own "$own" "$K"'
    def n(s): [.[] | select(.pr.state == s)] | length;
    (n("MERGED") + n("LANDED")) as $merged
    | "\(length) jobs: \($merged) merged (\(n("LANDED")) landed by hand), \(n("CLOSED")) closed unmerged, \(n("OPEN")) open, \([.[] | select(.pr.number == null)] | length) with no PR.",
      (if $merged > 0 then "Output tokens per merged PR: \((map(.out) | add) / $merged | round | k) (every job'"'"'s output tokens over \($merged) merged)."
       else "No merged PR yet, so no tokens-per-merge figure." end),
      (if $own > 0 then "\($own) jobs on repos you own left out." else empty end)'
fi
if [ -s "$GH_FAILED" ]; then
  { echo "LOOKUP FAILED:"; sed 's/^/  /' "$GH_FAILED"; } >&2
  exit 3
fi
