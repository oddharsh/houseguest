#!/usr/bin/env bash
# Which oss-pr phase runs next on this branch, read from the ledger, after Sudus's `wake`.
#
#   next.sh [LEDGER]         the first phase whose condition doesn't hold on HEAD, and why
#   next.sh --all [LEDGER]   every condition that doesn't hold, one per line (the PR gate's list)
#
# The phases are one ordered table, and each has a condition over the ledger. The first that
# fails is what runs next, so a new commit, a rewritten body, or an edited verdict sends the job
# back to the phase that has to rerun, with no judgment from the session. The PR gate reads
# the same table with --all, so the two can't drift apart.
#
# Exit 0 when every phase holds, 1 when a phase is next, 3 when recon stopped the job, and
# 4 when the user has to decide before anything runs.

set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
all=""; [ "${1:-}" = "--all" ] && { all=1; shift; }
ledger="${1:-$(git rev-parse --git-dir)/houseguest/$(git branch --show-current)}"
head=$(git rev-parse HEAD)

line() { grep -m1 -E "^$2" "$ledger/$1" 2>/dev/null | sed -E "s/^$2[[:space:]]*//"; }
sealed() { bash "$here/receipt.sh" check "$ledger/$1" >/dev/null 2>&1; }
on_head() {  # on_head <file> <what reruns it>: the verdict's SHA: is HEAD
  local sha; sha=$(line "$1" 'SHA:')
  [ "$sha" = "$head" ] && return 0
  why="$1 is for ${sha:-no sha}, but HEAD is $head; $2"; return 1
}

