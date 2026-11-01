#!/usr/bin/env bash
# SessionStart: on a branch with an oss-pr ledger, print which phase runs next (scripts/next.sh),
# so a resumed session starts where the ledger says. Prints nothing anywhere else; never blocks.

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
branch=$(git branch --show-current)
[ -n "$branch" ] && [ -d "$dir/houseguest/$branch" ] || exit 0
echo "houseguest: this branch has an oss-pr ledger at $dir/houseguest/$branch."
bash "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/skills/oss-pr/scripts/next.sh" "$dir/houseguest/$branch"
exit 0
