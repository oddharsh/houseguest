#!/usr/bin/env bash
# Regression test for the PR gate: commands and ledgers that once passed when they shouldn't.
#
#   bash tests/gate.sh
#
# Feeds hooks/gate.sh the hook's JSON on stdin, runs next.sh --all on a scratch ledger, and runs
# housecheck.sh in a scratch repo. Each case names the exit code it expects, and a blocked case
# names words its message must contain, so a block for the wrong reason fails too. Prints the
# cases that differ and exits 1 if any do.
#
# Needs jq, and ruff for the housecheck cases (skipped with a notice when it's missing). Touches
# no network and nothing outside a temp directory: `gh` is a stub that knows one PR, number 123
# on branch feat, and receipts are sealed with a scratch key.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SC="$ROOT/skills/oss-pr/scripts"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export HOUSEGUEST_RECEIPT_KEY="$W/receipt.key" CLAUDE_PLUGIN_ROOT="$ROOT" GH_LOG="$W/gh.log" XDG_CONFIG_HOME="$W/config"

mkdir "$W/bin"
cat > "$W/bin/gh" <<'EOF'
#!/bin/bash
echo "gh $*" >> "$GH_LOG"
# room.sh asks for the login, the set-default, and whether the repo is a fork (GH_PARENT).
case "$*" in
  "config get -h github.com user") echo me; exit 0 ;;
  "repo set-default --view") [ -z "${GH_DEFAULT:-}" ] || echo "$GH_DEFAULT"; exit 0 ;;
  "repo view "*isFork,parent*) echo "${GH_PARENT:-no}"; exit 0 ;;
  "repo view --json isFork -q .isFork") [ "${GH_PARENT:-no}" = no ] && echo false || echo true; exit 0 ;;
esac
case "$1 $2 $* " in "pr view "*" 123 "*) echo feat; exit 0 ;; esac
exit 1
EOF
chmod +x "$W/bin/gh"
export PATH="$W/bin:$PATH"

