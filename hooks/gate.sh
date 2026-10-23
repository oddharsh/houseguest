#!/usr/bin/env bash
# PreToolUse gate for `gh pr create` on repos you don't own.
#
# Blocks (exit 2) until the oss-pr ledger shows recon said GO, the blind intent
# check found no deliberate choice in the way, a style note exists, and a proof
# and the final check both passed on the current HEAD. Stays silent everywhere else: other commands,
# repos that aren't forks, and your own repos.
# A user who explicitly wants to skip can prefix the command with HOUSEGUEST_SKIP=1.

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

# A security report recon marked PRIVATE also blocks public issues and pushes.
private_only=""
if printf '%s' "$cmd" | grep -q -E '(^|[;&|[:space:]])(gh[[:space:]]+issue[[:space:]]+create|git[[:space:]]+push)([[:space:]]|$)'; then
  private_only=1
else
  printf '%s' "$cmd" | grep -q -E '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0
fi
printf '%s' "$cmd" | grep -q 'HOUSEGUEST_SKIP=1' && exit 0

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

if [ -n "$private_only" ]; then
  grep -q -E '^DECISION:[[:space:]]*PRIVATE' "$(git rev-parse --git-dir)/houseguest/$(git branch --show-current)/recon.md" 2>/dev/null || exit 0
  # The advisory's temporary private fork (<repo>-ghsa-xxxx-xxxx-xxxx) is where the fix belongs.
  for w in $(printf '%s' "$cmd" | sed -E 's/.*git[[:space:]]+push//'); do
    case "$w" in -*) continue ;; esac
    url=$(git remote get-url "$w" 2>/dev/null || printf '%s' "$w")
    printf '%s' "$url" | grep -q -E -- '-ghsa(-[a-z0-9]{4}){3}' && exit 0
  done
  cat >&2 <<EOF
houseguest blocked this: recon.md says this is a security vulnerability (DECISION: PRIVATE).
Nothing about it goes public until the maintainers publish an advisory: report it through the
channel in SECURITY.md, and push a fix only to the advisory's private fork (its name ends in
-ghsa-...). If the user explicitly says to go ahead, rerun the command prefixed with HOUSEGUEST_SKIP=1.
EOF
  exit 2
fi

# Only gate contributions upstream: a fork, or a clone with an `upstream` remote.
if ! git remote get-url upstream >/dev/null 2>&1; then
  [ "$(gh repo view --json isFork -q .isFork 2>/dev/null)" = "true" ] || exit 0
fi

branch=$(git branch --show-current)
ledger="$(git rev-parse --git-dir)/houseguest/$branch"
head=$(git rev-parse HEAD)
problems=""
add() { problems="${problems}  - $1
"; }

if [ ! -f "$ledger/recon.md" ]; then
  add "recon.md missing: run oss-pr phase 1 (recon)"
else
  decision=$(grep -m1 -E '^DECISION:' "$ledger/recon.md" | sed 's/^DECISION:[[:space:]]*//')
  case "$decision" in
    GO*) ;;
    DOCS*) grep -q -E '^VERDICT:[[:space:]]*INTENDED' "$ledger/intent.md" 2>/dev/null || add "recon decided DOCS, but intent.md doesn't say the behavior is INTENDED: a docs change needs the intent check's citation behind it" ;;
    JOIN*) [ -f "$ledger/pr-defaults.md" ] || add "recon decided JOIN but pr-defaults.md is missing: run prdefaults.sh on the PR you're adding to and follow references/existing-pr.md" ;;
    "") add "recon.md has no DECISION: line" ;;
    *) add "recon decided $decision: $(grep -m1 -E '^Reason:' "$ledger/recon.md" | sed 's/^Reason:[[:space:]]*//')" ;;
  esac
fi

if [ -f "$ledger/recon.md" ]; then
  pol=$(grep -m1 -E '^- AI policy:' "$ledger/recon.md" | sed 's/^- AI policy:[[:space:]]*//')
  case "$pol" in
    ""|"<"*) add "recon.md has no AI policy verdict: run policy.sh (gather.sh runs it) and record what it found" ;;
  esac
fi

if [ -f "$ledger/recon.md" ]; then
  rep=$(grep -m1 -E '^- Reproduces on:' "$ledger/recon.md" | sed 's/^- Reproduces on:[[:space:]]*//')
  case "$rep" in
    ""|"<"*|*"not yet checked"*) add "recon.md doesn't say where the bug reproduces: run channels.sh, reproduce on prod and each build it marks DIFFERS, and record the results (or \"n/a: not a bug fix\")" ;;
    *BLOCKED:*) add "recon's reproduction is blocked by the setup ($(printf '%s' "$rep" | sed 's/.*BLOCKED:[[:space:]]*//' | cut -c1-160)): fix the environment and reproduce, since a broken setup says nothing about the bug" ;;
    *"<yes/no>"*|*"<reproduces?"*) add "recon.md's Reproduces on line still has unfilled results: reproduce on each listed build and replace every <yes/no>" ;;
  esac
fi