# Each check returns 0 when its phase holds, or sets why and returns 1. A check that ends the
# job sets stop; one that needs the user's call sets ask.
why="" stop="" ask=""
p_intent() {
  # JOIN skips the intent check, and a recon that stopped the job is what to report.
  case "$(line recon.md 'DECISION:')" in ""|GO*|DOCS*) ;; *) return 0 ;; esac
  [ -f "$ledger/intent.md" ] || { why="intent.md missing: run the intent check (oss-pr phase 0) in its own subagent, or write VERDICT: N/A (<reason>) when the change alters no existing behavior"; return 1; }
  case "$(line intent.md 'VERDICT:')" in
    ""|"<"*|*"|"*) why="intent.md has no filled-in VERDICT: line"; return 1 ;;
  esac
}
p_recon() {
  [ -f "$ledger/recon.md" ] || { why="recon.md missing: run oss-pr phase 1 (recon)"; return 1; }
  local d; d=$(line recon.md 'DECISION:')
  case "$d" in
    GO*) ;;
    DOCS*) grep -q -E '^VERDICT:[[:space:]]*INTENDED' "$ledger/intent.md" 2>/dev/null \
      || { why="recon decided DOCS, but intent.md doesn't say the behavior is INTENDED: a docs change needs the intent check's citation behind it"; return 1; } ;;
    JOIN*) [ -f "$ledger/pr-defaults.md" ] \
      || { why="recon decided JOIN but pr-defaults.md is missing: run prdefaults.sh on the PR you're adding to and follow references/existing-pr.md"; return 1; } ;;
    "") why="recon.md has no DECISION: line"; return 1 ;;
    *) stop=1; why="recon decided $d: $(line recon.md 'Reason:')"; return 1 ;;
  esac
  case "$(line recon.md '- AI policy:')" in
    ""|"<"*) why="recon.md has no AI policy verdict: run policy.sh (gather.sh runs it) and record what it found"; return 1 ;;
  esac
  local rep; rep=$(line recon.md '- Reproduces on:')
  case "$rep" in
    ""|"<"*|*"not yet checked"*) why="recon.md doesn't say where the bug reproduces: run channels.sh, reproduce on prod and each build it marks DIFFERS, and record the results (or \"n/a: not a bug fix\")"; return 1 ;;
    *BLOCKED:*) why="recon's reproduction is blocked by the setup ($(printf '%s' "$rep" | sed 's/.*BLOCKED:[[:space:]]*//' | cut -c1-160)): fix the environment and reproduce, since a broken setup says nothing about the bug"; return 1 ;;
    *"<yes/no>"*|*"<reproduces?"*) why="recon.md's Reproduces on line still has unfilled results: reproduce on each listed build and replace every <yes/no>"; return 1 ;;
  esac
  case "$d" in GO*)
    case "$(line intent.md 'VERDICT:')" in
      INTENDED*)
        case "$(line intent.md '- Factual error:')" in ""|"<"*|none*|None*)
          why="the intent check found this behavior intended ($(line intent.md 'Basis:' | cut -c1-200)), and names no factual error behind it: recon should ASK the maintainers first"; return 1 ;;
        esac ;;
      CONFLICTING*) why="the intent check found conflicting sources on whether this behavior is intended: recon should ASK the maintainers first"; return 1 ;;
    esac ;;
  esac
}
p_style() { [ -f "$ledger/style.md" ] || { why="style.md missing: run oss-pr phase 2 (style fingerprint)"; return 1; }; }
p_write() {
  [ -f "$ledger/house.md" ] || { why="house.md missing: run housecheck.sh to check the diff against the repo's house rules"; return 1; }
  local s; s=$(line house.md 'STATUS:')
  case "$s" in
    PASS*) sealed house.md || { why="house.md was edited after housecheck.sh sealed it: rerun housecheck.sh rather than editing its verdict"; return 1; } ;;
    *) why="house rules check is '${s:-missing}': fix the FAILs, run the missing tools, and fix or acknowledge each flag"; return 1 ;;
  esac
  # housecheck.sh reads commit subjects, so a reworded commit needs it again: this one binds to the SHA.
  on_head house.md "rerun housecheck.sh"
}
p_proof() {
  [ -f "$ledger/proof.md" ] || { why="proof.md missing: run oss-pr phase 4 (prove.sh), or write STATUS: N/A for docs-only changes"; return 1; }
  local s; s=$(line proof.md 'STATUS:')
  case "$s" in
    PASS*) sealed proof.md || { why="proof.md was edited after prove.sh sealed it: rerun prove.sh rather than editing its verdict"; return 1; } ;;
    N/A*) ;;
    *)
      # After Sudus's escalation rule: three different trees that failed the proof since it last
      # passed is a problem another rewrite won't fix. Rerunning one tree counts once.
      local tried; tried=$(awk -F'\t' '$2 == "PASS" {split("", seen); n = 0} $2 == "FAIL" && !($1 in seen) {seen[$1] = 1; n++} END {print n + 0}' "$ledger/proof-attempts.log" 2>/dev/null)
      tried=${tried:-0}
      if [ "$tried" -ge 3 ] && [ ! -s "$ledger/proof-ack.md" ]; then
        ask=1; why="the proof has failed on $tried different trees: show the user what failed each time and ask how to go on, then write their answer to proof-ack.md"; return 1
      fi
      why="proof status is '${s:-missing}'"; return 1 ;;
  esac
  # The proof is about the code, so a commit with the same tree (a reworded message, a squash) keeps it.
  local sha tree; sha=$(line proof.md 'SHA:')
  tree=$(git rev-parse -q --verify "$sha^{tree}" 2>/dev/null)
  [ -n "$tree" ] && [ "$tree" = "$(git rev-parse HEAD^{tree})" ] && return 0
  why="proof.md is for ${sha:-no sha}, whose tree isn't HEAD's ($head); rerun the proof on the current commit"; return 1
}
p_copy() {
  [ -s "$ledger/pr-title.txt" ] && [ -s "$ledger/pr-body.md" ] \
    || { why="pr-title.txt or pr-body.md missing: run oss-pr phase 5 (copy)"; return 1; }
}
p_review() {
  local s; s=$(grep -E '^STOP:' "$ledger/rounds.md" 2>/dev/null | tail -1 | sed -E 's/^STOP:[[:space:]]*//')
  case "$s" in
    clean*|stand-still*decided*|budget*decided*) ;;
    "") why="rounds.md has no STOP: line: run the maintainer review (oss-pr phase 6) until the loop stops, and record how"; return 1 ;;
    *) why="the review loop stopped at '$s' and the user hasn't decided the open findings"; return 1 ;;
  esac
}
p_final() {
  [ -f "$ledger/final.md" ] || { why="final.md missing: run the final check (oss-pr phase 7) on this commit, after review"; return 1; }
  local s; s=$(line final.md 'STATUS:')
  case "$s" in
    PASS*"checked by the user"*) ;;
    PASS*)
      sealed final.md || { why="final.md was edited after the final check sealed it: rerun the final check rather than editing final.md"; return 1; }
      local runs
      runs=$(bash "$here/receipt.sh" verify "$ledger/runs.log" 2>&1) \
        || { why="runs.log: $runs. The final check runs each repro through receipt.sh run; rerun it"; return 1; }
      echo "$runs" | awk '{print $1}' | grep -q -x "$head" \
        || { why="runs.log shows nothing run on HEAD ($head): the final check reproduces on the commit being pushed"; return 1; }
      case "$(line proof.md 'STATUS:')" in N/A*) ;; *)
        echo "$runs" | awk '{print $1}' | grep -v -x -e "$head" -e none | grep -q . \
          || { why="runs.log shows nothing run on the base: the final check shows each problem on the base before showing it's gone on HEAD"; return 1; } ;;
      esac
      # The final check records the body it read, so rewriting the body makes it stale. A
      # missing body is phase 5's to report.
      [ -f "$ledger/pr-body.md" ] || return 1
      local body; body=$(openssl dgst -sha256 < "$ledger/pr-body.md" | awk '{print $NF}')
      case "$(line final.md 'BODY:')" in
        "sha256=$body") ;;
        "") why="final.md doesn't say which pr-body.md it checked (no BODY: line): rerun the final check"; return 1 ;;
        *) why="pr-body.md changed after the final check read it: rerun the final check on the new body"; return 1 ;;
      esac ;;
    *) why="final check is '${s:-missing}': the PR doesn't yet show it solves every problem it poses (see $ledger/final.md)"; return 1 ;;
  esac
  on_head final.md "rerun the final check"
}
p_recheck() {
  [ -f "$ledger/recheck.md" ] || { why="recheck.md missing: run recheck.sh --save \"$ledger/recheck.md\" right before opening the PR"; return 1; }
  grep -q -E '^STATUS:[[:space:]]*CLEAR' "$ledger/recheck.md" \
    || { why="recheck.sh found changes upstream since recon (see $ledger/recheck.md): act on each, then rerun it with --since set to its Checked: time"; return 1; }
  sealed recheck.md || { why="recheck.md was edited after recheck.sh sealed it: rerun recheck.sh --save rather than editing its report"; return 1; }
}