cases=0 failed=0
miss() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
gate() {  # gate <exit> <command> [<words the block message must contain>]
  local rc
  cases=$((cases + 1))
  jq -n --arg c "$2" --arg d "$PWD" '{tool_input: {command: $c}, cwd: $d}' | bash "$ROOT/hooks/gate.sh" >/dev/null 2>"$W/err"
  rc=$?
  [ "$rc" = "$1" ] || { miss "gate.sh exit $rc, want $1: $2"; return; }
  [ -z "${3:-}" ] || grep -q -F -- "$3" "$W/err" || miss "gate.sh's message lacks \"$3\": $2"
}
nx() {  # nx <exit> <what the ledger looks like> [<words next.sh must print>]
  local out rc
  cases=$((cases + 1))
  out=$(bash "$SC/next.sh" --all "$L" 2>&1); rc=$?
  [ "$rc" = "$1" ] || { miss "next.sh --all exit $rc, want $1: $2 ($out)"; return; }
  [ -z "${3:-}" ] || case "$out" in *"$3"*) ;; *) miss "next.sh --all doesn't say \"$3\": $2 ($out)" ;; esac
}
hc() {  # hc <house.md's STATUS> <what the tree looks like> [<words house.md must contain>]
  local st
  cases=$((cases + 1))
  bash "$SC/housecheck.sh" --base main >/dev/null 2>&1
  st=$(grep -m1 '^STATUS:' .git/houseguest/feat/house.md)
  [ "$st" = "STATUS: $1" ] || { miss "housecheck.sh wrote \"$st\", want \"STATUS: $1\": $2"; return; }
  [ -z "${3:-}" ] || grep -q -F -- "$3" .git/houseguest/feat/house.md || miss "house.md lacks \"$3\": $2"
}
repo() {  # repo <dir>: a new repo on main, and the shell inside it
  git init -q -b main "$1" && cd "$1" || exit 1
  git config user.email test@example.com; git config user.name test; git config commit.gpgsign false
}
ago() { date -u -v-"$1"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$1 minutes ago" +%Y-%m-%dT%H:%M:%SZ; }

# A fork: the `upstream` remote makes the gate apply. Branch feat has a ledger with nothing in
# it, so anything that opens a PR is blocked and names the missing phases.
repo "$W/fork"
echo one > a.txt; git add a.txt; git commit -q -m "init"
git remote add upstream https://example.com/up/stream.git
git switch -q -c feat; echo two >> a.txt; git commit -q -am "change a"
mkdir -p .git/houseguest/feat
PR='houseguest blocked this PR'

# --- Opening a PR, however the command is wrapped ----------------------------------------
gate 2 'gh pr create --fill' "$PR"
gate 2 'url=$(gh pr create --fill)' "$PR"
gate 2 '(gh pr create --fill)' "$PR"
gate 2 'bash -c "gh pr create --fill"' "$PR"
gate 2 "bash -c 'gh pr create'" "$PR"
gate 2 'echo `gh pr create`' "$PR"
gate 2 'gh pr create|cat' "$PR"
gate 0 'ls -la'
gate 0 'gh pr view 123 && gh pr list'
gate 0 'gh pr created'

# --- gh api opens a PR only when it POSTs to .../pulls -----------------------------------
gate 2 'gh api repos/o/r/pulls -f title=x -f head=me:feat -f base=main' "$PR"
gate 2 'gh api -X POST /repos/o/r/pulls --input body.json' "$PR"
gate 2 'gh api --method POST "repos/{owner}/{repo}/pulls" -F title=x' "$PR"
gate 0 'gh api repos/o/r/pulls'
gate 0 'gh api "repos/o/r/pulls?state=open"'
gate 0 'gh api -X GET repos/o/r/pulls -f state=open'
gate 0 'gh api repos/o/r/pulls/123/comments -f body=hi'

# --- A command chained with opening a PR still gets the PR's checks ----------------------
gate 2 'git push -u origin feat && gh pr create --fill' "$PR"
gate 2 'gh pr create --fill && gh pr merge --auto --squash' "$PR"
gate 0 'git push origin feat'

# --- Gerrit uploads: gated here because feat has a ledger --------------------------------
GERRIT='houseguest blocked this Gerrit change'
gate 2 'git review' "$GERRIT"
gate 2 '(git review)' "$GERRIT"
gate 2 'bash -c "git review"' "$GERRIT"
gate 2 'bash -c "git push origin HEAD:refs/for/main"' "$GERRIT"
gate 0 'git review -d 1234'
gate 0 '(git review -d 1234)'
gate 0 'bash -c "git review -l"'
gate 0 "sh -c 'git review --list'"

# --- Every matcher and exemption shares one command boundary -----------------------------
# git-review's read-only exemption once ran past the end of its own command, and a path
# in front of gh or git once hid the command word.
gate 2 'git review -t topic && ls -l' "$GERRIT"
gate 2 'git review -l; git review' "$GERRIT"
gate 2 'git review -d 1234 && git review' "$GERRIT"
gate 2 'git cl upload && git review -l' "$GERRIT"
gate 2 '/usr/bin/git review' "$GERRIT"
gate 0 '/usr/bin/git review -l'
gate 0 'git review -d 1234 && git review -l'
gate 2 '/opt/homebrew/bin/gh pr create --fill' "$PR"
gate 2 '{ gh pr create --fill; }' "$PR"
gate 2 'xargs gh pr create --fill' "$PR"
gate 2 'gh api repos/o/r/pulls \
  -f title=x' "$PR"
gate 0 'gh api repos/o/r/pulls; echo -f title=x'
git switch -q -c unreviewed  # no ledger, no review config: only `repo upload` makes this Gerrit
gate 2 'repo upload .' "$GERRIT"
gate 0 'git cl upload -m "fix repo uploads"'
git switch -q feat

# --- recon said PRIVATE: no push, no issue, in a fork or out of one ----------------------
PRIVATE='DECISION: PRIVATE'
printf 'DECISION: PRIVATE\n' > .git/houseguest/feat/recon.md
gate 2 'git push origin feat' "$PRIVATE"
gate 2 '(git push origin feat)' "$PRIVATE"
gate 2 'echo "$(gh issue create --title x)"' "$PRIVATE"
gate 2 'git push origin feat && gh pr create --fill' "$PRIVATE"
git remote rename upstream elsewhere
gate 2 'git push origin feat && gh pr create --fill' "$PRIVATE"
gate 0 'gh pr create --fill'
git remote rename elsewhere upstream
rm .git/houseguest/feat/recon.md

# --- gh pr merge: the PR is found wherever its number sits -------------------------------
MERGE='houseguest blocked this merge. merge.sh says'
AUTO='--auto merges whenever checks go green'
gate 2 'gh pr merge 123 --squash' "$MERGE"
gate 2 'gh pr merge --squash 123' "$MERGE"
gate 2 'gh pr merge -R o/r 123 -s' "$MERGE"
gate 2 'gh pr merge -b "body text 9" -t "subject" 123 --squash' "$MERGE"
gate 2 'gh pr merge --repo=o/r --squash "123"' "$MERGE"
gate 2 'gh pr merge -b "two words" -R "o/r" 123' "$MERGE"
gate 2 'x=$(gh pr merge --squash 123)' "$MERGE"
gate 2 'gh pr merge --auto 123' "$AUTO"
gate 2 'bash -c "gh pr merge 123 --auto"' "$AUTO"
gate 0 'gh pr merge --squash 456'
gate 0 'gh pr merge 456 --squash'
cases=$((cases + 1))
grep -q -x -F 'gh pr view 123 -R o/r --json headRefName -q .headRefName' "$GH_LOG" \
  || miss "gate.sh never looked up PR 123 in o/r for \`gh pr merge -R o/r 123 -s\`"

# --- HOUSEGUEST_SKIP=1 skips only as an assignment at the start of the command -----------
gate 0 'HOUSEGUEST_SKIP=1 gh pr create --fill'
gate 0 'GH_TOKEN=x HOUSEGUEST_SKIP=1 gh pr create --fill'
gate 2 'gh pr create --title x --body "prefix the command with HOUSEGUEST_SKIP=1 to skip"' "$PR"
gate 2 'git commit -m "document HOUSEGUEST_SKIP=1" && gh pr create --fill' "$PR"
gate 2 'gh pr create --fill --body "$(cat <<EOF
To skip, run:
HOUSEGUEST_SKIP=1 gh pr create
EOF
)"' "$PR"
gate 2 'echo HOUSEGUEST_SKIP=1; gh pr create --fill' "$PR"
gate 2 'cd . && HOUSEGUEST_SKIP=1 gh pr create --fill' "$PR"

