#!/usr/bin/env bash
# Test that house.sh adds eslint and tsc only when the command it emits would load a config for
# the changed files, and reports NOTRUN naming the config when only a nested one covers them.
#
#   bash tests/house.sh
#
# Builds throwaway git repos; nothing touches the network or runs eslint or tsc. Each case that
# drops a tool sits beside the case that keeps it. Prints the cases that differ and exits 1 if any do.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
S="$ROOT/skills/oss-pr/scripts"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

cases=0 failed=0
miss() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
same() {  # same <what> <got> <want>
  cases=$((cases + 1))
  [ "$2" = "$3" ] || miss "$1
  got:  $2
  want: $3"
}
# repo <name> <package.json> <path>...: a committed repo with that package.json and an empty file
# at each path.
repo() {
  local r="$W/$1" p; printf '%s\n' "$2" > "$W/pkg"; shift 2
  git init -q -b main "$r"; cp "$W/pkg" "$r/package.json"
  for p in "$@"; do mkdir -p "$r/$(dirname "$p")"; : > "$r/$p"; done
  git -C "$r" add -A && git -C "$r" -c user.name=t -c user.email=t@t commit -q -m init
  echo "$r"
}
machine() { (cd "$1" && bash "$S/house.sh" --machine --files "$2") | grep -E '^(eslint|tsc|NOTRUN)	'; }
T=$(printf '\t')
DEPS='{"devDependencies": {"eslint": "9.0.0", "typescript": "5.4.0"}}'

# workerd at 6e8333e01: eslint and typescript as dependencies, a base eslint config under tools/,
# every tsconfig nested, no eslint config above the changed .js, and tsconfigs above it that
# include only TypeScript.
r=$(repo workerd "$DEPS" src/workerd/api/tests/a.js tools/base.eslint.config.mjs src/cloudflare/eslint.config.mjs src/workerd/api/tests/tsconfig.json types/tsconfig.json)
same "no eslint config above a .js file, a tsconfig above it: neither tool, and no NOTRUN" "$(machine "$r" src/workerd/api/tests/a.js)" ""
same "the same tsconfig above a .ts file: NOTRUN tsc" "$(machine "$r" src/workerd/api/tests/b.ts)" \
"NOTRUN${T}tsc${T}no tsconfig.json at the repo root, and your files sit under src/workerd/api/tests/tsconfig.json; run tsc -p on the one that owns them"

r=$(repo nested "$DEPS" src/a.ts src/eslint.config.mjs src/tsconfig.json types/tsconfig.json)
same "nested configs above the changed file: a NOTRUN for each naming the config" "$(machine "$r" src/a.ts)" \
"NOTRUN${T}eslint${T}your files sit under src/eslint.config.mjs, which eslint doesn't load from the repo root; run eslint the way the repo does for that folder
NOTRUN${T}tsc${T}no tsconfig.json at the repo root, and your files sit under src/tsconfig.json; run tsc -p on the one that owns them"

r=$(repo root "$DEPS" src/a.ts eslint.config.mjs tsconfig.json src/eslint.config.mjs src/tsconfig.json)
same "root flat config and root tsconfig.json: both tools added" "$(machine "$r" src/a.ts)" \
"eslint${T}npx --no-install eslint {FILES}
tsc${T}npx --no-install tsc --noEmit -p ."

r=$(repo legacy "$DEPS" src/a.ts src/.eslintrc.json)
same "a legacy .eslintrc above the changed file: eslint added" "$(machine "$r" src/a.ts)" \
"eslint${T}npx --no-install eslint {FILES}"

r=$(repo legacy-elsewhere "$DEPS" src/a.ts other/.eslintrc.json)
same "a legacy .eslintrc beside, not above, the changed file: nothing" "$(machine "$r" src/a.ts)" ""

r=$(repo pkgconfig '{"devDependencies": {"eslint": "8.0.0"}, "eslintConfig": {"root": true}}' src/a.ts)
same "eslintConfig in package.json: eslint added" "$(machine "$r" src/a.ts)" \
"eslint${T}npx --no-install eslint {FILES}"

r=$(repo script-config '{"devDependencies": {"eslint": "9.0.0"}, "scripts": {"lint": "eslint -c tools/base.eslint.config.mjs src"}}' src/a.ts tools/base.eslint.config.mjs)
same "the repo's lint script passes -c: eslint added with it" "$(machine "$r" src/a.ts)" \
"eslint${T}npx --no-install eslint -c tools/base.eslint.config.mjs {FILES}"

echo "$cases cases, $failed failed"
[ "$failed" -eq 0 ]
