#!/usr/bin/env bash
# Which bugs did this repo fix lately, so a reader can ask what design would have prevented them?
#
#   retro.sh [--repo DIR] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--max N]
#
# Prints every non-merge commit reachable from HEAD and committed in the window (default: the last
# 7 days through today), oldest first, with its date, subject, files, and body. FIX marks a commit
# whose subject or body uses a bug word (fix, bug, regress, revert, crash, hang, leak, race, wrong,
# stale, broke, blocked, false pass, silently). It says where to read first; the reader still
# judges every commit, since a fix titled "Keep X working" carries no bug word in its subject.
# Ends with a COMMITS: line. skills/practice/SKILL.md, "Retro", says what to do with the output.
# Read-only, no network; needs git.
# Exits 0, even for a window with no commits, and 2 on a bad argument, a directory with no
# commits, or a window holding more than --max commits (default 300), which is more than one
# reader can cluster in a pass.

set -uo pipefail
repo=. since="" until="" max=300
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --since) since="$2"; shift 2 ;;
    --until) until="$2"; shift 2 ;;
    --max) max="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "retro.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$max" in ''|*[!0-9]*|0) echo "retro.sh: --max takes a positive number" >&2; exit 2 ;; esac
[ -n "$since" ] || since=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
[ -n "$until" ] || until=$(date +%Y-%m-%d)
for d in "$since" "$until"; do
  case "$d" in
    [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]) ;;
    *) echo "retro.sh: dates take the form YYYY-MM-DD, got '$d'" >&2; exit 2 ;;
  esac
done
git -C "$repo" rev-parse -q --verify HEAD >/dev/null 2>&1 \
  || { echo "retro.sh: $repo isn't a git repo with commits" >&2; exit 2; }

# git reads a bare date as that day at the current time of day, so pin both ends to whole days.
shas=$(git -C "$repo" log --no-merges --reverse --format=%H \
  --since="$since 00:00:00" --until="$until 23:59:59") \
  || { echo "retro.sh: git log failed in $repo" >&2; exit 2; }
n=0; [ -n "$shas" ] && n=$(wc -l <<<"$shas" | tr -d ' ')
if [ "$n" -gt "$max" ]; then
  echo "retro.sh: $n commits from $since to $until, past --max $max; narrow the window" >&2
  exit 2
fi

bug='(^|[^[:alnum:]_])(fix(e[sd]|es)?|bugs?|regress(ion|ions|ed)?|revert(s|ed)?|crash(es|ed)?|hangs?|leaks?|races?|wrong|stale|broken?|breaks?|blocked|false (pass|passes|positives?|negatives?)|silently)($|[^[:alnum:]_])'
fixes=0
for sha in $shas; do
  head=$(git -C "$repo" show -s --date=short --format='%h %cd' "$sha") || exit 2
  subject=$(git -C "$repo" show -s --format=%s "$sha") || exit 2
  body=$(git -C "$repo" show -s --format=%b "$sha") || exit 2
  files=$(git -C "$repo" show --name-only --format= "$sha") || exit 2
  # A here-string, never a pipe into grep -q: under pipefail, grep quitting on its first match
  # kills the writer with SIGPIPE and the pipeline reports a miss (commit 1c5f72f).
  mark=-
  if grep -qiE "$bug" <<<"$subject
$body"; then mark=FIX; fixes=$((fixes + 1)); fi
  printf '== %s %s %s\n' "$head" "$mark" "$subject"
  printf 'files: %s\n' "$(tr '\n' ' ' <<<"$files" | sed 's/ *$//')"
  [ -n "$body" ] && sed 's/^/    /' <<<"$body"
  echo
done
echo "COMMITS: $n FIX: $fixes FROM: $since TO: $until"
