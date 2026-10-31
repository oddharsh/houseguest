#!/usr/bin/env bash
# Score agents/maintainer-review.md against past PRs whose outcome we know.
#
#   run.sh prep   <out-dir> [corpus.jsonl...]   rebuild each PR offline
#   run.sh review <out-dir> [--model M] [--jobs N]
#   run.sh verify <out-dir> [--model M] [--jobs N]
#   run.sh judge  <out-dir> [--model M] [--jobs N]
#   run.sh score  <out-dir>
#   run.sh all    <out-dir> [--model M] [--jobs N]
#   run.sh archive <out-dir> <dest-dir>         copy cases and scores, not clones
#
# Corpora default to recall.jsonl and noise.jsonl beside this script. Each
# stage skips cases whose output already exists, so a rerun after a prompt
# change only needs `rm <out-dir>/*/{review.md,checks.json,judge.json}` first.
#
# prep: for each PR, a fresh git repo at the merge base (50 commits of history,
#   no remote), with the PR's final tree as one commit on top, plus the body,
#   the diff, and policy.sh's view of CONTRIBUTING and the AI policy as of the
#   moment the PR opened. Nothing the reviewer gets was written after that.
# review: the agent body as the system prompt, prompt.md as the task, run with
#   `claude -p` in the case's repo. No WebFetch and no gh or curl: a reviewer
#   that can reach GitHub can read how the PR ended.
# verify: list the review's Important findings, then run agents/finding-check.md
#   on each one alone, in the case's repo and as offline as the review. The
#   verdicts go in checks.json; the judge drops what they refute, as the skill
#   keeps a refuted finding from starting a round.
# judge: a second model splits the review into findings, marks each blocking or
#   nit, and for the recall set says whether one names the maintainer's reason.
# score: recall (hits / recall cases) and noise (clean PRs with a blocking
#   finding, and blocking findings per clean PR), as a table and scores.json.
#
# review, verify, and judge need a logged-in `claude` CLI (`claude auth
# status`). A session that can't run one can do those steps itself: write
# review.md from prompt.md and system.md; checks.json as {checker_prompt,
# checks: [{finding, verdict, evidence}]} from agents/finding-check.md, one
# check per Important finding; and judge.json from judge-prompt.md and
# judge.md, in each case directory. score doesn't care who wrote them.

set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
plugin=$(cd "$here/../.." && pwd)
cmd="${1:?usage: run.sh <prep|review|verify|judge|score|all|archive> <out-dir> ...}"
out="${2:?usage: run.sh $cmd <out-dir> ...}"
shift 2
model="" jobs=4 corpora=()
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    *) corpora+=("$1"); shift ;;
  esac
