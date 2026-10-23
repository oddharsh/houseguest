#!/usr/bin/env bash
# Will reviewers get a preview build of this PR, and what do they see when they don't?
#
#   preview.sh --repo owner/name [--files a,b] [--as-of DATE] [--save FILE]
#
# Run from the clone. Reports:
#   - preview pipelines the repo runs on PRs: workflows that deploy or publish per PR
#     (Vercel, Netlify, Cloudflare Pages, Firebase, Surge, Chromatic, pkg.pr.new, uploaded
#     build artifacts), and host config files (vercel.json, netlify.toml, .readthedocs.yaml),
#     with any step that skips fork PRs;
#   - what recent merged PRs actually got: a preview link from a GitHub App's comment (never a
#     person's, since anyone can paste a link) or a check, on
#     fork PRs and branch PRs separately, and fork PRs that waited on a maintainer to
#     authorize the build;
#   - how often outside contributors' merged PRs carried screenshots or recordings, overall
#     and among those touching UI files.
# Ends with one verdict: FORKS GET ONE, BRANCHES ONLY, or NONE FOUND.
# --files: the paths you're changing, to say whether the change is visible in a UI.
# --save writes the same report to FILE (the ledger's preview.md).

set -uo pipefail
repo="" files="" asof="" save=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --files) files="$2"; shift 2 ;;
    --as-of) asof="$2"; shift 2 ;;
    --save) save="$2"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "preview.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { echo "preview.sh: --repo is required" >&2; exit 2; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "preview.sh: run it from the clone" >&2; exit 2; }

# Hosts and services that turn a PR into something a reviewer can open.
HOSTS='vercel\.app|netlify\.app|pages\.dev|workers\.dev|pkg\.pr\.new|surge\.sh|web\.app|firebaseapp\.com|readthedocs\.build|onrender\.com|chromatic\.com|up\.railway\.app|fly\.dev|expo\.dev|stackblitz\.com|codesandbox\.io'
STEPS='pkg-pr-new|pkg\.pr\.new|continuous-release|vercel|netlify|cloudflare/pages-action|wrangler(-action)?.*(pages deploy|versions upload|preview)|surge|action-hosting-deploy|chromatic|pr-preview-action|surge-preview|eas (update|build)|expo-github-action|fly(ctl)? deploy|actions/upload-artifact'
UI='\.(css|scss|sass|less|styl|html?|vue|svelte|tsx|jsx|astro|mdx|swift|kt|xib|storyboard|qml|ui)$|(^|/)(components?|ui|views?|pages|styles|themes?|templates|layouts?)/'

