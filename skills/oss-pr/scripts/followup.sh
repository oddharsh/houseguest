#!/usr/bin/env bash
# List your open PRs and issues on repos you don't own where someone else spoke last.
#
#   followup.sh [--days N] [--limit N] [--gerrit https://<host>]... [--email ADDR]
#
# A maintainer's unanswered question is the most common way a good contribution
# dies: the thread goes quiet, and a stale bot closes it. This finds every open
# item where the newest human comment or review isn't yours, newest wait last.
# It also lists your open PRs whose upstream CI is failing, or waiting for a maintainer to
# approve the run (first-time contributors' workflows need that), whoever spoke last.
# --days hides waits shorter than N days (default 0). --limit caps items checked (default 60).
# --gerrit adds your open changes on that Gerrit host (repeatable), found by --email
# (default: git config user.email), with their unresolved inline threads and red try bots.
# Without gh, it reads only the Gerrit hosts. Read-only.

set -uo pipefail
. "$(dirname "$0")/lib.sh"
days=0 limit=60 email="" hosts=()
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --gerrit) hosts+=("${2%/}"); shift 2 ;;
    --email) email="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "followup.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
me=$(gh api user --jq .login 2>/dev/null)
[ -n "$me" ] || [ ${#hosts[@]} -gt 0 ] || { echo "followup.sh: gh isn't authenticated" >&2; exit 1; }
[ -n "$email" ] || email=$(git config user.email)

items=""
if [ -n "$me" ]; then
  q="author:$me is:open archived:false -user:$me"
  items=$(gh api -X GET search/issues -f q="$q" -f per_page=100 -f sort=updated \
    --jq '.items[] | "\(.repository_url | sub("https://api.github.com/repos/"; ""))\t\(.number)\t\(if .pull_request then "pr" else "issue" end)\t\(.title)"' | head -"$limit")
fi
[ -z "$items" ] && [ ${#hosts[@]} -eq 0 ] && { echo "No open PRs or issues of yours on other people's repos."; exit 0; }

# Fetch every thread in parallel; each line comes back as the item plus its JSON.
fetch_item() {
  local repo n kind title json
  IFS=$'\t' read -r repo n kind title <<< "$1"
  if [ "$kind" = "pr" ]; then json=$(gh pr view "$n" -R "$repo" --json comments,reviews,reviewDecision,statusCheckRollup 2>/dev/null)
  else json=$(gh issue view "$n" -R "$repo" --json comments 2>/dev/null); fi || { printf '%s\tFAILED\n' "$1"; return; }
  printf '%s\t%s\n' "$1" "$(echo "$json" | jq -c .)"
}
fetched=$(echo "$items" | pmap 8 fetch_item)
unread=$(echo "$fetched" | awk -F'\t' '$5 == "FAILED" {print $1 "#" $2}')

now=$(date -u +%s)
rows="" ci_rows=""
while IFS=$'\t' read -r repo n kind title json; do
  [ "$json" = "FAILED" ] && continue
  if [ "$kind" = "pr" ]; then
    ci_row=$(echo "$json" | jq -r --arg repo "$repo" --arg n "$n" --arg title "$title" '
      [.statusCheckRollup[]? | {name: (.name // .context), r: ((.conclusion // .state // "") | ascii_upcase)}] as $c
      | ([$c[] | select(.r | test("^(FAILURE|ERROR|TIMED_OUT|STARTUP_FAILURE)$")) | .name] | unique) as $red
      | ([$c[] | select(.r == "ACTION_REQUIRED") | .name] | unique) as $wait
      | if ($red | length) > 0 then "\($repo)#\($n) \($title)\tfailing: \($red | join(", "))"
        elif ($wait | length) > 0 then "\($repo)#\($n) \($title)\twaiting for a maintainer to approve the run: \($wait | join(", "))"
        else empty end')
    [ -n "$ci_row" ] && ci_rows="$ci_rows
$ci_row"
  fi
  row=$(echo "$json" | jq -r --arg me "$me" --arg repo "$repo" --arg n "$n" --arg kind "$kind" --arg title "$title" --argjson now "$now" --argjson days "$days" '
    def bot: ((.author.login // "") | test("\\[bot\\]$|bot$|^app/|github-actions|changeset|codecov|vercel|netlify|devin|copilot|coderabbit|devprod|sonarcloud|codspeed|renovate|dependabot|cla-assistant|triage"; "i"))
      or ((.body // "") | test("^\\s*<!--"));
    (.reviewDecision // "") as $rd
    | ([.comments[]? | {who: .author.login, at: .createdAt, body: (.body // ""), bot: bot}]
     + [.reviews[]? | select((.body // "") != "" or .state == "CHANGES_REQUESTED") | {who: .author.login, at: .submittedAt, body: ("[" + .state + "] " + (.body // "")), bot: bot}])
    | map(select(.bot | not)) | sort_by(.at) as $c
    | ($c | map(select(.who == $me)) | last) as $mine
    | ($c | map(select(.who != $me)) | last) as $theirs
    | if $theirs == null then empty
      elif $mine != null and $mine.at > $theirs.at then empty
      else (($now - ($theirs.at | fromdateiso8601)) / 86400) as $age
        | select($age >= $days)
        | "\($age | floor)\t\($repo)#\($n) [\($kind)\(if $rd == "CHANGES_REQUESTED" then ", changes requested" else "" end)\(if ($theirs.body | test("\\?")) then ", asks a question" else "" end)] \($title)\t\($theirs.who), \($age | floor)d ago: \($theirs.body | gsub("\\s+"; " ") | .[:240])"
      end')
  [ -n "$row" ] && rows="$rows
$row"
done <<< "$fetched"

# Gerrit: one query per host for your open changes, with their messages and votes. Bots and CI
# post as service accounts or with an autogenerated: tag, and a bare vote isn't a reply (a -1 or
# -2 is). A rejected vote on any label but Code-Review is a try bot or presubmit failing.
gerrit_rows() {
  curl -fs -G "$1/changes/" --data-urlencode "q=owner:$email status:open" -d n="$limit" \
    -d o=MESSAGES -d o=LABELS -d o=DETAILED_ACCOUNTS | sed 1d | jq -r --arg host "$1" --argjson now "$now" --argjson days "$days" '
    def bot: ((.tag // "") | startswith("autogenerated:")) or ((.author.tags // []) | index("SERVICE_USER") != null)
      or ((.author.email // "") | test("gserviceaccount\\.com$|bot@"; "i"));
    def said: (.message | sub("^Patch Set [0-9]+:[^\\n]*"; "") | test("\\S")) or (.message | test("^Patch Set [0-9]+:[^\\n]*Code-Review-"));
    .[] | . as $ch | "\($host)/c/\(.project)/+/\(._number) \(.subject)" as $head
    | ([.labels // {} | to_entries[] | select(.key != "Code-Review" and .value.rejected != null) | .key]) as $red
    | (if ($red | length) > 0 then "C\t\($head)\tfailing: \($red | join(", "))" else empty end),
      ([.messages[]? | select(.author != null and (bot | not) and said)] as $m
       | ($m | map(select(.author._account_id == $ch.owner._account_id)) | last) as $mine
       | ($m | map(select(.author._account_id != $ch.owner._account_id)) | last) as $theirs
       | if $theirs == null then empty
         elif $mine != null and $mine.date > $theirs.date then empty
         else (($now - ($theirs.date | .[:19] | sub(" "; "T") + "Z" | fromdateiso8601)) / 86400) as $age
           | select($age >= $days)
           | "R\t\($age | floor)\t\($head) [change\(if $ch.labels["Code-Review"].rejected then ", Code-Review -2" else "" end)\(if ($ch.unresolved_comment_count // 0) > 0 then ", \($ch.unresolved_comment_count) unresolved" else "" end)\(if ($theirs.message | test("\\?")) then ", asks a question" else "" end)]\t\($theirs.author.display_name // $theirs.author.name), \($age | floor)d ago: \($theirs.message | gsub("\\s+"; " ") | .[:240])"
         end)'
}
for host in ${hosts[@]+"${hosts[@]}"}; do
  if out=$(gerrit_rows "$host"); then
    rows="$rows
$(echo "$out" | sed -n 's/^R	//p')"
    ci_rows="$ci_rows
$(echo "$out" | sed -n 's/^C	//p')"
  else unread="$unread
$host"; fi
done

unread=$(echo "$unread" | sed '/^$/d')
[ -n "$unread" ] && { echo "Couldn't read $(echo "$unread" | wc -l | tr -d ' ') item(s), so they're missing below; rerun, or open them by hand: $(echo "$unread" | tr '\n' ' ')"; echo; }

if [ -n "$(echo "$ci_rows" | sed '/^$/d')" ]; then
  echo "Upstream CI on your PRs (a red PR reads as abandoned; fix it, or say in the thread why it isn't yours):"
  echo "$ci_rows" | sed '/^$/d' | while IFS=$'\t' read -r head detail; do
    printf -- '- %s\n    %s\n' "$head" "$detail"
  done
  echo
fi
if [ -z "$(echo "$rows" | sed '/^$/d')" ]; then
  echo "Nothing waiting on your reply: on every open item, you spoke last (or nobody has replied)."
  exit 0
fi
echo "Waiting on your reply (longest wait last):"
echo "$rows" | sed '/^$/d' | sort -t$'\t' -k1,1n | while IFS=$'\t' read -r age head detail; do
  printf -- '- %s\n    %s\n' "$head" "$detail"
done
if echo "$rows" | grep -q -F '[change'; then
  echo
  echo "On a Gerrit change the questions sit in inline threads: read them with"
  echo "curl -s '<host>/changes/<number>/comments' | sed 1d | jq, or 'git cl comments' in a Chromium clone."
fi
