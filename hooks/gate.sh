#!/usr/bin/env bash
# PreToolUse gate for `gh pr create`, or a Gerrit upload, on repos you don't own.
#
# Blocks (exit 2) until the oss-pr ledger shows recon said GO, the blind intent
# check found no deliberate choice in the way, a style note exists, a proof and the
# final check both passed on the current HEAD, and the review loop stopped: every
# condition skills/oss-pr/scripts/next.sh checks. Stays silent everywhere else: other commands,
# repos that aren't forks, and your own repos. A `gh issue create` from a branch with a ledger
# gets only the title check.
# A user who explicitly wants to skip can prefix the command with HOUSEGUEST_SKIP=1.

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

# Gerrit's equivalents of `gh pr create`: Chromium's `git cl upload`, Go's `git codereview mail`,
# git-review (Wikimedia, Qt, OpenStack), Android's `repo upload`, and a plain push to refs/for/<branch>.
GERRIT_RE='git[[:space:]]+cl[[:space:]]+upload|git[[:space:]]+codereview[[:space:]]+mail|git[[:space:]]+review|repo[[:space:]]+upload|git[[:space:]]+push[[:space:]][^;&|]*refs/for/[^[:space:];&|]*'
gerrit=""
printf '%s' "$cmd" | grep -q -E "(^|[;&|[:space:]])($GERRIT_RE)([[:space:]]|\$)" && gerrit=1
# git-review also downloads, lists, and compares changes; only its upload publishes anything.
printf '%s' "$cmd" | grep -q -E 'git[[:space:]]+review[[:space:]](.*[[:space:]])?(-[dxXNmls]|--(download|cherrypick|cherrypick-indicate|cherrypick-only|compare|list|setup))([[:space:]]|$)' && gerrit=""

# A security report recon marked PRIVATE also blocks public issues and pushes.
private_only=""
if [ -n "$gerrit" ]; then :
elif printf '%s' "$cmd" | grep -q -E '(^|[;&|[:space:]])(gh[[:space:]]+issue[[:space:]]+create|git[[:space:]]+push)([[:space:]]|$)'; then
  private_only=1
else
  printf '%s' "$cmd" | grep -q -E '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0
fi
printf '%s' "$cmd" | grep -q 'HOUSEGUEST_SKIP=1' && exit 0

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

if [ -n "$private_only" ]; then
  ledger="$(git rev-parse --git-dir)/houseguest/$(git branch --show-current)"
  if ! grep -q -E '^DECISION:[[:space:]]*PRIVATE' "$ledger/recon.md" 2>/dev/null; then
    # An issue filed from a branch houseguest keeps a ledger for gets the same title check as a PR,
    # against the titles of issues this repo's maintainers closed as completed.
    printf '%s' "$cmd" | grep -q -E '(^|[;&|[:space:]])gh[[:space:]]+issue[[:space:]]+create([[:space:]]|$)' && [ -d "$ledger" ] || exit 0
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