# --- A ledger where every phase holds, then one thing wrong at a time --------------------
git switch -q -c ready
L="$PWD/.git/houseguest/ready"; mkdir -p "$L"
head=$(git rev-parse HEAD)
seal() { bash "$SC/receipt.sh" seal "$1"; }
printf 'VERDICT: N/A (docs only)\n' > "$L/intent.md"
printf 'DECISION: GO\n- AI policy: none found\n- Reproduces on: n/a: not a bug fix\n' > "$L/recon.md"
echo style > "$L/style.md"
printf 'STATUS: PASS\nSHA: %s\n' "$head" > "$L/house.md"; seal "$L/house.md"
printf 'STATUS: N/A (docs)\nSHA: %s\n' "$head" > "$L/proof.md"
echo "Fix a" > "$L/pr-title.txt"; echo "Body." > "$L/pr-body.md"
echo "STOP: clean (round 1)" > "$L/rounds.md"
body=$(openssl dgst -sha256 < "$L/pr-body.md" | awk '{print $NF}')
bash "$SC/receipt.sh" run "$L/runs.log" -- true >/dev/null
final() {  # final <STATUS> [<BODY hash>]: write final.md unsealed
  printf 'STATUS: %s\nSHA: %s\n' "$1" "$head" > "$L/final.md"
  [ -z "${2:-}" ] || printf 'BODY: sha256=%s\n' "$2" >> "$L/final.md"
  rm -f "$L/final.md.seal"
}
recheck() {  # recheck [<Checked: time>]: write a sealed CLEAR report
  { echo "# Recheck"; [ -z "${1:-}" ] || echo "Checked: $1"; echo; echo "STATUS: CLEAR"; } > "$L/recheck.md"
  seal "$L/recheck.md"
}
final PASS "$body"; seal "$L/final.md"
recheck "$(ago 0)"
nx 0 'sealed final.md with a run on HEAD, recheck from now'
gate 0 'gh pr create --fill'

# The user-checked final.md waives runs.log and nothing else.
USER_CHECKED='PASS (checked by the user: ran it on their iPhone)'
final "$USER_CHECKED"
nx 1 'final.md hand-written as checked by the user, no seal, no BODY' "isn't sealed as it stands"
gate 2 'gh pr create --fill' "isn't sealed as it stands"
final "$USER_CHECKED" "$body"; seal "$L/final.md"
nx 0 'the same line with BODY, sealed after writing it'
echo "edited" >> "$L/final.md"
nx 1 'that sealed file edited afterwards' "isn't sealed as it stands"
final "$USER_CHECKED" "$body"; seal "$L/final.md"
echo "Body, rewritten." > "$L/pr-body.md"
nx 1 'checked by the user and sealed, then pr-body.md rewritten' 'pr-body.md changed after the final check read it'
echo "Body." > "$L/pr-body.md"
final PASS "$body"; seal "$L/final.md"

