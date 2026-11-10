#!/usr/bin/env bash
# PreToolUse gate for `gh pr create`, or a Gerrit upload, on repos you don't own.
#
# Blocks (exit 2) until the oss-pr ledger shows recon said GO, the blind intent
# check found no deliberate choice in the way, a style note exists, a proof and the
# final check both passed on the current HEAD, and the review loop stopped: every
# condition skills/oss-pr/scripts/next.sh checks. Stays silent everywhere else: other commands,
# repos that aren't forks, and your own repos. A `gh issue create` from a branch with a ledger
# gets only the title check. A `gh pr merge` of a PR whose branch has a ledger runs
# skills/oss-pr/scripts/merge.sh, and `gh pr merge --auto` is blocked outright.
# A user who explicitly wants to skip can prefix the command with HOUSEGUEST_SKIP=1.

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

# A command word also starts inside a subshell or a quoted script: $(gh ...), (gh ...), bash -c "gh ...".
B=$'(^|[;&|(`"\'[:space:]])' E=$'([;&|)`"\'[:space:]]|$)'

# Gerrit's equivalents of `gh pr create`: Chromium's `git cl upload`, Go's `git codereview mail`,
# git-review (Wikimedia, Qt, OpenStack), Android's `repo upload`, and a plain push to refs/for/<branch>.
GERRIT_RE='git[[:space:]]+cl[[:space:]]+upload|git[[:space:]]+codereview[[:space:]]+mail|git[[:space:]]+review|repo[[:space:]]+upload|git[[:space:]]+push[[:space:]][^;&|]*refs/for/[^[:space:];&|]*'
gerrit=""
printf '%s' "$cmd" | grep -q -E "$B($GERRIT_RE)$E" && gerrit=1
# git-review also downloads, lists, and compares changes; only its upload publishes anything.
printf '%s' "$cmd" | grep -q -E "git[[:space:]]+review[[:space:]](.*[[:space:]])?(-[dxXNmls]|--(download|cherrypick|cherrypick-indicate|cherrypick-only|compare|list|setup))$E" && gerrit=""

api_opens_pr() {  # a `gh api` POST to repos/<owner>/<repo>/pulls: gh POSTs for any field or --input unless -X GET
  case "$cmd" in *gh*api*pulls*) ;; *) return 1 ;; esac
  printf '%s' "$cmd" | tr '\n' ' ' | grep -o -E "${B}gh[[:space:]]+api[[:space:]][^;&|]*" \
    | grep -E "repos/[^/[:space:]]+/[^/[:space:]]+/pulls$E" \
    | grep -v -i -E -- '(-X|--method)[[:space:]=]*GET' \
    | grep -q -i -E -- '(-X|--method)[[:space:]=]*POST|[[:space:]](-f|--(raw-)?field|--input)'
}

# A security report recon marked PRIVATE also blocks public issues and pushes. A command that
# opens a PR always reaches the PR's checks, whatever is chained around it: `git push && gh pr create`.
private_only="" merge="" pr=""
{ printf '%s' "$cmd" | grep -q -E "${B}gh[[:space:]]+pr[[:space:]]+create$E" || api_opens_pr; } && pr=1
if [ -n "$gerrit" ]; then :
elif [ -z "$pr" ] && printf '%s' "$cmd" | grep -q -E "${B}gh[[:space:]]+pr[[:space:]]+merge$E"; then
  merge=1
elif printf '%s' "$cmd" | grep -q -E "$B(gh[[:space:]]+issue[[:space:]]+create|git[[:space:]]+push)$E"; then
  private_only=1
elif [ -z "$pr" ]; then
  exit 0
fi
# Only a leading environment assignment skips: the same text in a PR body or a commit message doesn't.
skip_re='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*HOUSEGUEST_SKIP=1[[:space:]]'
[[ $cmd =~ $skip_re ]] && exit 0

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

