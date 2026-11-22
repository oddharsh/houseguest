#!/usr/bin/env bash
# Test that a failed lookup reads as unknown, never as "nothing found", in policy.sh, channels.sh,
# and house.sh.
#
#   bash tests/lookups.sh
#
# Puts stub gh, curl, npm, and git (ls-remote only) first on PATH, so no case touches the network.
# Each failure case sits beside the healthy run it differs from. Prints the cases that differ and
# exits 1 if any do.

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

SHA=1111111111111111111111111111111111111111
mkdir -p "$W/bin"
# gh: answers the calls these scripts make on a tiny repo o/r. GH_FAIL (a regex over the
# arguments) fails a call the way GitHub's rate limiter does.
cat > "$W/bin/gh" <<EOF
#!/usr/bin/env bash
args="\$*"
if [ -n "\${GH_FAIL:-}" ] && printf '%s' "\$args" | grep -q -E "\$GH_FAIL"; then
  echo "gh: API rate limit exceeded (HTTP 403)" >&2; exit 1
fi
case "\$args" in
  *rate_limit*) echo "5000 2026-11-22T00:00:00Z" ;;
  *"/commits/$SHA --jq .sha") echo $SHA ;;
  *"/commits/$SHA --jq .commit.committer.date") echo 2026-11-01T00:00:00Z ;;
  *"/commits/v1.0 --jq .sha") echo $SHA ;;
  *"/commits/1.0 --jq .sha") echo '{"message":"No commit found for SHA: 1.0","status":"422"}'; echo "gh: No commit found for SHA: 1.0 (HTTP 422)" >&2; exit 1 ;;
  *"repos/o/r --jq .default_branch") echo main ;;
  *"commits?sha=main"*) echo $SHA ;;
  *matching-refs*) ;;
  *"releases?per_page=50"*) echo '[]' ;;
  *"commits?per_page=1"*) echo $SHA ;;
  *"git/trees/$SHA?recursive=1") echo '{"truncated":false,"tree":[{"type":"blob","path":"CONTRIBUTING.md"}]}' ;;
  *"contents/CONTRIBUTING.md"*) echo "Thanks for helping. Open an issue first." ;;
  *search/issues*) ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
EOF
# curl: writes CURL_BODY to -o and prints CURL_CODE for -w '%{http_code}'.
cat > "$W/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
[ -n "$out" ] && printf '%s' "${CURL_BODY:-}" > "$out"
printf '%s' "${CURL_CODE:-200}"
EOF
# npm: NPM_ERR names the error `npm view` fails with; unset, it answers like a 404.
cat > "$W/bin/npm" <<'EOF'
#!/usr/bin/env bash
echo "npm error code ${NPM_ERR:-E404}" >&2; exit 1
EOF
real_git=$(command -v git)
cat > "$W/bin/git" <<EOF
#!/usr/bin/env bash
[ "\$1" = ls-remote ] && { printf '%s\trefs/tags/v1.0\n' $SHA; exit 0; }
exec "$real_git" "\$@"
EOF
chmod +x "$W/bin/"*
export PATH="$W/bin:$PATH"

# --- channels.sh -----------------------------------------------------------------------
ch() {  # ch <prod> <package> -> stdout, then "rc=N", then stderr
  bash "$S/channels.sh" --repo o/r --prod "$1" --package "$2" --paths src --as-of 2026-11-10 > "$W/out" 2> "$W/err"
  echo "rc=$?"
}
got=$(ch "$SHA" pypi:foo); verdicts=$(grep -c -E '^- (Same commit|VERDICT)' "$W/out")
same "channels: a 404 from PyPI is an answer" "$got $(cat "$W/err") $verdicts" "rc=0 channels.sh: no pypi versions found for foo 1"
got=$(CURL_CODE=500 ch "$SHA" pypi:foo)
same "channels: PyPI answering 500 stops the run" "$got $(cat "$W/err")" "rc=3 channels.sh: couldn't read https://pypi.org/pypi/foo/json (HTTP 500); rerun rather than guess the channels"
same "channels: PyPI answering 500 prints no report" "$(cat "$W/out")" ""