# The blind intent check. JOIN skips it: the PR being joined already has the maintainers' attention.
case "$decision" in
  GO*)
    if [ ! -f "$ledger/intent.md" ]; then
      add "intent.md missing: run the intent check (oss-pr phase 0) in its own subagent, or write VERDICT: N/A (<reason>) when the change alters no existing behavior"
    else
      verdict=$(grep -m1 -E '^VERDICT:' "$ledger/intent.md" | sed 's/^VERDICT:[[:space:]]*//')
      ferr=$(grep -m1 -E '^- Factual error:' "$ledger/intent.md" | sed 's/^- Factual error:[[:space:]]*//')
      case "$verdict" in
        ""|"<"*|*"|"*) add "intent.md has no filled-in VERDICT: line" ;;
        INTENDED*)
          case "$ferr" in
            ""|"<"*|none*|None*) add "the intent check found this behavior intended ($(grep -m1 -E '^Basis:' "$ledger/intent.md" | sed 's/^Basis:[[:space:]]*//' | cut -c1-200)), and names no factual error behind it: recon should ASK the maintainers first" ;;
          esac ;;
        CONFLICTING*) add "the intent check found conflicting sources on whether this behavior is intended: recon should ASK the maintainers first" ;;
      esac
    fi ;;
esac

[ -f "$ledger/style.md" ] || add "style.md missing: run oss-pr phase 2 (style fingerprint)"

if [ ! -f "$ledger/house.md" ]; then
  add "house.md missing: run housecheck.sh to check the diff against the repo's house rules"
else
  hstat=$(grep -m1 -E '^STATUS:' "$ledger/house.md" | sed 's/^STATUS:[[:space:]]*//')
  hsha=$(grep -m1 -E '^SHA:' "$ledger/house.md" | sed 's/^SHA:[[:space:]]*//')
  case "$hstat" in PASS*) ;; *) add "house rules check is '${hstat:-missing}': fix the FAILs, run the missing tools, and fix or acknowledge each flag" ;; esac
  [ "$hsha" = "$head" ] || add "house.md is for ${hsha:-no sha}, but HEAD is $head; rerun housecheck.sh"
fi

if [ ! -f "$ledger/proof.md" ]; then
  add "proof.md missing: run oss-pr phase 4 (prove.sh), or write STATUS: N/A for docs-only changes"
else
  status=$(grep -m1 -E '^STATUS:' "$ledger/proof.md" | sed 's/^STATUS:[[:space:]]*//')
  sha=$(grep -m1 -E '^SHA:' "$ledger/proof.md" | sed 's/^SHA:[[:space:]]*//')
  case "$status" in
    PASS*|N/A*) ;;
    *) add "proof status is '${status:-missing}'" ;;
  esac
  [ "$sha" = "$head" ] || add "proof.md is for ${sha:-no sha}, but HEAD is $head; rerun the proof on the current commit"
fi

# The final check: the problems the PR poses, reproduced as posed, on this HEAD.
if [ ! -f "$ledger/final.md" ]; then
  add "final.md missing: run the final check (oss-pr phase 7) on this commit, after review"
else
  fstat=$(grep -m1 -E '^STATUS:' "$ledger/final.md" | sed 's/^STATUS:[[:space:]]*//')
  fsha=$(grep -m1 -E '^SHA:' "$ledger/final.md" | sed 's/^SHA:[[:space:]]*//')
  case "$fstat" in
    PASS*) ;;
    *) add "final check is '${fstat:-missing}': the PR doesn't yet show it solves every problem it poses (see $ledger/final.md)" ;;
  esac
  [ "$fsha" = "$head" ] || add "final.md is for ${fsha:-no sha}, but HEAD is $head; rerun the final check"
fi

# The title, when one is passed: recheck it against the repo's title conventions.
ttl=$(printf '%s' "$cmd" | sed -n -E "s/.*(--title|-t)[ =]+\"([^\"]*)\".*/\2/p; s/.*(--title|-t)[ =]+'([^']*)'.*/\2/p" | head -1)
[ -z "$ttl" ] && [ -f "$ledger/pr-title.txt" ] && printf '%s' "$cmd" | grep -q 'pr-title.txt' && ttl=$(head -1 "$ledger/pr-title.txt")
if [ -n "$ttl" ] && [ -f "$ledger/titles.json" ] && [ ! -s "$ledger/title-ack.md" ]; then
  tout=$(bash "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/skills/oss-pr/scripts/title.sh" --stats "$ledger/titles.json" "$ttl" 2>/dev/null)
  if [ $? -ne 0 ]; then add "title doesn't match the repo's title conventions: $(echo "$tout" | sed -n '/^FLAG/,$p' | grep '^  - ' | sed 's/^  - //' | tr '\n' ';' | cut -c1-240). Rewrite it, or explain in title-ack.md why it's right"; fi
elif [ -n "$ttl" ] && [ ! -f "$ledger/titles.json" ]; then
  add "title not checked: run title.sh --save \"$ledger/titles.json\" first (see pr-copy.md)"
fi

[ -z "$problems" ] && exit 0

cat >&2 <<EOF
houseguest blocked this PR. The oss-pr ledger at $ledger isn't complete:
$problems
Finish the missing phases with the oss-pr skill. If the user explicitly says to skip
the checks for this PR, rerun the same command prefixed with HOUSEGUEST_SKIP=1.
EOF
exit 2