# pr-body.md can be a symlink to a draft whose YAML frontmatter is never posted, so the
# BODY: hash covers the text under it.
printf -- '---\nstatus: needs-review\n---\n\nBody.\n' > "$W/draft.md"
rm "$L/pr-body.md"; ln -s "$W/draft.md" "$L/pr-body.md"
nx 0 'pr-body.md a symlink to a draft with frontmatter over the same body'
printf -- '---\nstatus: needs-review\nnext: OK the text\n---\n\nBody.\n' > "$W/draft.md"
nx 0 'only the draft frontmatter edited'
printf -- '---\nstatus: needs-review\n---\n\nBody, rewritten.\n' > "$W/draft.md"
nx 1 'the body under the frontmatter rewritten' 'pr-body.md changed after the final check read it'
printf -- '---\nstatus: needs-review\nBody.\n' > "$W/draft.md"
nx 1 'a draft whose frontmatter never closes' 'pr-body.md changed after the final check read it'
rm "$L/pr-body.md"; echo "Body." > "$L/pr-body.md"

# recheck.md is good for an hour, by its sealed Checked: line.
recheck 2026-11-01T00:00:00Z
nx 1 'recheck.md checked on 2026-11-01' 'recheck.md is over an hour old'
gate 2 'gh pr create --fill' 'recheck.md is over an hour old'
recheck "$(ago 59)"
nx 0 'recheck.md from 59 minutes ago'
recheck "$(ago 61)"
nx 1 'recheck.md from 61 minutes ago' 'recheck.md is over an hour old'
recheck
nx 1 'recheck.md with no Checked: line' 'recheck.md is over an hour old'

# --- What a person checks by hand goes beside the sealed recheck.md, not inside it ----------
# On Gerrit, recheck.sh can't see the review server, so the contributor writes what it shows.
# Written into recheck.md, that broke the seal, and next.sh said to rerun recheck.sh, which
# overwrote the findings: a loop. They live in recheck-notes.md, which no seal covers.
recheck "$(ago 0)"
echo "- no open changes on the review server touch a.txt" > "$L/recheck-notes.md"
nx 0 'findings in recheck-notes.md beside a sealed CLEAR recheck.md, no reseal'
echo "- no open changes on the review server touch a.txt" >> "$L/recheck.md"
nx 1 'findings appended to recheck.md itself' 'write your own findings in recheck-notes.md'
rm -f "$L/recheck-notes.md"; recheck "$(ago 0)"

# --- Your own repos: no skip flag needed --------------------------------------------------
# origin is yours (gh login "me"); upstream is the template it came from, which gh targets
# first when nothing names a repo. The branch's ledger is empty, so a gated command blocks.
repo "$W/mine"
echo one > a.txt; git add a.txt; git commit -q -m "init"
git remote add origin https://github.com/me/tool.git
git remote add upstream git@github.com:tmpl/tool.git
git switch -q -c feat; mkdir -p .git/houseguest/feat
gate 2 'gh pr create --fill' "$PR"
gate 0 'gh pr create -R me/tool --fill'
gate 0 'gh pr create --repo=me/tool --fill'
gate 0 'gh pr create --repo "Me/tool" --fill'
gate 0 'gh api repos/me/tool/pulls -f title=x'
gate 2 'gh pr create -R me/tool --fill && gh pr create -R tmpl/tool --fill' "$PR"
gate 0 'gh pr merge -R me/tool 123 --squash'
export GH_DEFAULT=me/tool
gate 0 'gh pr create --fill'
export GH_DEFAULT=tmpl/tool
gate 2 'gh pr create --fill' "$PR"
unset GH_DEFAULT
mkdir -p "$W/config/houseguest"
echo "acme own" > "$W/config/houseguest/rooms"
gate 0 'gh pr create -R acme/tool --fill'
gate 2 'gh pr create -R acmeco/tool --fill' "$PR"
printf '# a repo line beats its owner, and the login\nme/tool guest\n' > "$W/config/houseguest/rooms"
gate 2 'gh pr create -R me/tool --fill' "$PR"
rm "$W/config/houseguest/rooms"
printf 'DECISION: PRIVATE\n' > .git/houseguest/feat/recon.md
export GH_DEFAULT=me/tool
gate 2 'git push origin feat' 'DECISION: PRIVATE'
unset GH_DEFAULT
rm .git/houseguest/feat/recon.md