done
[ ${#corpora[@]} -eq 0 ] && corpora=("$here/recall.jsonl" "$here/noise.jsonl")
mkdir -p "$out"; out=$(cd "$out" && pwd)

# --- prep ---------------------------------------------------------------------
prep_one() {  # prep_one <set> <json row>
  local set="$1" row="$2" url repo n dir
  url=$(jq -r .url <<<"$row")
  repo=$(sed -E 's#https://github.com/([^/]+/[^/]+)/pull/.*#\1#' <<<"$url")
  n=${url##*/}
  dir="$out/$(tr / _ <<<"$repo")_$n"
  [ -f "$dir/prompt.md" ] && { echo "prep: $repo#$n (cached)"; return; }
  rm -rf "$dir"; mkdir -p "$dir"

  local pr base head created mb
  pr=$(gh api "repos/$repo/pulls/$n") || { echo "prep: $repo#$n: PR lookup failed" >&2; return 1; }
  base=$(jq -r .base.sha <<<"$pr"); head=$(jq -r .head.sha <<<"$pr"); created=$(jq -r .created_at <<<"$pr")
  # The merge base, not the base tip: it's what GitHub diffs a PR against.
  mb=$(gh api "repos/$repo/compare/$base...$head" --jq .merge_base_commit.sha 2>/dev/null)
  [ -z "$mb" ] && mb="$base"

  local ws="$dir/repo" login
  login=$(jq -r .user.login <<<"$pr")
  g() { git -C "$ws" -c commit.gpgsign=false -c user.name="$login" -c user.email="$login@users.noreply.github.com" "$@"; }
  git init -q "$ws"
  g remote add origin "https://github.com/$repo"
  { g fetch -q --depth=50 origin "$mb" \
    && { g fetch -q --depth=1 origin "$head" 2>/dev/null || g fetch -q --depth=1 origin "refs/pull/$n/head"; } \
    && g checkout -q --detach "$mb" \
    && g update-ref refs/tags/base "$mb" \
    && g checkout -q -b pr \
    && g read-tree -u --reset "$head" \
    && g commit -q --allow-empty -m "$(g log -1 --format=%B "$head")"; } \
    || { echo "prep: $repo#$n: couldn't rebuild the PR" >&2; rm -rf "$dir"; return 1; }
  # HEAD is now one commit holding the PR's final tree, with the head commit's
  # message, so the reviewer sees what the contributor wrote and none of the
  # PR's later history. Without the remote it can't fetch what came after.
  g remote remove origin
  rm -f "$ws/.git/FETCH_HEAD"

  g diff base...HEAD > "$dir/diff.patch"
  # Maintainers retitle PRs they close ("AI junk", "[rejected AI] ..."), which
  # hands the reviewer the verdict. Use the title the PR opened with. Body edits
  # are rarer; ones by anyone but the author get flagged in case.json.
  local title edits
  title=$(gh api graphql -F n="$n" -f o="${repo%/*}" -f r="${repo#*/}" -f query='
    query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
      timelineItems(itemTypes:[RENAMED_TITLE_EVENT],first:1){nodes{... on RenamedTitleEvent{previousTitle}}}
      userContentEdits(first:20){nodes{editor{login}}}}}}' \
    --jq '.data.repository.pullRequest | [.timelineItems.nodes[0].previousTitle // null,
      ([.userContentEdits.nodes[].editor.login | select(. != null)] | unique)] | @json' 2>/dev/null)
  edits=$(jq -c --arg a "$login" '.[1] - [$a]' <<<"${title:-[null,[]]}")
  title=$(jq -r '.[0] // empty' <<<"${title:-[null,[]]}")
  [ -z "$title" ] && title=$(jq -r .title <<<"$pr")
  { echo "# $title"; echo; jq -r '.body // ""' <<<"$pr"; } > "$dir/pr-body.md"
  bash "$plugin/skills/oss-pr/scripts/policy.sh" --repo "$repo" --as-of "$created" --keep "$dir/docs" \
    > "$dir/policy.md" 2>/dev/null

  # The reviewer prompt under test, frontmatter stripped. Its hash goes in
  # case.json so scores from different prompt versions don't get mixed up.
  awk 'f >= 2; /^---$/ { f++ }' "$plugin/agents/maintainer-review.md" > "$dir/system.md"
  jq -n --arg set "$set" --arg repo "$repo" --argjson n "$n" --arg url "$url" --arg mb "$mb" \
    --arg head "$head" --arg created "$created" --argjson row "$row" \
    --arg prompt "$(git hash-object "$dir/system.md" | cut -c1-12)" --arg title "$title" \
    --argjson edits "${edits:-[]}" \
    '{set: $set, repo: $repo, number: $n, url: $url, merge_base: $mb, head: $head, created: $created,
      title: $title, body_edited_by_others: $edits, reviewer_prompt: $prompt} + $row' > "$dir/case.json"
  cat > "$dir/prompt.md" <<EOF
Review this pull request to $repo.

- The repo: \`$ws\`, a clone at the PR's base with the PR applied. HEAD is the PR; the tag \`base\` is the base it branched from. The diff is \`git diff base...HEAD\`, also saved at \`$dir/diff.patch\`.
- The drafted body: \`$dir/pr-body.md\` (title on the first line).
- CONTRIBUTING and any AI policy: read them in the repo, and \`$dir/policy.md\` lists every contribution and AI policy source as of the moment the PR opened, with copies under \`$dir/docs\`.
- The ledger: none. This PR wasn't drafted with houseguest, so there's no intent.md, recon.md, or proof. Judge the claims in the body against the code and the repo.
- The lean ladder: \`$plugin/skills/oss-pr/references/lean.md\`.

This review runs offline, on a PR from the past. Don't use the network: no WebFetch, gh, curl, or git fetch. Anything on GitHub from after the PR opened would tell you how it ended.
EOF
  echo "prep: $repo#$n ($set) at ${mb:0:10}"
}

prep() {
  local c set
  for c in "${corpora[@]}"; do
    case "$(basename "$c")" in recall*) set=recall ;; noise*) set=noise ;; *) set=$(basename "$c" .jsonl) ;; esac
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      prep_one "$set" "$row"
    done < "$c"
  done
}

# --- review and judge ---------------------------------------------------------
need_claude() {
  claude auth status 2>/dev/null | jq -e .loggedIn >/dev/null && return
  echo "run.sh: the claude CLI isn't logged in (claude auth status). Log in, or write review.md and judge.json yourself (see the header)." >&2
  exit 1
}

review_one() {  # review_one <case dir>
  local dir="$1" res
  [ -s "$dir/review.md" ] && return
  # Read-only git and file tools inside the case; no network.
  res=$(cd "$dir/repo" && claude -p "$(cat "$dir/prompt.md")" \
    --system-prompt "$(cat "$dir/system.md")" ${model:+--model "$model"} \
    --tools "Read,Grep,Glob,Bash" --permission-mode dontAsk \
    --allowedTools "Read" "Grep" "Glob" "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)" \
      "Bash(git blame:*)" "Bash(git grep:*)" "Bash(git ls-files:*)" "Bash(ls:*)" "Bash(wc:*)" \
    --add-dir "$dir" "$plugin/skills/oss-pr/references" \
    --output-format json --no-session-persistence 2>/dev/null)
  if jq -e '.is_error == false' <<<"$res" >/dev/null 2>&1; then
    jq -r .result <<<"$res" > "$dir/review.md"
    jq '{runner: "claude -p", cost_usd: .total_cost_usd, models: (.modelUsage | keys), turns: .num_turns}' <<<"$res" > "$dir/review.meta.json"
    echo "review: $(basename "$dir")"
  else
    echo "review: $(basename "$dir") failed: $(jq -r '.result // "no output"' <<<"$res" 2>/dev/null | head -c 200)" >&2
  fi
}

FINDINGS_SCHEMA='{"type":"object","required":["important"],"properties":{
  "important":{"type":"array","items":{"type":"string"}}}}'
CHECK_SCHEMA='{"type":"object","required":["verdict","evidence"],"properties":{
  "verdict":{"enum":["CONFIRMED","REFUTED","PRE-EXISTING","UNSURE"]},"evidence":{"type":"string"}}}'

verify_one() {  # verify_one <case dir>: one finding check per Important finding
  local dir="$1" repo list finding res checks="[]"
  [ -s "$dir/review.md" ] || return
  [ -s "$dir/checks.json" ] && return
  repo=$(jq -r .repo "$dir/case.json")
  list=$(claude -p "Copy out every finding this review tags Important, each verbatim with its instances and evidence, in the order it gives them. Leave out Nits, Pre-existing findings, and lean notes.

<review>
$(cat "$dir/review.md")
</review>" ${model:+--model "$model"} --tools "" --json-schema "$FINDINGS_SCHEMA" \
    --output-format json --no-session-persistence 2>/dev/null)
  jq -e '.structured_output.important' <<<"$list" >/dev/null 2>&1 \
    || { echo "verify: $(basename "$dir") couldn't list its findings" >&2; return; }
  # Written here rather than at prep, so a cached prep still checks with the current prompt.
  awk 'f >= 2; /^---$/ { f++ }' "$plugin/agents/finding-check.md" > "$dir/check-system.md"
  while IFS= read -r finding; do
    res=$(cd "$dir/repo" && claude -p "Check this finding from a review of a pull request to $repo.

- The repo: \`$dir/repo\`, a clone at the PR's base with the PR applied. HEAD is the PR; the tag \`base\` is the base it branched from.
- The title and body: \`$dir/pr-body.md\` (title on the first line).
- CONTRIBUTING and any AI policy as of the moment the PR opened: \`$dir/policy.md\`, with copies under \`$dir/docs\`.
- The finding, verbatim:

<finding>
$(jq -r . <<<"$finding")
</finding>

This check runs offline, on a PR from the past. You can read files and run read-only git commands, nothing else: where you'd run the input, read the code path and say you didn't run it." \
      --system-prompt "$(cat "$dir/check-system.md")" ${model:+--model "$model"} \
      --tools "Read,Grep,Glob,Bash" --permission-mode dontAsk \
      --allowedTools "Read" "Grep" "Glob" "Bash(git log:*)" "Bash(git show:*)" "Bash(git diff:*)" \
        "Bash(git blame:*)" "Bash(git grep:*)" "Bash(git ls-files:*)" "Bash(ls:*)" "Bash(wc:*)" \
      --add-dir "$dir" --json-schema "$CHECK_SCHEMA" --output-format json --no-session-persistence 2>/dev/null)
    jq -e '.structured_output.verdict' <<<"$res" >/dev/null 2>&1 \
      || { echo "verify: $(basename "$dir") failed a check" >&2; return; }
    checks=$(jq -c --argjson f "$finding" --argjson c "$(jq -c .structured_output <<<"$res")" '. + [{finding: $f} + $c]' <<<"$checks")
  done < <(jq -c '.structured_output.important[]' <<<"$list")
  jq -n --arg p "$(git hash-object "$dir/check-system.md" | cut -c1-12)" --argjson c "$checks" \
    '{checker_prompt: $p, checks: $c}' > "$dir/checks.json"
  echo "verify: $(basename "$dir") ($(jq '[.checks[] | select(.verdict == "REFUTED")] | length' "$dir/checks.json") refuted of $(jq '.checks | length' "$dir/checks.json"))"
}

JUDGE_SCHEMA='{"type":"object","required":["findings","verdict"],"properties":{
  "findings":{"type":"array","items":{"type":"object","required":["summary","class"],"properties":{
    "summary":{"type":"string"},"class":{"enum":["blocking","nit"]}}}},
  "verdict":{"enum":["close","changes","merge"]},
  "hit":{"type":["boolean","null"]},"hit_rank":{"type":["integer","null"]},"why":{"type":"string"}}}'

judge_prompt() {  # judge_prompt <case dir> -> the grader's task on stdout
  local dir="$1"
  jq -r '"Set: \(.set)\nPR: \(.url)\n" + (if .set == "recall" then
    "\nThe maintainer closed it or asked for changes. Their reason, in one line: \(.expect)\nTheir words: \(.quote)\n" else
    "\nThe maintainers merged it without asking for changes.\n" end)' "$dir/case.json"
  echo; echo "The reviewer's reply, verbatim:"; echo; echo '<review>'; cat "$dir/review.md"; echo '</review>'
  [ -s "$dir/checks.json" ] || return 0
  echo; echo "A second agent then checked each Important finding against the code, one at a time:"; echo
  echo '<checks>'; jq -r '.checks[] | "- \(.verdict): \(.finding[0:300])\n  Evidence: \(.evidence)"' "$dir/checks.json"; echo '</checks>'
}

judge_one() {
  local dir="$1" res
  [ -s "$dir/review.md" ] || return
  [ -s "$dir/judge.json" ] && return
  res=$(cd "$dir" && claude -p "$(cat "$dir/judge-prompt.md")" --system-prompt "$(cat "$here/judge.md")" \
    ${model:+--model "$model"} --tools "" --json-schema "$JUDGE_SCHEMA" \
    --output-format json --no-session-persistence 2>/dev/null)
  if jq -e '.structured_output' <<<"$res" >/dev/null 2>&1; then
    jq '.structured_output' <<<"$res" > "$dir/judge.json"
    echo "judge: $(basename "$dir")"
  else
    echo "judge: $(basename "$dir") failed" >&2
  fi
}

prompts() {  # judge-prompt.md for every reviewed case, whoever runs the judge
  local d
  for d in "$out"/*/; do
    [ -s "$d/review.md" ] && judge_prompt "${d%/}" > "$d/judge-prompt.md"
  done
}

each() {  # each <fn>: run fn over every case dir, $jobs at a time
  local fn="$1" d
  export -f review_one verify_one judge_one judge_prompt; export model plugin here JUDGE_SCHEMA FINDINGS_SCHEMA CHECK_SCHEMA
  for d in "$out"/*/; do [ -f "$d/case.json" ] && echo "${d%/}"; done \
    | xargs -P "$jobs" -I{} bash -c "$fn \"\$1\"" _ {}
}

# --- score --------------------------------------------------------------------
score() {
  local rows
  rows=$(for d in "$out"/*/; do
    [ -f "$d/case.json" ] && [ -f "$d/judge.json" ] || continue
    jq -c --slurpfile j "$d/judge.json" '{set, url, agent, kind} + ($j[0] | {verdict, hit, hit_rank,
      blocking: ([.findings[] | select(.class == "blocking")] | length), nits: ([.findings[] | select(.class == "nit")] | length)})' "$d/case.json"
  done | jq -s .)
  jq '{
    recall: ([.[] | select(.set == "recall")] | {n: length, hits: ([.[] | select(.hit)] | length),
      first_finding: ([.[] | select(.hit_rank == 1)] | length)}),
    noise: ([.[] | select(.set == "noise")] | {n: length,
      flagged: ([.[] | select(.blocking > 0)] | length),
      blocking_per_pr: (if length > 0 then ([.[].blocking] | add) / length else null end),
      would_merge: ([.[] | select(.verdict == "merge")] | length)}),
    cases: .}' <<<"$rows" > "$out/scores.json"
  jq -r '.recall as $r | .noise as $z
    | "Recall: \($r.hits)/\($r.n) maintainer reasons named (\($r.first_finding) as the first finding).",
      "Noise: \($z.flagged)/\($z.n) clean PRs got a blocking finding; \($z.blocking_per_pr // 0 | . * 10 | round / 10) blocking findings per clean PR; \($z.would_merge)/\($z.n) called mergeable.",
      "",
      (.cases[] | "\(.set)\t\(if .set == "recall" then (if .hit then "HIT #\(.hit_rank)" else "MISS" end) else "\(.blocking) blocking" end)\t\(.nits) nits\t\(.verdict)\t\(.url)")' "$out/scores.json"
}

archive() {  # keep what a reader needs to audit a score, without the clones
  local dest="${corpora[0]:?usage: run.sh archive <out-dir> <dest-dir>}" d name
  mkdir -p "$dest"
  for d in "$out"/*/; do
    [ -f "$d/case.json" ] || continue
    name=$(basename "$d"); mkdir -p "$dest/$name"
    cp "$d"/{case.json,review.md,checks.json,judge.json} "$dest/$name/" 2>/dev/null
    [ -f "$d/review.meta.json" ] && cp "$d/review.meta.json" "$dest/$name/"
  done
  cp "$out/scores.json" "$dest/" 2>/dev/null
  echo "archived $(ls -d "$dest"/*/ | wc -l | tr -d ' ') cases to $dest"
}

case "$cmd" in
  prep) prep ;;
  archive) archive ;;
  review) need_claude; each review_one ;;
  verify) need_claude; each verify_one ;;
  judge) prompts; need_claude; each judge_one ;;
  score) score ;;
  all) prep; need_claude; each review_one; each verify_one; prompts; each judge_one; score ;;
  *) echo "run.sh: unknown command $cmd" >&2; exit 1 ;;
esac