cmd_title() {  # cmd_title <ledger title file>: the file's first line when the command reads it, else the command's --title
  # The file comes first: in `--title "$(cat .../pr-title.txt)"` the quoted text is the `$(cat ...)` itself.
  if [ -f "$1" ] && printf '%s' "$cmd" | grep -q "$(basename "$1")"; then head -1 "$1"; return; fi
  printf '%s' "$cmd" | sed -n -E "s/.*(--title|-t)[ =]+\"([^\"]*)\".*/\2/p; s/.*(--title|-t)[ =]+'([^']*)'.*/\2/p" | head -1
}
title_flags() {  # title_flags <stats file> <title>: what title.sh flags, joined by ";", or nothing when it passes
  local out
  out=$(bash "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/skills/oss-pr/scripts/title.sh" --stats "$1" "$2" 2>/dev/null) && return 0
  out=$(echo "$out" | sed -n '/^FLAG/,$p' | grep '^  - ' | sed 's/^  - //' | tr '\n' ';' | sed 's/;$//' | cut -c1-240)
  [ -n "$out" ] || out="title.sh couldn't read $1"
  printf '%s' "$out"
}

if [ -n "$merge" ]; then
  # Only PRs houseguest made: the PR's head branch has a ledger in this clone.
  args=$(printf '%s' "$cmd" | tr '\n' ' ' | sed -E 's/.*gh[[:space:]]+pr[[:space:]]+merge//; s/[;&|)`].*//')
  # The PR is the first word that's neither a flag nor a flag's value, wherever it sits.
  sel=$(printf '%s' "$args" | sed -E -e ':a' -e "s/^[[:space:]]+(-[RAbFt]|--(repo|author-email|body|body-file|subject|match-head-commit))([[:space:]]+|=)(\"[^\"]*\"|'[^']*'|[^[:space:]]+)//" -e ta \
    -e 's/^[[:space:]]+-[^[:space:]]*//' -e ta -e 's/^[[:space:]]+//; s/[[:space:]].*//' | tr -d "\"'")
  repo=$(printf '%s' "$args" | sed -n -E 's/.*(-R|--repo)[ =]+([^[:space:]]+).*/\2/p' | tr -d "\"'")
  head=$(gh pr view ${sel:+"$sel"} ${repo:+-R "$repo"} --json headRefName -q .headRefName 2>/dev/null)
  ledger="$(git rev-parse --git-dir)/houseguest/$head"
  [ -n "$head" ] && [ -d "$ledger" ] || exit 0
  if printf '%s' "$args" | grep -q -E "(^|[[:space:]])--auto(=|$E)"; then
    why="--auto merges whenever checks go green, so a comment that lands after this runs gets no answer before the merge. Run merge.sh, answer what it lists, and merge by hand"
  else
    method=""
    printf '%s' "$args" | grep -q -E "(^|[[:space:]])(-s|--squash)$E" && method=--squash
    printf '%s' "$args" | grep -q -E "(^|[[:space:]])(-m|--merge)$E" && method=--merge
    printf '%s' "$args" | grep -q -E "(^|[[:space:]])(-r|--rebase)$E" && method=--rebase
    out=$(bash "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/skills/oss-pr/scripts/merge.sh" ${sel:+"$sel"} ${repo:+-R "$repo"} $method --ledger "$ledger" 2>&1) && exit 0
    why="merge.sh says it isn't ready:
$out"
  fi
  cat >&2 <<EOF
houseguest blocked this merge. $why

Answer each open comment ("When you merge it yourself" in the oss-pr skill), then rerun merge.sh.
If the user explicitly says to merge anyway, rerun the same command prefixed with HOUSEGUEST_SKIP=1.
EOF
  exit 2
fi

# A push chained in front of opening a PR goes on to the PR's checks, unless recon said PRIVATE.
[ -n "$pr" ] && ! grep -q -E '^DECISION:[[:space:]]*PRIVATE' "$(git rev-parse --git-dir)/houseguest/$(git branch --show-current)/recon.md" 2>/dev/null && private_only=""
if [ -n "$private_only" ]; then
  ledger="$(git rev-parse --git-dir)/houseguest/$(git branch --show-current)"
  if ! grep -q -E '^DECISION:[[:space:]]*PRIVATE' "$ledger/recon.md" 2>/dev/null; then
    # An issue filed from a branch houseguest keeps a ledger for gets the same title check as a PR,
    # against the titles of issues this repo's maintainers closed as completed.
    printf '%s' "$cmd" | grep -q -E "${B}gh[[:space:]]+issue[[:space:]]+create$E" && [ -d "$ledger" ] || exit 0
    ttl=$(cmd_title "$ledger/issue-title.txt") why=""
    [ -n "$ttl" ] || exit 0
    if [ ! -f "$ledger/issue-titles.json" ]; then
      why="the title isn't checked: run title.sh --issues --save \"$ledger/issue-titles.json\" first (see pr-copy.md)"
    elif [ ! -s "$ledger/title-ack.md" ]; then
      tf=$(title_flags "$ledger/issue-titles.json" "$ttl")
      [ -n "$tf" ] && why="the title doesn't match the titles of issues this repo's maintainers acted on: $tf. Rewrite it, or explain in title-ack.md why it's right"
    fi
    [ -z "$why" ] && exit 0
    cat >&2 <<EOF