# Phase id, label, and what to launch. The order is the graph: the first phase that fails runs next.
PHASES='intent|0 intent check|agents/intent-check.md, in its own subagent and a scratch clone
recon|1 recon|references/recon.md
style|2 style fingerprint|references/style.md
write|3 write the change|references/lean.md, then housecheck.sh
proof|4 proof|references/proof.md
copy|5 copy|references/pr-copy.md
review|6 maintainer review|agents/maintainer-review.md, then a finding check per Important finding
final|7 final check|agents/final-check.md, in its own subagent and a scratch clone
recheck|recheck|scripts/recheck.sh --save, right before the PR'

held="" after="" next="" failed=""
while IFS='|' read -r id label launch; do
  [ -n "$next" ] && [ -z "$all" ] && { after="${after:+$after, }$label"; continue; }
  why=""
  if "p_$id"; then held="${held:+$held, }$label"
  else
    failed=1
    [ -n "$all" ] && echo "$why"
    [ -z "$next" ] && { next="$label|$launch"; first_why="$why"; }
  fi
done <<EOF
$PHASES
EOF

if [ -n "$all" ]; then [ -z "$failed" ]; exit $?; fi
if [ -z "$next" ]; then
  echo "READY: every phase holds on $head. Show the user pr-title.txt, pr-body.md, and the exact command, and wait for a yes."
  exit 0
fi
if [ -n "$stop" ]; then
  echo "STOP: $first_why"
  echo "Report it to the user with links (\"When recon says stop\" in SKILL.md)."
  exit 3
fi
if [ -n "$ask" ]; then
  echo "ASK USER: $first_why"
  exit 4
fi
echo "NEXT: phase ${next%%|*} (${next#*|})"
echo "  why: $first_why"
echo "held: ${held:-nothing yet}"
[ -n "$after" ] && echo "after: $after"
exit 1
