#!/usr/bin/env bash
# Test for skills/oss-pr/scripts/practice.sh.
#
#   bash tests/practice.sh
#
# Builds clones with ledgers shaped like real ones, runs practice.sh on them, and compares its
# rows and totals to literals. Prints the cases that differ and exits 1 if any do. Needs git;
# touches no network and nothing outside a temp directory.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export HOUSEGUEST_STATE="$W/state" HOUSEGUEST_ROOTS="" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
P="$ROOT/skills/oss-pr/scripts/practice.sh"

cases=0 failed=0
miss() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
same() {  # same <what> <got> <want>
  cases=$((cases + 1))
  [ "$2" = "$3" ] || miss "$1
  got:  $2
  want: $3"
}

clone() {  # clone <dir> <remote url>
  git init -q "$1" && git -C "$1" remote add origin "$2"
}
ledger() {  # ledger <clone> <branch> <date YYYYMMDD>: an empty ledger, its files dated that day
  L="$1/.git/houseguest/$2"; mkdir -p "$L"; STAMP="${3}1200"
}
note() {  # note <file> <text>: write a ledger note dated like its ledger
  printf '%s\n' "$2" > "$L/$1"; touch -t "$STAMP" "$L/$1"
}

roots="$W/src"
clone "$roots/a" https://github.com/up/a.git
ledger "$roots/a" fix/one 20261101
note recon.md "DECISION: GO
Reason: open bug, no PR"
note rounds.md "## Round 1 (maintainer-review on abc)

- R1.1 [Important] guard misses the empty case. Status: fixed in def.
- R1.2 [Important] claims a race. Status: refuted (finding check: the lock is held at a.rs:40).
- R1.3 [Nit] name. Status: left.

## Round 2 (maintainer-review on def)

STOP: clean (round 2)"
note decisions.md "D1: kept the guard; housecheck S3
D2: scoped the fix to AVIF only; because the user decided to keep the PR small
D3: reverses D1: dropped the guard, because the caller already checks"
note judgment.md "- caught: the fix guarded at the caller | read the 3 other callers
- no-help: 2 rounds guessing at the hang | sample(1) named the lock
- thrown: a cache in front of the parser | 0.4 ms of 31 ms"
note final.md "STATUS: PASS"
# A copy a phase kept inside the ledger is not a second job.
mkdir -p "$L/attempt-1"; note attempt-1/proof.md "STATUS: FAIL"

ledger "$roots/a" stopped 20261102
note recon.md "DECISION: STOP
Reason: open PR already fixes it"

# A Gerrit clone, two levels down, with a job still open.
clone "$roots/deep/chromium/src" https://chromium.googlesource.com/chromium/src.git
ledger "$roots/deep/chromium/src" crash-fix 20261103
note proof.md "STATUS: PASS"

out=$(bash "$P" --root "$roots"); rc=$?
rows=$(printf '%s\n' "$out" | sed -n '2,4p' | tr -s ' ')
same "one row per job, oldest first, nested copies left out" "$rows" \
"2026-11-01 up/a fix/one GO 2 2 1 1 1 1 1 1
2026-11-02 up/a stopped STOP 0 0 0 0 0 0 0 0
2026-11-03 chromium/src crash-fix - 0 0 0 0 0 0 0 0"
same "totals over the 2 finished jobs; the open one isn't counted" "$(printf '%s\n' "$out" | sed -n '/^Last/,$p')" \
"Last 2 finished jobs:
  Recon: 1 GO, 0 DOCS, 0 JOIN, 0 ASK, 1 STOP.
  Review: 2 rounds, 2 Important findings, 1 refuted by the finding check.
  Decisions: 1 name you, 1 reverse an earlier one.
  Judgment notes: 1 caught, 1 no-help, 1 thrown; 1 of 2 jobs have none."
same "no drift on 2 jobs, exit 0" "$rc" 0

# Five finished jobs with decisions that never name the user and no judgment notes: all 3 drifts.
for i in 1 2 3 4 5; do
  ledger "$roots/a" "auto-$i" "2026111$i"
  note recon.md "DECISION: GO"
  note decisions.md "D1: picked the smaller diff; housecheck S1"
  note final.md "STATUS: PASS"
done
out=$(bash "$P" --root "$roots" --last 5); rc=$?
same "every drift line on 5 unexamined jobs" "$(printf '%s\n' "$out" | grep '^DRIFT:' | cut -c1-60)" \
"DRIFT: 5 of the last 5 finished jobs have no judgment.md. Wr
DRIFT: no no-help note in the last 5 jobs. Either the agent 
DRIFT: 5 jobs have decisions.md, and no decision in them nam"
same "drift exits 1" "$rc" 1

bash "$P" --root "$W/empty" >/dev/null 2>&1; rc=$?
same "no ledger exits 2" "$rc" 2
bash "$P" --last 0 >/dev/null 2>&1; rc=$?
same "--last 0 is a usage error" "$rc" 2

echo "$cases cases, $failed failed"
[ "$failed" -eq 0 ]
