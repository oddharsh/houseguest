#!/usr/bin/env bash
# What do your oss-pr ledgers say about your own judgment, across jobs?
#
#   practice.sh [--root DIR]... [--last N]
#
# Finds every ledger (.git/houseguest/<branch>) under each --root, under each directory in
# $HOUSEGUEST_ROOTS (colon-separated), and named in the phase log hooks/meter.sh keeps. Prints one
# row per job, oldest first, dated by the oldest file in its ledger:
#
#   RECON     recon.md's DECISION (GO, DOCS, JOIN, ASK, STOP), or - before recon ran
#   ROUNDS    review rounds in rounds.md; IMP its Important findings; REFUTED those the finding
#             check refuted
#   STEERED   decisions.md lines that name the user; REVERSED lines that reverse an earlier one
#   CAUGHT, NOHELP, THROWN   lines of each kind in judgment.md (skills/practice/references/craft.md)
#
# Then totals over the last N finished jobs (default 10). A job is finished once final.md exists,
# rounds.md has a STOP line, or recon decided ASK or STOP. Each pattern that needs your attention
# gets a DRIFT line. Read-only, no network; needs git, and jq only to read the phase log.
# Exits 0, 1 when it printed a DRIFT line, and 2 when it found no ledger.

set -uo pipefail
last=10 roots=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) roots="$roots:$2"; shift 2 ;;
    --last) last="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "practice.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$last" in ''|*[!0-9]*|0) echo "practice.sh: --last takes a positive number" >&2; exit 2 ;; esac
roots="$roots:${HOUSEGUEST_ROOTS:-}"
log="${HOUSEGUEST_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/houseguest}/phases.jsonl"