# A fork you own sends its PRs to the parent, which isn't yours.
repo "$W/myfork"
echo one > a.txt; git add a.txt; git commit -q -m "init"
git remote add origin https://github.com/me/fork.git
git switch -q -c feat; mkdir -p .git/houseguest/feat
export GH_PARENT=tmpl/fork
gate 2 'gh pr create --fill' "$PR"
export GH_PARENT=no
gate 0 'gh pr create --fill'
unset GH_PARENT

# --- housecheck.sh: .c++ files get the C++ checks ----------------------------------------
# workerd names its C++ sources .c++, which no extension pattern matched: clang-format never
# ran, the width check used prettier's 80 columns, and the comment and license checks skipped the
# file. A stub clang-format stands in for the real one, which isn't always installed.
printf '#!/bin/bash\nexit 0\n' > "$W/bin/clang-format"; chmod +x "$W/bin/clang-format"
repo "$W/cxx"
printf 'ColumnLimit: 100\n' > .clang-format; printf '{"printWidth": 80}\n' > .prettierrc.json
for n in 1 2 3; do printf '// Copyright (c) 2026 Example\nint f%s();\n' "$n" > "f$n.c++"; done
git add .; git commit -q -m "init"
git switch -q -c feat
printf '// Copyright (c) 2026 Example\nint f1();\nint long_name_%s();\n' "$(printf 'x%.0s' $(seq 1 75))" > f1.c++
printf '// now handles the empty case\nint g();\n' > g.c++
git add .; git commit -q -m "Add g.c++"
hc 'REVIEW (2 flag(s) to fix or acknowledge)' 'a 90-column line under ColumnLimit 100, a narrating comment, a new file without the license header' 'ok T:clang-format'
cases=$((cases + 1))
grep -q -F '**FLAG** C1 `g.c++:1`' .git/houseguest/feat/house.md && grep -q -F '**FLAG** L1 `g.c++`' .git/houseguest/feat/house.md \
  && ! grep -q -F 'W4' .git/houseguest/feat/house.md || miss "house.md for .c++ files lacks the C1 or L1 flag, or has a W4 flag: $(grep -E 'FLAG|T:' .git/houseguest/feat/house.md)"
rm "$W/bin/clang-format"

# --- housecheck.sh: the files it checked have to be the files at HEAD --------------------
if command -v ruff >/dev/null 2>&1; then
  repo "$W/py"
  printf '[tool.ruff]\nfix = true\n' > pyproject.toml
  printf 'def one():\n    return 1\n' > a.py
  git add .; git commit -q -m "init"
  git switch -q -c feat
  printf 'import os\n\n\ndef one():\n    return 1\n' > a.py
  git commit -q -am "Add an import"
  TREE='the working tree differs from HEAD in a.py'
  hc 'FAIL (1 to fix)' 'ruff with fix = true rewrites a.py during the check' "$TREE"
  git checkout -q -- a.py
  printf '[tool.ruff]\n' > pyproject.toml; git commit -q -am "Turn autofix off"
  hc 'FAIL (1 to fix)' 'clean tree, HEAD has the unused import' '**FAIL** T:ruff'
  printf 'def one():\n    return 1\n' > a.py
  hc 'FAIL (1 to fix)' 'an uncommitted edit removes the import' "$TREE"
  git commit -q -am "Drop the import"
  hc 'PASS' 'that edit committed, clean tree'
else
  echo "SKIP housecheck.sh cases: ruff isn't installed"
fi

# --- housecheck.sh: a tool house.sh can't run from the root reads NOT RUN, not FAIL --------
repo "$W/ts"
mkdir src && printf '{"include": ["**/*.ts"]}\n' > src/tsconfig.json
git add .; git commit -q -m "init"
git switch -q -c feat
printf 'const one = 1;\n' > src/a.js; git add .; git commit -q -m "Add a.js"
hc 'PASS' 'a .js file under a tsconfig that includes only .ts'
printf 'const two = 2;\n' > src/b.ts; git add .; git commit -q -m "Add b.ts"
hc 'INCOMPLETE (1 check(s) not run)' 'a .ts file under that nested tsconfig' '**NOT RUN** T:tsc: no tsconfig.json at the repo root, and your files sit under src/tsconfig.json'

echo "$cases cases, $failed failed"
[ "$failed" -eq 0 ]