got=$(ch "$SHA" npm:foo)
same "channels: npm's E404 is an answer" "$got $(cat "$W/err")" "rc=0 channels.sh: no npm versions found for foo"
got=$(NPM_ERR=ECONNREFUSED ch "$SHA" npm:foo)
same "channels: npm unreachable stops the run" "$got $(cat "$W/err")" "rc=3 channels.sh: couldn't read foo from npm (npm error code ECONNREFUSED); rerun rather than guess the channels"

# sha_of tries 1.0 (422 "No commit found"), then foo@1.0 (404), then v1.0: neither miss is a failure.
got=$(ch 1.0 pypi:foo)
same "channels: a 422 and a 404 while resolving a version are answers" "$got $(grep -c 'LOOKUPS FAILED' "$W/out")" "rc=0 0"
same "channels: prod resolves through v1.0" "$(grep '^Prod:' "$W/out")" "Prod: 1.0, commit 111111111 (2026-11-01T00:00:00Z)"
got=$(GH_FAIL=matching-refs ch "$SHA" pypi:foo)
same "channels: a failed branch listing marks the report and exits 3" "$got $(grep 'LOOKUPS FAILED' "$W/out")" "rc=3 **LOOKUPS FAILED while finding the channels** (rate limit or network). A build missing below may still exist; rerun before trusting SKIP."

# --- policy.sh -------------------------------------------------------------------------
pol() { bash "$S/policy.sh" --repo o/r --as-of 2026-11-10 > "$W/out" 2> "$W/err"; echo "rc=$?"; }
got=$(pol)
same "policy: no rule and no failures is NONE FOUND" "$got $(grep 'AI POLICY' "$W/out")" "rc=0 **AI POLICY: NONE FOUND.** Sources checked:"
got=$(GH_FAIL=search/issues pol)
same "policy: a failed search is UNKNOWN" "$got $(grep 'AI POLICY' "$W/out")" "rc=3 **AI POLICY: UNKNOWN.** No rule turned up, but the failed lookups above could hold one. Rerun policy.sh, and read any source that fails twice by hand. Sources checked:"
same "policy: the failed searches are listed" "$(grep -E '^\*\*LOOKUPS FAILED|^- AI comments' "$W/out")" "**LOOKUPS FAILED: 2.** What they would have read is unknown, not absent:
- AI comments: search (ChatGPT OR Copilot OR Claude OR slop): gh: API rate limit exceeded (HTTP 403)
- AI comments: search (LLM OR \"AI-generated\" OR \"AI generated\" OR \"AI-assisted\"): gh: API rate limit exceeded (HTTP 403)"
same "policy: maintainer comments read unknown, not none" "$(grep -A1 '^### Maintainer comments' "$W/out" | tail -1)" "- LOOKUP FAILED: unknown, not none (listed below)"

# --- house.sh --------------------------------------------------------------------------
repo="$W/repo"
git init -q -b main "$repo"
printf '{\n  "packageManager": "pnpm@9.1.0",\n  "scripts": {"lint": "oxlint src"}\n}\n' > "$repo/package.json"
git -C "$repo" add package.json && git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m init
unknown="- package.json doesn't parse as JSON, so what it would say here is unknown, not absent"
(cd "$repo" && bash "$S/house.sh" > "$W/out" 2> "$W/err")
same "house: a valid package.json lists its scripts" "$(grep -c -F -e "$unknown" "$W/out") $(grep -F 'npm script `lint`' "$W/out") $(grep -F 'packageManager' "$W/out")" "0 - npm script \`lint\`: \`oxlint src\` - packageManager: pnpm@9.1.0"
printf '<<<<<<< HEAD\n' | cat - "$repo/package.json" > "$W/p" && mv "$W/p" "$repo/package.json"
(cd "$repo" && bash "$S/house.sh" > "$W/out" 2> "$W/err")
same "house: an unparseable package.json reads unknown" "$(grep -c -F -e "$unknown" "$W/out") $(grep -c -F 'npm script' "$W/out")" "2 0"
same "house: and says so on stderr" "$(cat "$W/err")" "house.sh: package.json doesn't parse as JSON; its scripts, packageManager, and engines are left out"

echo "$cases cases, $failed failed"
[ "$failed" -eq 0 ]
