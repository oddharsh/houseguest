#!/usr/bin/env bash
# Which room a PR walks into: your own repo, a repo run on coding agents, or someone else's house.
#
#   room.sh [--repo owner/name] [--quick]
#
# Prints one line, `ROOM: own|agents|guest|unknown (<why>)`, then the evidence. The rooms file
# decides first: ${XDG_CONFIG_HOME:-~/.config}/houseguest/rooms, one entry per line, an owner or
# owner/name, then own, agents, or guest. A repo's line beats its owner's line. With no entry, the
# owner being your gh login makes it own. Otherwise the last 30 merged PRs by other people decide:
# agents when at least 5 were sampled and 75% or more carry a coding agent's mark (a
# Co-Authored-By: trailer, a claude/ codex/ cursor/ copilot/ devin/ branch, or the agent's own bot
# account). Anything less is guest.
#
# Without --repo it resolves the repo `gh pr create` would target from the current clone: the
# `gh repo set-default`, else the first of the upstream, github, and origin remotes, and that
# repo's parent when it's a fork. --quick stops before the PR sample, for the PR gate: it answers
# own, or unknown when only the sample could tell. Exit 0 unless the arguments are wrong.

set -uo pipefail
repo="" quick=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --quick) quick=1; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "room.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done

rooms="${XDG_CONFIG_HOME:-$HOME/.config}/houseguest/rooms"
login=$(gh config get -h github.com user 2>/dev/null)
[ -n "$login" ] || login=$(gh api user -q .login 2>/dev/null)

slug_of() {  # slug_of <remote url>: owner/name, from https, ssh, or scp-style URLs
  printf '%s' "$1" | sed -n -E 's#.*[:/]([^/:]+)/([^/]+)$#\1/\2#p' | sed -E 's/\.git$//'
}
listed() {  # listed <owner/name>: the room the rooms file gives it, repo line over owner line
  [ -f "$rooms" ] || return 1
  local r
  r=$(awk -v repo="$1" -v owner="${1%%/*}" '
    /^[[:space:]]*(#|$)/ { next }
    tolower($1) == tolower(repo) { exact = $2 }
    tolower($1) == tolower(owner) { byowner = $2 }
    END { if (exact != "") print exact; else if (byowner != "") print byowner }' "$rooms")
  case "$r" in own|agents|guest) echo "$r" ;; *) return 1 ;; esac
}
owned() {  # owned <owner/name>: the room's reason when the repo is yours, else nothing
  local r; r=$(listed "$1")
  if [ -n "$r" ]; then [ "$r" = own ] && echo "$rooms lists it as own"; return; fi
  [ -n "$login" ] && [ "$(printf '%s' "${1%%/*}" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')" ] \
    && echo "owner ${1%%/*} is your gh login"
}

via=""
if [ -z "$repo" ]; then
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "ROOM: unknown (not in a clone, and no --repo)"; exit 0; }
  repo=$(gh repo set-default --view 2>/dev/null | grep -m1 -E '^[^/[:space:]]+/[^/[:space:]]+$')
  if [ -n "$repo" ]; then via="gh repo set-default"
  else
    # gh's own remote order when nothing is set: upstream, github, origin, then the rest.
    for name in upstream github origin $(git remote); do
      url=$(git remote get-url "$name" 2>/dev/null) || continue
      repo=$(slug_of "$url"); [ -n "$repo" ] && { via="remote $name"; break; }
    done
    [ -n "$repo" ] || { echo "ROOM: unknown (no GitHub remote)"; exit 0; }
    # A PR from a fork goes to its parent. Only a repo you'd own needs the lookup.
    if [ -n "$(owned "$repo")" ]; then
      fork=$(gh repo view "$repo" --json isFork,parent -q 'if .isFork then .parent.owner.login + "/" + .parent.name else "no" end' 2>/dev/null)
      case "$fork" in
        "") echo "ROOM: unknown (couldn't tell whether $repo is a fork)"; exit 0 ;;
        no) ;;
        *) via="$via, a fork of $fork"; repo="$fork" ;;
      esac
    fi
  fi
fi
via="${via:+, from $via}"

why=$(owned "$repo")
if [ -n "$why" ]; then echo "ROOM: own ($repo: $why$via)"; exit 0; fi
r=$(listed "$repo")
if [ -n "$r" ]; then echo "ROOM: $r ($repo: $rooms lists it$via)"; exit 0; fi
[ -n "$quick" ] && { echo "ROOM: unknown ($repo: not yours; the PR sample decides between agents and guest$via)"; exit 0; }

# The sample: merged PRs by anyone but you, leaving out dependency and release bots.
q='query($o:String!,$n:String!){repository(owner:$o,name:$n){pullRequests(states:MERGED,first:30,orderBy:{field:CREATED_AT,direction:DESC}){nodes{number headRefName author{__typename login} commits(first:20){nodes{commit{message}}}}}}}'
json=$(gh api graphql -f query="$q" -f o="${repo%%/*}" -f n="${repo#*/}" 2>/dev/null) \
  || { echo "ROOM: guest ($repo: LOOKUP FAILED on merged PRs, so the cautious room$via)"; exit 0; }
printf '%s' "$json" | jq -r --arg me "$login" '
  def agent_bot: test("^(copilot-swe-agent|devin-ai-integration|cursor|claude|codex|openai-codex|google-labs-jules|gemini-code-assist)(\\[bot\\])?$"; "i");
  def mark:
    if (.author.login // "" | agent_bot) then "bot \(.author.login)"
    elif (.headRefName | test("^(claude|codex|cursor|copilot|devin|jules)[/-]"; "i")) then "branch \(.headRefName | split("/")[0])"
    else ([.commits.nodes[].commit.message | capture("(?i)co-authored-by:[[:space:]]*(?<a>claude|codex|cursor|copilot|devin|gemini|jules|aider)") | .a | ascii_downcase] | first // empty | "trailer \(.)")
    end;
  [.data.repository.pullRequests.nodes[]
    | select((.author.login // "") != $me)
    | select((.author.__typename != "Bot") or (.author.login // "" | agent_bot))
    | {n: .number, m: (mark // "")}] as $prs
  | ($prs | length) as $total | ([$prs[] | select(.m != "")] | length) as $marked
  | (if $total >= 5 and $marked * 4 >= $total * 3 then "agents" else "guest" end) as $room
  | "ROOM: \($room) (\($marked) of \($total) merged PRs by other people carry a coding agent'"'"'s mark\(if $total < 5 then "; fewer than 5 sampled" else "" end))",
    ($prs[] | "- #\(.n): \(if .m == "" then "no mark" else .m end)")'
[ -n "$via" ] && echo "- repo: $repo${via#,}"
exit 0
