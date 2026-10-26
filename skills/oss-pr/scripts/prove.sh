#!/usr/bin/env bash
# Red-green proof that a change fixes what its test checks.
#
#   prove.sh [--base REF | --red-ref REF] [--tests REGEX] [--expect REGEX]
#            [--runs N] [--flake N] [--max-hunks N] [--suite "CMD"] -- <test command...>
#
# Green: the test command passes on HEAD.
# Red:   the same command fails on a tree that has the test but not the fix.
#   default     HEAD with every changed non-test file restored to merge-base(--base, HEAD)
#   --red-ref   a commit that has the test but not the fix (for inline tests, as in
#               Zig or Rust, where test and fix share a file: commit the test first)
#
# --expect   red output must match this regex, so a compile error can't pass as red
# --runs     repeat red and green N times each (default 3)
# --flake    run green N more times; any failure among them marks the test flaky (default 10, 0 skips)
# --max-hunks  check at most N hunks of the fix for coverage (default 20, 0 skips)
# --suite    a broader command (the repo's CI test target) to run once on HEAD
#
# Coverage: each hunk of the fix is reverted on its own, and the test command runs once.
# A hunk the test doesn't notice is untested or unneeded. Comment-only hunks are skipped.
# With --suite, a hunk the test misses is tried against the whole suite too: caught there,
# it counts as covered; missed there as well, it's flagged as possibly changing nothing.
# Uncovered hunks fail the proof unless coverage-ack.md in the ledger names them
# (`- path:line <reason>`), the same way house-ack.md answers housecheck flags.
# The added test lines are also scanned for flake risks (sleeps, clocks, unseeded
# randomness, network), which are reported but don't fail the proof.
#
# Needs a clean working tree, because it swaps files in place (so builds and
# installed dependencies are reused). A trap restores HEAD on exit or Ctrl-C.
# Writes proof.md and full logs to $(git rev-parse --git-dir)/houseguest/<branch>/.

set -uo pipefail

base="" red_ref="" tests_re="" expect="" runs=3 flake=10 max_hunks=20 suite=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --red-ref) red_ref="$2"; shift 2 ;;
    --tests) tests_re="$2"; shift 2 ;;
    --expect) expect="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --flake) flake="$2"; shift 2 ;;
    --max-hunks) max_hunks="$2"; shift 2 ;;
    --suite) suite="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
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

# Snapshots and golden files are the test's expected values, wherever they sit (insta keeps
# them in snapshots/ beside the code). Restoring one with the fix would make red compare the
# old output with the old snapshot and pass.
: "${tests_re:=(^|/)(tests?|spec|specs|__tests__|__snapshots__|snapshots|testdata|fixtures?)/|[._-](test|spec)s?\.[a-z]+$|(^|/)test_[^/]*$|_test\.[a-z]+$|\.(snap|ambr|golden)$}"

mode="" fix_files=""
if [ -n "$red_ref" ]; then
  mode="red-ref $(git rev-parse --short "$red_ref")"
  git rev-parse --verify -q "$red_ref^{commit}" >/dev/null || die "--red-ref $red_ref is not a commit"
  # Everything after the test-only commit is the fix, even in files that also hold tests.
  cov_from="$red_ref"
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
  cov_from="$mb"
fi
cov_files=$(git diff --name-only "$cov_from" HEAD | { [ -n "$red_ref" ] && cat || grep -v -E "$tests_re"; })

