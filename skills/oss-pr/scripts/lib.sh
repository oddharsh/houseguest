# Helpers sourced by the oss-pr scripts. Works in bash 3.2 (macOS's /bin/bash).

# pmap N CMD [ARGS...]: run `CMD ARGS... <line>` for each stdin line, N at a time,
# and print the outputs in input order. The body is a subshell so its `wait` only
# waits for its own jobs, never the caller's other background work.
pmap() (
  n="$1"; shift
  d=$(mktemp -d); i=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    i=$((i + 1))
    ( "$@" "$line" ) > "$d/$i" 2>/dev/null &
    [ $((i % n)) -eq 0 ] && wait
  done
  wait
  j=1; while [ "$j" -le "$i" ]; do cat "$d/$j"; j=$((j + 1)); done
  rm -rf "$d"
)

# ghf WHAT gh ARGS...: run gh; on failure append "WHAT: <gh's error>" to $GH_FAILED
# (when set) and return 1, so a failed lookup can't read as an empty result.
ghf() {
  local what="$1" out err rc
  shift
  err=$(mktemp)
  out=$("$@" 2>"$err"); rc=$?
  if [ "$rc" -ne 0 ]; then
    [ -n "${GH_FAILED:-}" ] && printf '%s: %s\n' "$what" "$(grep -v '^$' "$err" | head -1 | cut -c1-160)" >> "$GH_FAILED"
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  printf '%s\n' "$out"
}