houseguest blocked this issue: $why.
If the user explicitly says to skip the check, rerun the same command prefixed with HOUSEGUEST_SKIP=1.
EOF
    exit 2
  fi
  # The advisory's temporary private fork (<repo>-ghsa-xxxx-xxxx-xxxx) is where the fix belongs.
  for w in $(printf '%s' "$cmd" | sed -E 's/.*git[[:space:]]+push//'); do
    case "$w" in -*) continue ;; esac
    url=$(git remote get-url "$w" 2>/dev/null || printf '%s' "$w")
    printf '%s' "$url" | grep -q -E -- '-ghsa(-[a-z0-9]{4}){3}' && exit 0
  done
  cat >&2 <<EOF
houseguest blocked this: recon.md says this is a security vulnerability (DECISION: PRIVATE).
Nothing about it goes public until the maintainers publish an advisory: report it through the
channel in SECURITY.md, and push a fix only to the advisory's private fork (its name ends in
-ghsa-...). If the user explicitly says to go ahead, rerun the command prefixed with HOUSEGUEST_SKIP=1.
EOF
  exit 2
fi

branch=$(git branch --show-current)
ledger="$(git rev-parse --git-dir)/houseguest/$branch"

# Only gate contributions upstream: a fork, or a clone with an `upstream` remote. Gerrit has
# no forks, so there it's a project that checks in its review setup, any `repo upload` (Android's
# projects check in none), or a branch oss-pr already keeps a ledger for.
if [ -n "$gerrit" ]; then
  top=$(git rev-parse --show-toplevel)
  [ -e "$top/codereview.settings" ] || [ -e "$top/codereview.cfg" ] || [ -e "$top/.gitreview" ] || [ -d "$ledger" ] \
    || printf '%s' "$cmd" | grep -q -E 'repo[[:space:]]+upload' || exit 0
elif ! git remote get-url upstream >/dev/null 2>&1; then
  [ "$(gh repo view --json isFork -q .isFork 2>/dev/null)" = "true" ] || exit 0
fi
problems=""
add() { problems="${problems}  - $1
"; }
# Every phase's condition lives in next.sh, which the session also runs between phases.
while IFS= read -r why; do
  [ -n "$why" ] && add "$why"
done < <(bash "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/skills/oss-pr/scripts/next.sh" --all "$ledger")

# The title, when one is passed: recheck it against the repo's title conventions. On Gerrit
# the title is the commit's subject (`git cl upload -t` titles the patchset, not the change),
# and it's checked only when title.sh found merged titles to learn from.
if [ -n "$gerrit" ]; then
  ttl=""; [ -f "$ledger/titles.json" ] && ttl=$(git log -1 --format=%s)
else
  ttl=$(cmd_title "$ledger/pr-title.txt")
fi
if [ -n "$ttl" ] && [ -f "$ledger/titles.json" ] && [ ! -s "$ledger/title-ack.md" ]; then
  tf=$(title_flags "$ledger/titles.json" "$ttl")
  [ -n "$tf" ] && add "title doesn't match the repo's title conventions: $tf. Rewrite it, or explain in title-ack.md why it's right"
elif [ -n "$ttl" ] && [ ! -f "$ledger/titles.json" ]; then
  add "title not checked: run title.sh --save \"$ledger/titles.json\" first (see pr-copy.md)"
fi

[ -z "$problems" ] && exit 0

what="PR"; [ -n "$gerrit" ] && what="Gerrit change"
cat >&2 <<EOF
houseguest blocked this $what. The oss-pr ledger at $ledger isn't complete:
$problems
Finish the missing phases with the oss-pr skill. If the user explicitly says to skip
the checks for this $what, rerun the same command prefixed with HOUSEGUEST_SKIP=1.
EOF
exit 2