restore() {
  [ -n "${cov_files:-}" ] && echo "$cov_files" | while IFS= read -r f; do git checkout -q HEAD -- "$f" 2>/dev/null; done
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

# Flake check: the green test, many more times on HEAD.
flake_pass=0
for i in $(seq 1 "$flake"); do
  run flake "$i"; [ "$rc" -eq 0 ] && flake_pass=$((flake_pass + 1))
done

# Coverage: revert one hunk of the fix at a time and see whether the test notices.
cov_dir="$ledger/logs/hunks"; rm -rf "$cov_dir"; mkdir -p "$cov_dir"
git diff -U0 --no-color "$cov_from" HEAD -- $(echo "$cov_files" | tr '\n' ' ') | awk -v d="$cov_dir" '
  /^diff --git /{ hdr=$0 "\n"; inh=0; next }
  /^@@ /{ n++; f=sprintf("%s/%03d.patch", d, n); printf "%s", hdr > f; print > f; inh=1; next }
  inh { print > f; next }
  { hdr=hdr $0 "\n" }'
cov_total=0 cov_ok=0 cov_acked=0 cov_suite=0 cov_skipped=0 cov_lines=""
ack="$ledger/coverage-ack.md"
[ "$max_hunks" -gt 0 ] || rm -f "$cov_dir"/*.patch
for p in "$cov_dir"/*.patch; do
  [ -f "$p" ] || continue
  file=$(sed -n 's|^+++ b/||p' "$p" | head -1); [ -n "$file" ] || file=$(sed -n 's|^--- a/||p' "$p" | head -1)
  line=$(grep -m1 '^@@ ' "$p" | sed -E 's/^@@ -[0-9,]+ \+([0-9]+).*/\1/')
  changed=$(sed -n '/^@@ /,$p' "$p" | grep -E '^[-+]' | sed -E 's/^[-+]//')
  if ! echo "$changed" | grep -q -v -E '^[[:space:]]*($|//|#|/\*|\*|--|;|<!--)'; then cov_skipped=$((cov_skipped + 1)); continue; fi
  cov_total=$((cov_total + 1))
  if [ "$cov_total" -gt "$max_hunks" ]; then cov_total=$((cov_total - 1)); cov_lines="$cov_lines
- more hunks than --max-hunks $max_hunks; the rest weren't checked"; break; fi
  if ! git apply -R --unidiff-zero "$p" 2>/dev/null; then
    cov_lines="$cov_lines
- $file:$line couldn't be reverted alone (it depends on another hunk); not checked"; continue
  fi
  run "hunk-$(basename "$p" .patch)" 1
  # Missed by the narrow test: does anything in the wider suite notice? (Meta's ACH asks the
  # same of a planted fault: a change no test anywhere can tell apart may change nothing.)
  src_h=""
  if [ "$rc" -eq 0 ] && [ -n "$suite" ]; then
    bash -c "$suite" >"$ledger/logs/hunk-$(basename "$p" .patch)-suite.log" 2>&1; src_h=$?
  fi
  git checkout -q HEAD -- "$file" 2>/dev/null || rm -f "$file"
  if [ "$rc" -ne 0 ]; then
    cov_ok=$((cov_ok + 1))
  elif [ -n "$src_h" ] && [ "$src_h" -ne 0 ]; then
    cov_ok=$((cov_ok + 1)); cov_suite=$((cov_suite + 1)); cov_lines="$cov_lines
- $file:$line not caught by your test, but the wider suite fails without it (logs/hunk-$(basename "$p" .patch)-suite.log)"
  elif [ -f "$ack" ] && grep -q -F "$file:$line" "$ack"; then
    cov_acked=$((cov_acked + 1)); cov_lines="$cov_lines
- $file:$line not caught by the test; acknowledged: $(grep -m1 -F "$file:$line" "$ack" | sed "s|.*$file:$line[[:space:]]*||" | cut -c1-160)"
  else
    cov_lines="$cov_lines
- UNCOVERED $file:$line: reverting this hunk alone leaves $( [ -n "$src_h" ] && echo "the test and the whole suite green, so it may change nothing: delete it unless a new test shows otherwise" || echo "the test green") ($( { sed -n '/^@@ /,$p' "$p" | grep -E '^\+' ; sed -n '/^@@ /,$p' "$p" | grep -E '^-'; } | sed -E 's/^[-+][[:space:]]*//' | grep -v '^$' | head -1 | cut -c1-80))"
  fi
done
cov_missing=$((cov_total - cov_ok - cov_acked))

# Flake risks in the lines the PR adds to tests (with --red-ref, the test-only commit).
if [ -n "$red_ref" ]; then added=$(git diff -U0 --no-color "$red_ref^" "$red_ref" | awk '/^\+\+\+ b\//{ f=substr($0,7) } /^\+[^+]/{ print f ": " substr($0,2) }')
else added=$(git diff -U0 --no-color "$mb" HEAD | RE="$tests_re" awk '/^\+\+\+ b\//{ f=substr($0,7); t=(f ~ ENVIRON["RE"]) } t && /^\+[^+]/{ print f ": " substr($0,2) }'); fi
risk_lines=$(echo "$added" \
  | grep -E '\b(sleep|usleep|Thread\.sleep|time\.Sleep|setTimeout|setInterval|waitForTimeout|Date\.now|new Date\(\)|time\.Now|datetime\.now|time\.time\(|Instant::now|SystemTime::now|Math\.random|rand\.|random\.|thread_rng|uuid|https?://|localhost:[0-9]|fetch\(|requests\.(get|post))' \
  | head -8 | sed 's/^/- /')

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
[ "$flake_pass" -eq "$flake" ] || { status="FAIL"; reasons="$reasons; flaky: green passed $flake_pass/$flake extra runs"; }
[ "$cov_missing" -eq 0 ] || { status="FAIL"; reasons="$reasons; $cov_missing of $cov_total fix hunks untested, see Coverage"; }

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
  echo "- Flake check (HEAD, extra runs): $( [ "$flake" -gt 0 ] && echo "passed $flake_pass/$flake" || echo "skipped (--flake 0)")"
  echo "- Wider suite on HEAD: $suite_line"
  if [ "$max_hunks" -eq 0 ]; then echo "COVERAGE: skipped (--max-hunks 0)"
  else echo "COVERAGE: $cov_ok/$cov_total fix hunks caught by the test$( [ "$cov_suite" -gt 0 ] && echo ", $cov_suite of them only by the wider suite")$( [ "$cov_acked" -gt 0 ] && echo ", $cov_acked acknowledged")$( [ "$cov_skipped" -gt 0 ] && echo ", $cov_skipped comment-only skipped")"; fi
  echo
  echo "## Coverage"
  [ -n "$cov_lines" ] && echo "${cov_lines#?}" || echo "- every checked hunk turns the test red when reverted alone"
  if [ -n "$risk_lines" ]; then
    echo
    echo "## Flake risks in added test lines"
    echo "$risk_lines"
  fi
  echo
  echo "## Red output (tail of run 1)"
  tail_of "$ledger/logs/red-1.log"
  echo
  echo "## Green output (tail of run 1)"
  tail_of "$ledger/logs/green-1.log"
} >"$ledger/proof.md"
bash "$(dirname "$0")/receipt.sh" seal "$ledger/proof.md"

echo "$status: wrote $ledger/proof.md"
[ "$status" = "PASS" ]
