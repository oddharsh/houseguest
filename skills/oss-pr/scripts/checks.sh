#!/usr/bin/env bash
# Which checks stronger than one example test does this repo already run, and where?
#
#   checks.sh [--files a,b,...] [--save FILE]
#
# Run from the root of a clone. A red-green test proves one input. Property tests and
# fuzzers search many; expect and snapshot tests turn a behavior change into a diff a
# reviewer reads in seconds; type tests make a bad call fail to compile; a deterministic
# simulator replays a race from a seed; formal specs and proofs cover every input. An agent
# makes each of these cheap to run and to repair, so use the ones the repo already has.
# Adding one is a decision for maintainers. For each kind it lists the tool, how many files
# use it, the 3 that share the most folders with --files, and the CI or script lines that
# run it. --save writes the same report to FILE (the ledger's checks.md). Read-only.

set -uo pipefail
files_arg="" save=""
while [ $# -gt 0 ]; do
  case "$1" in
    --files) files_arg="$2"; shift 2 ;;
    --save) save="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "checks.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
git rev-parse --git-dir >/dev/null 2>&1 || { echo "checks.sh: run this inside a clone" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)" || exit 2

mine=$(echo "$files_arg" | tr ',' '\n' | sed '/^$/d')
SKIP='(^|/)(vendor|third_party|third-party|node_modules|dist|build)/'
tracked=$(git ls-files)
# Where the repo runs things, "path: line": CI config, package.json scripts, task runners.
runs=$( { [ -d .github/workflows ] && grep -H -v -E '^[[:space:]]*#' .github/workflows/*.y*ml 2>/dev/null
  [ -f package.json ] && jq -r '.scripts // {} | to_entries[] | "package.json:\(.key): \(.value)"' package.json 2>/dev/null
  for f in Makefile justfile Justfile .gitlab-ci.yml .circleci/config.yml tox.ini noxfile.py; do
    [ -f "$f" ] && grep -H -v -E '^[[:space:]]*#' "$f"
  done; } | sed -E 's/^([^:]*):[[:space:]]*/\1: /')

# nearest: of the paths on stdin, the 3 closest to --files. A file named after one of
# yours (tree_fuzz.zig for tree.zig, test_make.py for _make.py) comes first, then the
# ones sharing the most leading folders.
nearest() {
  if [ -z "$mine" ]; then head -3; return; fi
  awk -v mine="$(echo "$mine" | tr '\n' ' ')" '
    BEGIN { n = split(mine, m, " ") }
    { best = 0; np = split($0, p, "/")
      for (i = 1; i <= n; i++) {
        nq = split(m[i], q, "/"); k = 0
        while (k < np - 1 && k < nq - 1 && p[k+1] == q[k+1]) k++
        stem = q[nq]; sub(/\.[^.]*$/, "", stem); sub(/^_+/, "", stem)
        if (length(stem) >= 3 && index(p[np], stem)) k += 1000
        if (k > best) best = k
      }
      print best "\t" $0 }' | sort -s -t$'\t' -k1,1nr | head -3 | cut -f2
}

found=0 any=0 open=""
section() {
  [ -n "$open" ] && [ "$found" = 0 ] && echo "- none"
  echo; echo "## $1"; found=0; open=1
}
# row <tool> <content-regex> <path-regex> <runs-regex>: report a tool when any tracked file
# matches the content regex or the path regex. POSIX ERE only, since git grep runs it.
row() {
  local ev="" r
  [ -n "$2" ] && ev=$(git grep -l -I -E "$2" 2>/dev/null)
  [ -n "$3" ] && ev=$(printf '%s\n%s\n' "$ev" "$(echo "$tracked" | grep -E "$3")")
  ev=$(echo "$ev" | sed '/^$/d' | grep -v -E "$SKIP" | sort -u)
  [ -z "$ev" ] && return
  found=1 any=1
  echo "- **$1**: $(echo "$ev" | wc -l | tr -d ' ') files"
  echo "$ev" | nearest | sed 's/^/  - `/; s/$/`/'
  if [ -n "$4" ]; then
    # Lines that run a command beat job names and env keys; a workflow can repeat one line.
    r=$(echo "$runs" | grep -E "$4" | awk '!seen[$0]++ { p = ($0 ~ /run:|RUSTFLAGS|cargo |npx |npm |pnpm |yarn |pytest|go test|make |just |zig |python /) ? 0 : 1; print p "\t" $0 }' \
      | sort -s -t$'\t' -k1,1n | cut -f2 | cut -c1-160 | head -2)
    if [ -n "$r" ]; then echo "$r" | sed 's/^/  - runs in /'; else echo "  - nothing in CI or the repo's scripts runs it by name"; fi
  fi
}

report() {
  echo "# Checks beyond example tests, at $(git rev-parse --short HEAD)"

  section "Property tests"
  row hypothesis 'from hypothesis import|^import hypothesis|@given\(' '' 'hypothesis'
  row proptest 'proptest!|use proptest|^proptest[[:space:]]*=' '(^|/)proptest-regressions/' 'proptest|PROPTEST_'
  row quickcheck 'quickcheck!|#\[quickcheck\]|import Test\.QuickCheck|^quickcheck[[:space:]]*=' '' 'quickcheck|QUICKCHECK_'
  row fast-check "from ['\"](fast-check|@fast-check/[a-z-]+)['\"]|require\(['\"]fast-check['\"]\)" '' 'fast-check'
  row 'rapid (Go)' 'pgregory\.net/rapid' '' 'rapid'
  row gopter 'github\.com/leanovate/gopter' '' ''
  row 'testing/quick' '"testing/quick"' '' ''
  row jqwik 'net\.jqwik' '' 'jqwik'
  row ScalaCheck 'org\.scalacheck' '' 'scalacheck'

  section "Fuzzers"
  row 'Go native fuzzing' 'func Fuzz[A-Za-z0-9_]*\([a-z]+ \*testing\.F\)' '(^|/)testdata/fuzz/' '-fuzz[= ]'
  row cargo-fuzz 'fuzz_target!' '(^|/)fuzz/Cargo\.toml$' 'cargo[[:space:]]+(\+[a-z0-9.-]+[[:space:]]+)?fuzz'
  row libFuzzer 'LLVMFuzzerTestOneInput' '' 'fuzz'
  row atheris '^import atheris|^from atheris' '' 'atheris'
  row Jazzer 'com\.code_intelligence\.jazzer|@FuzzTest' '' 'jazzer'
  row 'fuzz targets in the tree' '' '_fuzz\.[a-z]+$|(^|/)fuzz_tests?\.[a-z]+$|(^|/)fuzzers?/' 'fuzz'
  row 'OSS-Fuzz / ClusterFuzzLite' 'google/oss-fuzz/infra/cifuzz|google/clusterfuzzlite' '(^|/)\.clusterfuzzlite/' 'cifuzz|clusterfuzzlite'

  section "Expect and snapshot tests"
  row insta 'insta::|assert_(debug_|yaml_|json_|ron_|toml_|csv_|compact_debug_)?snapshot!' '\.snap$' 'insta'
  row expect-test 'expect!\[|expect_file!\[' '' 'UPDATE_EXPECT'
  row 'Jest/Vitest snapshots' 'toMatch(Inline|File)?Snapshot\(|toThrowErrorMatching(Inline)?Snapshot\(' '(^|/)__snapshots__/' ''
  row 'syrupy / inline-snapshot / pytest-snapshot' 'from syrupy|from inline_snapshot|snapshot\.assert_match\(' '(^|/)__snapshots__/.*\.ambr$' 'snapshot-update|inline-snapshot'
  row 'Go golden files' 'sebdah/goldie|gotest\.tools/v3/golden' '(^|/)testdata/.*\.golden$' ''
  row ppx_expect 'let%expect_test' '' ''
  row 'lit / FileCheck' '(//|;|#)[[:space:]]*CHECK(-NEXT|-NOT|-LABEL|-SAME|-DAG)?:' '(^|/)lit\.(site\.)?cfg(\.py)?$' 'lit|FileCheck'
  row 'expected-output files' '' '\.(expected|stdout|stderr)$' ''

  section "Type tests (a bad call must fail to compile)"
  row 'tsd / expect-type / Vitest typecheck' "expectTypeOf\(|expectType<|from ['\"](tsd|expect-type)['\"]" '\.test-d\.(ts|tsx|mts)$' 'tsd|typecheck'
  row 'trybuild' 'trybuild::TestCases' '' ''
  row 'compile_fail doctests' '```compile_fail' '' ''
  row 'Python assert_type' 'assert_type\(' '' ''

  section "Deterministic simulation"
  row loom 'loom::model|cfg\(loom\)' '' 'loom'
  row shuttle 'shuttle::check_' '' 'shuttle'
  row madsim 'madsim::' '' 'madsim'
  row turmoil 'turmoil::Builder' '' 'turmoil'
  row Antithesis 'antithesis_sdk|antithesishq' '(^|/)\.antithesis/' 'antithesis'
  row 'simulator in the tree' '' '(^|/)(simulator|simulation|vopr)(/|\.[a-z]+$)' 'simulator|vopr'

  section "Formal specs and proofs"
  row 'TLA+' '' '\.tla$' 'tlc|apalache|tla2tools'
  row Quint '' '\.qnt$' 'quint'
  row Alloy '' '\.als$' 'alloy'
  row Dafny '' '\.dfy$' 'dafny'
  row Lean '' '\.lean$' 'lake |lean'
  row 'Coq / Rocq' '' '(^|/)_(Coq|Rocq)Project$' 'coq|rocq'
  row Isabelle '' '\.thy$' 'isabelle'
  row Agda '' '\.agda$' 'agda'
  row Kani '#\[kani::proof|cfg\(kani\)' '' 'kani'
  row Verus 'verus!' '' 'verus'
  row 'Prusti / Creusot' 'prusti_contracts|creusot_contracts' '' 'prusti|creusot'
  row CBMC '__CPROVER_' '' 'cbmc'
  row 'Frama-C (ACSL)' '/\*@[[:space:]]*(requires|ensures|assigns|loop invariant)' '' 'frama-c'
  row 'Why3 / SAW / Cryptol' '' '\.(mlw|saw|cry)$' 'why3|saw|cryptol'
  [ "$found" = 0 ] && echo "- none"

  echo
  if [ "$any" = 0 ]; then
    echo "None found. An example test through the public interface is the strongest check this repo runs; don't add a framework for one PR (lean.md, rung 4)."
  else
    echo "Use what applies to your files the way \`references/proof.md\` says under \"Checks beyond the example.\""
  fi
}

if [ -n "$save" ]; then report | tee "$save"; exit "${PIPESTATUS[0]}"; else report; fi