# Clones sit near the top of a root, so look for .git there and never walk a source tree: a
# depth-10 walk of a root holding a Chromium checkout ran past 2 minutes (2026-11-20). Inside each
# .git, a ledger is the directory holding a note that only sits at a ledger's top level. final.md
# is left out because old runs kept copies in subdirectories (final-v2/final.md).
ledgers=$( {
  IFS=:
  for r in $roots; do
    [ -d "$r" ] || continue
    find "$r" -maxdepth 5 -name node_modules -prune -o -name .git -type d -print -prune 2>/dev/null \
      | while IFS= read -r g; do
          for h in "$g/houseguest" "$g"/worktrees/*/houseguest; do
            [ -d "$h" ] && find "$h" -type f \( -name recon.md -o -name intent.md -o -name proof.md -o -name judgment.md \) 2>/dev/null
          done
        done | sed 's#/[^/]*$##'
  done
  [ -s "$log" ] && jq -r '.ledger // empty' "$log" 2>/dev/null
} | sort -u | awk '
  # A directory inside another ledger is a copy a phase kept (attempt-1/, logs/run1-fail/), since
  # git refuses a branch a/b/c beside a branch a/b.
  { keep[$0] = 1; path[NR] = $0 }
  END { for (i = 1; i <= NR; i++) { p = path[i]; inner = 0
          while (sub(/\/[^\/]*$/, "", p)) if (p in keep) { inner = 1; break }
          if (!inner) print path[i] } }')

# count <file> <extended regex>: matching lines, 0 when the file is missing.
count() { [ -f "$1" ] || { echo 0; return; }; grep -c -E "$2" "$1"; true; }

rows=""
while IFS= read -r l; do
  [ -d "$l" ] || continue
  gitdir=$(printf '%s' "$l" | sed -E 's#^(.*/\.git(/worktrees/[^/]+)?)/houseguest/.*#\1#')
  branch=$(printf '%s' "$l" | sed -E 's#^.*/\.git(/worktrees/[^/]+)?/houseguest/##')
  url=$(git --git-dir="${gitdir%/worktrees/*}" remote get-url upstream 2>/dev/null \
    || git --git-dir="${gitdir%/worktrees/*}" remote get-url origin 2>/dev/null)
  repo=$(printf '%s' "$url" | sed -n -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//')
  # Off GitHub (Gerrit hosts), the remote's path names the project: chromium/src.
  [ -n "$repo" ] || repo=$(printf '%s' "$url" | sed -E 's#^[a-z+]+://[^/]+/##; s#^[^@]+@[^:]+:##; s#\.git$##; s#^a/##')
  [ -n "$repo" ] || repo=$(basename "$(dirname "${gitdir%/worktrees/*}")")

  first=""
  for f in "$l"/*; do
    [ -f "$f" ] || continue
    t=$(date -r "$f" +%s)
    if [ -z "$first" ] || [ "$t" -lt "$first" ]; then first=$t; fi
  done
  [ -n "$first" ] || continue

  recon=$(sed -n -E 's/^DECISION:[[:space:]]*([A-Z]+).*/\1/p' "$l/recon.md" 2>/dev/null | head -n 1)
  rounds=$(count "$l/rounds.md" '^## Round')
  imp=$(count "$l/rounds.md" '\[Important\]')
  refuted=$(count "$l/rounds.md" '\[Important\].*[Rr]efuted')
  steered=$(count "$l/decisions.md" '^D[0-9]+:.*[Uu]ser')
  reversed=$(count "$l/decisions.md" '^D[0-9]+:.*[Rr]evers(es|ed|ing) D[0-9]')
  caught=$(count "$l/judgment.md" '^- caught:')
  nohelp=$(count "$l/judgment.md" '^- no-help:')
  thrown=$(count "$l/judgment.md" '^- thrown:')
  done=0
  { [ -f "$l/final.md" ] || grep -q '^STOP:' "$l/rounds.md" 2>/dev/null; } && done=1
  case "$recon" in ASK|STOP) done=1 ;; esac
  hasdec=0; [ -f "$l/decisions.md" ] && hasdec=1
  hasj=0; [ -f "$l/judgment.md" ] && hasj=1
  rows+="$first	$repo	$branch	${recon:--}	$rounds	$imp	$refuted	$steered	$reversed	$caught	$nohelp	$thrown	$done	$hasdec	$hasj"$'\n'
done <<EOF
$ledgers
EOF
[ -n "$rows" ] || { echo "practice.sh: no ledger found; pass --root with the directory your clones live in" >&2; exit 2; }
rows=$(printf '%s' "$rows" | sort -n)

{
  printf 'DATE\tREPO\tBRANCH\tRECON\tROUNDS\tIMP\tREFUTED\tSTEERED\tREVERSED\tCAUGHT\tNOHELP\tTHROWN\n'
  printf '%s\n' "$rows" | while IFS='	' read -r t rest; do
    printf '%s\t%s\n' "$(date -r "$t" +%Y-%m-%d 2>/dev/null || date -d "@$t" +%Y-%m-%d)" "$rest"
  done | cut -f 1-12
} | column -t -s "$(printf '\t')"
echo

printf '%s\n' "$rows" | awk -F '\t' -v last="$last" '
  $13 == 1 { n++; job[n] = $0 }
  END {
    if (n == 0) { print "No finished job yet, so no totals."; exit 0 }
    from = n > last ? n - last + 1 : 1; k = n - from + 1
    for (i = from; i <= n; i++) {
      split(job[i], f, "\t")
      recon[f[4]]++; r += f[5]; imp += f[6]; ref += f[7]; st += f[8]; rev += f[9]
      c += f[10]; h += f[11]; th += f[12]; dec += f[14]; if (!f[15]) noj++
    }
    printf "Last %d finished jobs:\n", k
    printf "  Recon: %d GO, %d DOCS, %d JOIN, %d ASK, %d STOP.\n", recon["GO"], recon["DOCS"], recon["JOIN"], recon["ASK"], recon["STOP"]
    printf "  Review: %d rounds, %d Important findings, %d refuted by the finding check.\n", r, imp, ref
    printf "  Decisions: %d name you, %d reverse an earlier one.\n", st, rev
    printf "  Judgment notes: %d caught, %d no-help, %d thrown; %d of %d jobs have none.\n", c, h, th, noj, k
    drift = 0
    if (k >= 4 && noj * 2 >= k) {
      printf "DRIFT: %d of the last %d finished jobs have no judgment.md. Write one line per catch, no-help, or throwaway before a job closes (craft.md).\n", noj, k; drift = 1 }
    if (k >= 5 && h == 0) {
      printf "DRIFT: no no-help note in the last %d jobs. Either the agent helped everywhere, or the places it did not went unrecorded.\n", k; drift = 1 }
    if (dec >= 3 && st == 0) {
      printf "DRIFT: %d jobs have decisions.md, and no decision in them names you. The agent made every call.\n", dec; drift = 1 }
    exit drift
  }'
