#!/usr/bin/env bash
# Tamper-evident receipts for the ledger, after loki-mode's signed run receipts.
#
#   receipt.sh seal FILE           write FILE.seal: FILE's hash, keyed with your receipt key
#   receipt.sh check FILE          exit 0 when FILE.seal matches FILE as it stands now
#   receipt.sh run LOG -- CMD...   run CMD, show its output, exit with its code, and append an
#                                  entry to LOG: the commit it ran on, its exit code, a hash of
#                                  its output, and the command, chained to the entry before
#   receipt.sh verify LOG          exit 0 when LOG's chain is intact; prints
#                                  "<commit> <exit> <command>" for each entry
#
# prove.sh, housecheck.sh, and recheck.sh seal the verdicts they write, and the final check
# runs every repro through `run`, then seals final.md. The PR gate checks the seals and the
# log, so a verdict edited by hand, or a final check that never ran anything on base and
# HEAD, can't open a PR.
#
# The key is ~/.config/houseguest/receipt.key (mode 600), made on first use;
# HOUSEGUEST_RECEIPT_KEY points elsewhere. Anything that can run your shell can read it, so
# this is a tripwire, not a security boundary: forging a receipt takes a deliberate step that
# shows in the transcript, where editing a STATUS line takes none.

set -uo pipefail

keyfile="${HOUSEGUEST_RECEIPT_KEY:-${XDG_CONFIG_HOME:-$HOME/.config}/houseguest/receipt.key}"
key() {
  if [ ! -s "$keyfile" ]; then
    ( umask 077; mkdir -p "$(dirname "$keyfile")"; openssl rand -hex 32 > "$keyfile" ) || { echo "receipt.sh: can't create $keyfile" >&2; exit 2; }
  fi
  cat "$keyfile"
}
sha() { openssl dgst -sha256 | awk '{print $NF}'; }
mac() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$(key)" | awk '{print $NF}'; }

cmd="${1:-}"; shift || true
case "$cmd" in
  seal)
    f="${1:?usage: receipt.sh seal FILE}"
    [ -f "$f" ] || { echo "receipt.sh: no such file $f" >&2; exit 2; }
    h=$(sha < "$f")
    echo "houseguest-seal v1 sha256=$h mac=$(mac "seal v1 $h")" > "$f.seal"
    ;;
  check)
    f="${1:?usage: receipt.sh check FILE}"
    [ -f "$f.seal" ] || { echo "no seal: $f.seal is missing"; exit 1; }
    h=$(sha < "$f")
    read -r _ _ hs ms < "$f.seal"
    [ "sha256=$h" = "$hs" ] || { echo "edited after sealing: $(basename "$f") no longer matches its seal"; exit 1; }
    [ "mac=$(mac "seal v1 $h")" = "$ms" ] || { echo "bad seal: $(basename "$f").seal wasn't made with this machine's receipt key"; exit 1; }
    ;;
  run)
    log="${1:?usage: receipt.sh run LOG -- CMD...}"; shift
    [ "${1:-}" = "--" ] && shift
    [ $# -gt 0 ] || { echo "usage: receipt.sh run LOG -- CMD..." >&2; exit 2; }
    tree=$(git rev-parse HEAD 2>/dev/null || echo none)
    out=$(mktemp)
    "$@" 2>&1 | tee "$out"
    rc=${PIPESTATUS[0]}
    prev=$(tail -n 1 "$log" 2>/dev/null | awk -F'\t' '{print $NF}')
    entry=$(printf 'v1\t%s\t%s\t%s\t%s\t%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tree" "$rc" "$(sha < "$out")" "$(printf '%q ' "$@" | sed 's/ $//')")
    printf '%s\t%s\n' "$entry" "$(mac "${prev:-start}
$entry")" >> "$log"
    rm -f "$out"
    exit "$rc"
    ;;
  verify)
    log="${1:?usage: receipt.sh verify LOG}"
    [ -s "$log" ] || { echo "no log: $log is missing or empty"; exit 1; }
    prev="start" i=0 tab=$'\t'
    while IFS= read -r line; do
      i=$((i + 1))
      entry="${line%"$tab"*}" m="${line##*"$tab"}"
      [ "$(mac "$prev
$entry")" = "$m" ] || { echo "broken at entry $i: the log was edited, reordered, or written without the receipt key"; exit 1; }
      printf '%s\n' "$entry" | awk -F'\t' '{print $3, $4, $6}'
      prev="$m"
    done < "$log"
    ;;
  *) sed -n '2,20p' "$0"; [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ]; exit $? ;;
esac