report() {
echo "# Preview: $repo"
echo
echo "## Preview pipelines in the repo"
found=0
for f in "$root"/.github/workflows/*.y*ml; do
  [ -f "$f" ] || continue
  grep -q -E '^[[:space:]]*(pull_request|pull_request_target|workflow_run)[[:space:]]*:|on:.*(pull_request|workflow_run)|^[[:space:]]*-[[:space:]]*(pull_request|pull_request_target|workflow_run)[[:space:]]*$' "$f" || continue
  hits=$(grep -o -i -E "$STEPS" "$f" | tr 'A-Z' 'a-z' | sort -u | tr '\n' ' ')
  [ -n "$hits" ] || continue
  found=1
  rel=${f#"$root"/}
  trig=$(grep -o -E 'pull_request_target|workflow_run|pull_request' "$f" | sort -u | tr '\n' ' ')
  echo "- $rel: ${hits% } (on: ${trig% })"
  if grep -q -E 'head\.repo\.full_name *== *github\.repository|github\.repository *== *github\.event\.pull_request\.head\.repo\.full_name|head\.repo\.fork *== *false|!github\.event\.pull_request\.head\.repo\.fork' "$f"; then
    echo "  - skips fork PRs: $(grep -n -m1 -E 'head\.repo\.full_name|head\.repo\.fork' "$f" | sed 's/^\([0-9]*\):[[:space:]]*/line \1: /' | cut -c1-140)"
  elif ! printf '%s' "$trig" | grep -q -E 'pull_request_target|workflow_run' && grep -q -E 'secrets\.' "$f"; then
    echo "  - runs on pull_request and uses secrets, which fork PRs don't get: the deploy step likely fails or skips on yours"
  fi
  printf '%s' "$hits" | grep -q 'upload-artifact' && echo "  - uploads build artifacts: reviewers can download them from the run's summary page"
done
for c in vercel.json netlify.toml .readthedocs.yaml .readthedocs.yml render.yaml app.json chromatic.config.json; do
  [ -f "$root/$c" ] && { found=1; echo "- $c (the host's GitHub app may build previews without a workflow)"; }
done
[ "$found" = 1 ] || echo "- none in .github/workflows or host config files"

q="repo:$repo is:pr is:merged sort:created-desc"
[ -n "$asof" ] && { case "$asof" in *T*) q="$q merged:<$asof" ;; *) q="$q merged:<${asof}T00:00:00Z" ;; esac; }
prs=$(gh api graphql -f q="$q" -f query='
query($q:String!){search(query:$q,type:ISSUE,first:40){nodes{... on PullRequest{
  number url isCrossRepository authorAssociation author{login} body
  files(first:60){nodes{path}}
  comments(first:30){nodes{author{login __typename} body}}
  commits(last:1){nodes{commit{statusCheckRollup{contexts(first:50){nodes{
    ... on CheckRun{name detailsUrl} ... on StatusContext{context targetUrl}}}}}}}
}}}}' --jq '.data.search.nodes' 2>/dev/null)
[ -n "$prs" ] && [ "$prs" != null ] || { echo; echo "preview.sh: couldn't read merged PRs for $repo" >&2; return 2; }

rows=$(echo "$prs" | jq --arg H "$HOSTS" --arg UI "$UI" '
  [.[] | select((.author.login // "") | test("\\[bot\\]$|dependabot|renovate|github-actions"; "i") | not)
   | ([.comments.nodes[] | select(.author.__typename == "Bot")]) as $bc
   | ([$bc[].body | scan("https?://[^\\s)\\]\"<>]*(?:" + $H + ")[^\\s)\\]\"<>]*")]) as $curls
   | ([.commits.nodes[].commit.statusCheckRollup.contexts.nodes[]? | select(((.name // .context) // "") | test("preview|deploy|vercel|netlify|pages|readthedocs|chromatic|pkg"; "i")) | (.detailsUrl // .targetUrl // empty) | select(test($H))]) as $surls
   | { number, url, fork: .isCrossRepository,
       outside: (.authorAssociation | test("OWNER|MEMBER|COLLABORATOR") | not),
       link: (($curls + $surls) | first // null),
       authorize: ([$bc[].body | select(test("authoriz|needs approval|approve.*deploy|requires? (a )?(team )?member"; "i"))] | length > 0),
       ui: ([.files.nodes[].path | select(test($UI; "i"))] | length > 0),
       shot: ((.body // "") | test("!\\[[^\\]]*\\]\\(|<img |<video |user-attachments/assets|\\.(png|jpe?g|gif|webp|mp4|mov)\\b"; "i")) }]')

echo
echo "## What the last $(echo "$rows" | jq length) merged human PRs got"
echo "$rows" | jq -r '
  def share(f): "\([.[] | select(f)] | length) of \(length)";
  ([.[] | select(.fork)]) as $f | ([.[] | select(.fork | not)]) as $b
  | "- Fork PRs with a preview link: \($f | share(.link != null))",
    "- Branch PRs with a preview link: \($b | share(.link != null))",
    "- Fork PRs where a bot waited on a maintainer to authorize the build: \($f | share(.authorize))",
    ([$f[] | select(.link != null)][:3][] | "  - #\(.number): \(.link)"),
    ([$b[] | select(.link != null)][:2][] | "  - #\(.number) (branch): \(.link)")'

echo
echo "## Screenshots and recordings in outside contributors' PRs"
echo "$rows" | jq -r '
  [.[] | select(.outside)] as $o | [$o[] | select(.ui)] as $u
  | "- All outside PRs: \([$o[] | select(.shot)] | length) of \($o | length) carried one",
    "- Outside PRs touching UI files: \([$u[] | select(.shot)] | length) of \($u | length) carried one",
    ([$u[] | select(.shot)][:3][] | "  - \(.url)")'
if [ -n "$files" ]; then
  uif=$(printf '%s' "$files" | tr ',' '\n' | grep -i -E "$UI" | head -5 | paste -sd ' ' -)
  echo "- Your change touches UI files: ${uif:-none}"
fi

echo
echo "$rows" | jq -r --argjson pipes "$found" '
  [.[] | select(.fork)] as $f | [.[] | select(.fork | not)] as $b
  | if ([$f[] | select(.link != null)] | length) > 0 then
      "VERDICT: FORKS GET ONE. A preview link should appear on your PR without anything from you. Check it builds your HEAD, and tell reviewers where to look."
    elif ([$b[] | select(.link != null)] | length) > 0 or ([$f[] | select(.authorize)] | length) > 0 or $pipes == 1 then
      "VERDICT: BRANCHES ONLY. The repo builds previews, but not on its own for fork PRs" + (if ($f | length) == 0 then " (no fork PR in this sample, so that part is unmeasured)" else "" end) + ". A maintainer may authorize one; don'"'"'t ask in the body, and don'"'"'t host your own. Show the change in the PR instead."
    else
      "VERDICT: NONE FOUND. No preview pipeline and no preview links on recent PRs. Show the change in the PR itself if reviewers would need to see it."
    end'
}

if [ -n "$save" ]; then report | tee "$save"; exit "${PIPESTATUS[0]}"; else report; fi
