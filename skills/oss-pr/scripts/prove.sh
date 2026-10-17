#!/usr/bin/env bash
# Red-green proof that a change fixes what its test checks.
#
#   prove.sh [--base REF | --red-ref REF] [--tests REGEX] [--expect REGEX]
#            [--runs N] [--suite "CMD"] -- <test command...>
#
# Green: the test command passes on HEAD.
# Red:   the same command fails on a tree that has the test but not the fix.
#   default     HEAD with every changed non-test file restored to merge-base(--base, HEAD)
#   --red-ref   a commit that has the test but not the fix (for inline tests, as in
#               Zig or Rust, where test and fix share a file: commit the test first)
#
# --expect   red output must match this regex, so a compile error can't pass as red
# --runs     repeat red and green N times each to catch flaky tests (default 1)
# --suite    a broader command (the repo's CI test target) to run once on HEAD
#
# Needs a clean working tree, because it swaps files in place (so builds and
# installed dependencies are reused). A trap restores HEAD on exit or Ctrl-C.
# Writes proof.md and full logs to $(git rev-parse --git-dir)/houseguest/<branch>/.

set -uo pipefail

base="" red_ref="" tests_re="" expect="" runs=1 suite=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --red-ref) red_ref="$2"; shift 2 ;;
    --tests) tests_re="$2"; shift 2 ;;
    --expect) expect="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --suite) suite="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "prove.sh: unknown argument $1 (put the test command after --)" >&2; exit 2 ;;
  esac
done
[ $# -gt 0 ] || { echo "prove.sh: missing test command after --" >&2; exit 2; }
cmd=("$@")

die() { echo "prove.sh: $*" >&2; exit 2; }

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repo"
git diff --quiet && git diff --cached --quiet || die "working tree has uncommitted changes; commit first so the proof binds to a commit"

branch=$(git branch --show-current)
[ -n "$branch" ] || die "detached HEAD; check out your topic branch"
head_sha=$(git rev-parse HEAD)
ledger="$(git rev-parse --git-dir)/houseguest/$branch"
mkdir -p "$ledger/logs"

: "${tests_re:=(^|/)(tests?|spec|specs|__tests__|testdata|fixtures?)/|[._-](test|spec)s?\.[a-z]+$|(^|/)test_[^/]*$|_test\.[a-z]+$}"

mode="" fix_files=""
if [ -n "$red_ref" ]; then
  mode="red-ref $(git rev-parse --short "$red_ref")"
  git rev-parse --verify -q "$red_ref^{commit}" >/dev/null || die "--red-ref $red_ref is not a commit"
else
  if [ -z "$base" ]; then
    for cand in upstream/HEAD origin/HEAD upstream/main origin/main upstream/master origin/master; do
      if git rev-parse --verify -q "$cand" >/dev/null; then base="$cand"; break; fi
    done
  fi
  [ -n "$base" ] || die "couldn't find a base branch; pass --base <ref>"
  mb=$(git merge-base "$base" HEAD) || die "no merge-base between $base and HEAD"
  fix_files=$(git diff --name-only "$mb" HEAD | grep -v -E "$tests_re")
  test_files=$(git diff --name-only "$mb" HEAD | grep -E "$tests_re")
  [ -n "$fix_files" ] || die "no non-test files changed since $base; nothing to revert"
  [ -n "$test_files" ] || die "no changed files match --tests; is the test in the same file as the fix? Use --red-ref"
  mode="revert fix files to merge-base $(git rev-parse --short "$mb") ($base)"
fi

restore() {
  if [ -n "$red_ref" ]; then
    git checkout -q "$branch" 2>/dev/null
  elif [ -n "$fix_files" ]; then
    echo "$fix_files" | while IFS= read -r f; do git checkout -q HEAD -- "$f" 2>/dev/null; done
  fi
}
trap restore EXIT INT TERM

make_red() {
  if [ -n "$red_ref" ]; then
    git checkout -q --detach "$red_ref"
  else
    echo "$fix_files" | while IFS= read -r f; do
      if git cat-file -e "$mb:$f" 2>/dev/null; then git checkout -q "$mb" -- "$f"; else rm -f "$f"; fi
    done
  fi
}

# run <label> <i> -> sets rc, writes log
run() {
  log="$ledger/logs/$1-$2.log"
  "${cmd[@]}" >"$log" 2>&1
  rc=$?
}

# Test runners color their output, and escape codes can split the text --expect looks for.
export NO_COLOR=1 FORCE_COLOR=0
green_pass=0 red_fail=0 red_expect_ok=0
for i in $(seq 1 "$runs"); do
  run green "$i"; [ "$rc" -eq 0 ] && green_pass=$((green_pass + 1))
done

make_red
for i in $(seq 1 "$runs"); do
  run red "$i"
  if [ "$rc" -ne 0 ]; then
    red_fail=$((red_fail + 1))
    if [ -z "$expect" ] || sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' "$log" | grep -q -E "$expect"; then red_expect_ok=$((red_expect_ok + 1)); fi
  fi
done
restore
trap - EXIT INT TERM

suite_line="not run"
if [ -n "$suite" ]; then
  bash -c "$suite" >"$ledger/logs/suite.log" 2>&1
  src=$?
  suite_line="\`$suite\` exit $src (log: logs/suite.log)"
fi

status="PASS"
reasons=""
[ "$green_pass" -eq "$runs" ] || { status="FAIL"; reasons="$reasons; green passed $green_pass/$runs"; }
[ "$red_fail" -eq "$runs" ] || { status="FAIL"; reasons="$reasons; red failed only $red_fail/$runs, so the test may not cover the fix"; }
[ "$red_expect_ok" -eq "$red_fail" ] || { status="FAIL"; reasons="$reasons; red failed for the wrong reason ($red_expect_ok/$red_fail matched --expect)"; }
if [ -n "$suite" ] && [ "$src" -ne 0 ]; then status="FAIL"; reasons="$reasons; suite exit $src"; fi

tail_of() { echo '```'; tail -n 25 "$1"; echo '```'; }

{
  echo "# Proof: $branch"
  echo "STATUS: $status${reasons:+ (${reasons#; })}"
  echo "SHA: $head_sha"
  echo
  echo "- Command: \`${cmd[*]}\`"
  echo "- Red tree: $mode"
  [ -n "$fix_files" ] && echo "- Fix files reverted for red: $(echo "$fix_files" | tr '\n' ' ')"
  echo "- Green (HEAD): passed $green_pass/$runs"
  echo "- Red (no fix): failed $red_fail/$runs${expect:+, $red_expect_ok matched \`$expect\`}"
  echo "- Wider suite on HEAD: $suite_line"
  echo
  echo "## Red output (tail of run 1)"
  tail_of "$ledger/logs/red-1.log"
  echo
  echo "## Green output (tail of run 1)"
  tail_of "$ledger/logs/green-1.log"
} >"$ledger/proof.md"

echo "$status: wrote $ledger/proof.md"
[ "$status" = "PASS" ]
