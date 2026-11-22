#!/usr/bin/env bash
# Test for skills/oss-pr/scripts/retro.sh.
#
#   bash tests/retro.sh
#
# Builds a repo with commits on fixed dates, runs retro.sh on it, and compares its output to
# literals. Prints the cases that differ and exits 1 if any do. Needs git; touches no network and
# nothing outside a temp directory.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
R="$ROOT/skills/oss-pr/scripts/retro.sh"

cases=0 failed=0
miss() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
same() {  # same <what> <got> <want>
  cases=$((cases + 1))
  [ "$2" = "$3" ] || miss "$1
  got:  $2
  want: $3"
}

repo="$W/repo"
git init -q -b main "$repo"
commit() {  # commit <date YYYY-MM-DD> <file> <message>
  printf '%s\n' "$3" >> "$repo/$2"
  git -C "$repo" add "$2"
  GIT_AUTHOR_DATE="$1T12:00:00Z" GIT_COMMITTER_DATE="$1T12:00:00Z" \
    git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m "$3"
}
commit 2026-11-01 a.sh "Fix the parser before the window"
commit 2026-11-10 a.sh "Fix the gate on quoted commands

A quoted command slipped past."
commit 2026-11-11 b.md "Add a prefix option"
commit 2026-11-12 b.md "Keep listings ungated

The exemption blocked a listing."
git -C "$repo" checkout -q -b side
commit 2026-11-13 c.sh "Side work"
git -C "$repo" checkout -q main
GIT_COMMITTER_DATE="2026-11-14T12:00:00Z" GIT_AUTHOR_DATE="2026-11-14T12:00:00Z" \
  git -C "$repo" -c user.name=t -c user.email=t@t merge -q --no-ff -m "Merge side, fix nothing" side

got=$(bash "$R" --repo "$repo" --since 2026-11-10 --until 2026-11-14 | sed -E 's/^== [0-9a-f]+ /== SHA /')
same "window, marks, merge left out, branch commit kept" "$got" "== SHA 2026-11-10 FIX Fix the gate on quoted commands
files: a.sh
    A quoted command slipped past.

== SHA 2026-11-11 - Add a prefix option
files: b.md

== SHA 2026-11-12 FIX Keep listings ungated
files: b.md
    The exemption blocked a listing.

== SHA 2026-11-13 - Side work
files: c.sh

COMMITS: 4 FIX: 2 FROM: 2026-11-10 TO: 2026-11-14"

# A bare date reads as that day at the current time; a commit at noon on the last day still counts.
got=$(bash "$R" --repo "$repo" --since 2026-11-12 --until 2026-11-12 | tail -1)
same "one-day window includes that day" "$got" "COMMITS: 1 FIX: 1 FROM: 2026-11-12 TO: 2026-11-12"

got=$(bash "$R" --repo "$repo" --since 2026-11-20 --until 2026-11-21; echo "exit=$?")
same "empty window is a result" "$got" "COMMITS: 0 FIX: 0 FROM: 2026-11-20 TO: 2026-11-21
exit=0"

got=$(bash "$R" --repo "$repo" --since 2026-11-10 --until 2026-11-14 --max 4 | tail -1)
same "window at --max" "$got" "COMMITS: 4 FIX: 2 FROM: 2026-11-10 TO: 2026-11-14"

got=$(bash "$R" --repo "$repo" --since 2026-11-10 --until 2026-11-14 --max 3 2>&1; echo "exit=$?")
same "window past --max" "$got" "retro.sh: 4 commits from 2026-11-10 to 2026-11-14, past --max 3; narrow the window
exit=2"

got=$(bash "$R" --repo "$repo" --since 11/10/2026 2>&1; echo "exit=$?")
same "bad date" "$got" "retro.sh: dates take the form YYYY-MM-DD, got '11/10/2026'
exit=2"

mkdir "$W/plain"
got=$(bash "$R" --repo "$W/plain" --since 2026-11-10 2>&1; echo "exit=$?")
same "not a repo" "$got" "retro.sh: $W/plain isn't a git repo with commits
exit=2"

printf '%d cases, %d failed\n' "$cases" "$failed"
[ "$failed" -eq 0 ]
