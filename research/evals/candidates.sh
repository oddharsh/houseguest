#!/usr/bin/env bash
# List candidate PRs for the reviewer corpora, one JSON object per line.
#   candidates.sh <recall|noise> <owner/name> [limit]
# recall: closed-unmerged PRs from outside contributors where a maintainer
#   (OWNER/MEMBER/COLLABORATOR, non-bot) said something; the last thing they
#   said is the likely reason, the same heuristic gather.sh uses for rejected
#   attempts. Curate by hand: keep rows where that text is a real reason.
# noise: merged PRs from outside contributors with no CHANGES_REQUESTED review.
# Both look at PRs created after 2025-06-01, when agent PRs became common, and
# flag the ones whose branch, body, or title says an agent wrote them.
set -uo pipefail
set_="${1:?usage: candidates.sh <recall|noise> <owner/name> [limit]}"
repo="${2:?usage: candidates.sh <recall|noise> <owner/name> [limit]}"
limit="${3:-60}"

# Same predicates as gather.sh's JQLIB, plus an agent-authorship guess.
JQLIB='
def human: ((.author.is_bot // false) | not)
  and (((.author.login // "") | test("\\[bot\\]$|^app/|dependabot|renovate|github-actions|changeset|release-please"; "i")) | not);
def maint: (.authorAssociation // "") | IN("OWNER","MEMBER","COLLABORATOR");
def outside: (.authorAssociation // "") | IN("CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE");
def agent: [(.headRefName // ""), (.body // ""), (.title // "")] | join("\n")
  | (capture("(?i)(?<s>^(claude|codex|copilot|cursor|devin|jules)/|generated with \\[?claude|claude code|co-authored-by: (claude|copilot)|codex|devin|cursor agent|copilot)") // null) | if . then .s else null end;
def clip: gsub("\\s+"; " ") | .[:700];
'

if [ "$set_" = recall ]; then st="is:closed is:unmerged"; else st="is:merged"; fi
# GraphQL search, because `gh pr list` doesn't expose authorAssociation.
gh api graphql --paginate -f q="repo:$repo is:pr $st created:>2025-06-01 sort:updated-desc" -f query='
query($q:String!,$endCursor:String){search(query:$q,type:ISSUE,first:40,after:$endCursor){
  pageInfo{hasNextPage endCursor}
  nodes{... on PullRequest{number title url authorAssociation author{login} headRefName body createdAt closedAt
    additions deletions changedFiles
    comments(last:30){nodes{author{login} authorAssociation createdAt body}}
    reviews(last:30){nodes{author{login} authorAssociation state submittedAt body}}}}}}' 2>/dev/null \
| jq -s --argjson n "$limit" '[.[].data.search.nodes[] | select(.number != null)
    | .comments = .comments.nodes | .reviews = .reviews.nodes][:$n]' \
| jq -c --arg set "$set_" --arg repo "$repo" "$JQLIB"'
  .[] | select(human and outside)
  | ([.comments[] | select(maint and ((.author.login // "") | test("bot"; "i") | not))
      | {who: .author.login, at: .createdAt, kind: "comment", body: (.body // "")}]
     + [.reviews[] | select(maint and (.body // "") != "")
      | {who: .author.login, at: .submittedAt, kind: ("review " + .state), body: (.body // "")}]
     | sort_by(.at)) as $said
  | ([.reviews[] | select(.state == "CHANGES_REQUESTED")] | length) as $cr
  | {set: $set, repo: $repo, number, url, title, author: .author.login, agent: agent,
     size: "+\(.additions)/-\(.deletions) in \(.changedFiles)", closedAt,
     changes_requested: $cr,
     last_maintainer: (if ($said | length) > 0 then ($said[-1] | .body |= clip) else null end),
     maintainer_said: ($said | length)}
  | if $set == "recall" then select(.maintainer_said > 0) else select(.changes_requested == 0) end'
