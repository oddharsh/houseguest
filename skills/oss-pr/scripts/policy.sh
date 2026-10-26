#!/usr/bin/env bash
# Find a repo's AI / LLM contribution policy wherever it lives, and say where you looked.
#
#   policy.sh --repo owner/name [--as-of DATE] [--keep DIR]
#
# Policies hide in more places than the repo root. This checks, in order:
#   1. contribution docs at the repo root and in .github
#   2. any file anywhere in the tree whose name says it's a policy or contributing guide
#   3. the owner's .github repo, where GitHub keeps org-wide defaults
#   4. contribution links from README, CONTRIBUTING, and issue/PR templates,
#      followed one level, including into other repos (image-rs keeps its policy
#      in image-rs/organization, linked only from the README)
#   5. maintainer comments on earlier issues and PRs that mention LLM or AI use
# and ends with a verdict line naming every source checked.
#
# --as-of reads every GitHub source at its last commit before that moment.
# Pages outside GitHub can only be read live; the output marks them. They count as a rule
# only when the URL or page title names contribution guidance; otherwise they're mentions.
# --keep DIR leaves the fetched docs in DIR so other checks can grep them.
# Read-only: GET requests only.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

repo="" asof="" keep=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --as-of) asof="$2"; shift 2 ;;
    --keep) keep="$2"; shift 2 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "policy.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { echo "policy.sh: --repo owner/name is required" >&2; exit 2; }
owner="${repo%%/*}"
asof_ts="9999"
if [ -n "$asof" ]; then case "$asof" in *T*) asof_ts="$asof" ;; *) asof_ts="${asof}T00:00:00Z" ;; esac; fi

if [ -n "$keep" ]; then dir="$keep"; mkdir -p "$dir"; else dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT; fi
sources="$dir/.sources"; : > "$sources"; : > "$dir/.guides"

AI_RE='\bLLMs?\b|large language model|AI[- ]?(generated|assisted|assistance|tools?|agents?|policy|use|usage|written|authored)|generative AI|machine[- ]generated|chatgpt|copilot|claude|gemini|\bGPT\b|vibe[- ]cod|slop'
NAME_RE='(^|/)(CONTRIBUTING|CONTRIBUTE|HACKING|DEVELOPMENT|GOVERNANCE|AI_POLICY|AI-POLICY|AGENTS|CLAUDE|TRIAGE)(\.(md|rst|txt|adoc))?$|(^|/)LLMS?[^/]*\.(md|rst|adoc)$|^(\.github/)?README(\.(md|rst|txt|adoc))?$|(^|/)[^/]*(ai|llm|genai)[-_ .]?(policy|policies|usage|use|contribution|contributions|guidelines|rules)[^/]*\.(md|rst|txt|adoc)$|(^|/)[^/]*contribut[^/]*\.(md|rst|txt|adoc)$|^\.github/(PULL_REQUEST_TEMPLATE|ISSUE_TEMPLATE|DISCUSSION_TEMPLATE)|pull_request_template'
GUIDE_RE='contribut|polic(y|ies)|guideline|governance|code[-_ ]of[-_ ]conduct|hacking|developer[-_ ]guide|(ai|llm)[-_ ]?(use|usage|rules)'
SKIP_RE='(^|/)(node_modules|vendor|third_party|tests?|fixtures?|\.agents|\.claude|\.cursor|skills|examples?)/'

ref_of() {  # ref_of owner/repo -> last commit sha before the as-of moment
  local u="repos/$1/commits?per_page=1"
  [ "$asof_ts" != "9999" ] && u="$u&until=$asof_ts"
  gh api "$u" --jq '.[0].sha' 2>/dev/null
}
fetch() {  # fetch owner/repo ref path label
  local dest="$dir/$1/$3"
  [ -s "$dest" ] && return 0
  mkdir -p "$(dirname "$dest")"
  if gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/$3?ref=$2" > "$dest" 2>/dev/null && [ -s "$dest" ]; then
    printf '%s\t%s\t%s\n' "$1/$3" "${2:0:10}" "$4" >> "$sources"
  else
    rm -f "$dest"
  fi
}
fetch_one() {  # fetch_one owner/repo ref path: download only, no source record
  local dest="$dir/$1/$3"
  mkdir -p "$(dirname "$dest")"
  { gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/$3?ref=$2" > "$dest" 2>/dev/null && [ -s "$dest" ]; } || rm -f "$dest"
}
fetch_many() {  # fetch_many owner/repo ref label < paths: download in parallel, record sources in input order
  local p todo
  todo=$(while IFS= read -r p; do [ -n "$p" ] && [ ! -s "$dir/$1/$p" ] && echo "$p"; done)
  [ -z "$todo" ] && return 0
  echo "$todo" | pmap 8 fetch_one "$1" "$2" > /dev/null
  echo "$todo" | while IFS= read -r p; do
    [ -s "$dir/$1/$p" ] && printf '%s\t%s\t%s\n' "$1/$p" "${2:0:10}" "$3" >> "$sources"
  done
  return 0
}
list_tree() {  # list_tree owner/repo ref -> blob paths (whole tree; notes truncation)
  local out
  out=$(gh api "repos/$1/git/trees/$2?recursive=1" 2>/dev/null) || return 0
  [ "$(echo "$out" | jq -r .truncated)" = "true" ] && echo "TRUNCATED" >&2
  echo "$out" | jq -r '.tree[] | select(.type == "blob") | .path'
}

echo "## AI policy sweep"
echo

# 1 and 2: the repo itself, whole tree.
ref=$(ref_of "$repo")
if [ -z "$ref" ]; then echo "- couldn't read $repo at that moment"; exit 0; fi

# 5 starts now, in the background: it reads issue threads, not the docs below.
enf_thread() {  # enf_thread N -> up to 2 maintainer comments in thread N that apply an AI rule
  gh api "repos/$repo/issues/$1/comments?per_page=100" 2>/dev/null | jq -r --arg t "$asof_ts" --arg re "$AI_RE" --arg enf "$ENF_RE" --arg n "$1" '
    (if type == "array" then .[] else empty end) | select(.created_at < $t) | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR"))
    | select(.user.type != "Bot") | select(.body | test($enf; "i"))
    | "- #\($n) **\(.user.login)** (\(.author_association), \(.created_at[:10])): \(.body | gsub("\\s+"; " ") | .[:300])"' 2>/dev/null | head -2
}
enforcement() {
  local nums="" terms q
  # GitHub search allows at most 5 boolean operators per query, so split the terms.
  for terms in '(LLM OR "AI-generated" OR "AI generated" OR "AI-assisted")' '(ChatGPT OR Copilot OR Claude OR slop)'; do
    q="repo:$repo in:comments $terms"
    [ "$asof_ts" != "9999" ] && q="$q created:<$asof_ts"
    nums="$nums $(gh api -X GET search/issues -f q="$q" -f per_page=10 --jq '.items[].number' 2>/dev/null | grep -E '^[0-9]+$')"
  done
  echo $nums | tr ' ' '\n' | sort -rn | uniq | head -16 | pmap 8 enf_thread  # newest threads first
}
enforcement > "$dir/.enf" 2>/dev/null &
tree=$(list_tree "$repo" "$ref" 2>"$dir/.trunc")
[ -s "$dir/.trunc" ] && echo "- note: $repo's tree is too large to list in full; nested policy files may be missed"
echo "$tree" | grep -iE "$NAME_RE" | grep -v -iE "$SKIP_RE" | head -40 \
  | fetch_many "$repo" "$ref" "repo"

# 3: org-wide defaults in owner/.github.
if [ "$repo" != "$owner/.github" ] && gh api "repos/$owner/.github" --jq .full_name >/dev/null 2>&1; then
  oref=$(ref_of "$owner/.github")
  if [ -n "$oref" ]; then
    list_tree "$owner/.github" "$oref" 2>/dev/null | grep -iE "$NAME_RE|^profile/README\.md$" | head -20 \
      | fetch_many "$owner/.github" "$oref" "org default ($owner/.github)"
  fi
fi

# 4: follow contribution links one level, out of the repo if needed.
links=$( { grep -rhoE 'https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(blob|tree)/[^ )">'"'"'`]+' "$dir" 2>/dev/null
           grep -rhoE 'https?://[^ )">'"'"'`]+' "$dir" 2>/dev/null | grep -iE 'contribut|policy|policies|guideline|\bai\b|llm|code-of-conduct|governance' ; } \
         | sed 's/[.,;:]*$//; s/#.*$//' | grep -v -E '[$]\{|\{\{|%7B' | sort -u | head -25)
follow_link() {  # follow_link url -> source records for what it fetched, on stdout
  local url="$1" sources lrepo lpath lref safe dest
  sources=$(mktemp)
  if echo "$url" | grep -qE '^https?://github\.com/[^/]+/[^/]+/(blob|tree)/'; then
    lrepo=$(echo "$url" | sed -E 's#^https?://github\.com/([^/]+/[^/]+)/(blob|tree)/[^/]+/.*#\1#')
    lpath=$(echo "$url" | sed -E 's#^https?://github\.com/[^/]+/[^/]+/(blob|tree)/[^/]+/##')
    if echo "$lpath" | grep -qiE "$NAME_RE|polic|guideline|\.md$" && echo "$lpath" | grep -qiE '\.(md|rst|txt|adoc)$'; then
      lref=$(ref_of "$lrepo"); [ -n "$lref" ] && fetch "$lrepo" "$lref" "$lpath" "linked from $repo"
    fi
  elif ! echo "$url" | grep -qiE '^https?://([a-z0-9-]+\.)*(github\.com|shields\.io|badge|crates\.io|docs\.rs|npmjs\.com|opensource\.guide|contributor-covenant\.org|choosealicense\.com|creativecommons\.org|semver\.org|keepachangelog\.com|conventionalcommits\.org|opensource\.org|apache\.org/licenses|gnu\.org)'; then
    safe=$(echo "$url" | sed -E 's#^https?://##; s#[^A-Za-z0-9._/-]#_#g')
    dest="$dir/live/$safe.txt"; mkdir -p "$(dirname "$dest")"
    if curl -sL --max-time 10 "$url" > "$dest.html" 2>/dev/null && sed -e 's/<[^>]*>/ /g' "$dest.html" | tr -s ' \t' > "$dest" && [ -s "$dest" ]; then
      printf '%s\t%s\t%s\n' "$url" "live" "linked page outside GitHub (read live, not as of then)" >> "$sources"
      # Product pages talk about AI in words that look like rules ("required", "issues"), so a
      # live page joins the verdict only when its URL or <title> says it's contribution guidance.
      title=$(tr '\n' ' ' < "$dest.html" | grep -oiE '<title[^>]*>[^<]*' | head -1 | sed 's/<[^>]*>//')
      printf '%s\n%s\n' "$url" "$title" | grep -qiE "$GUIDE_RE" && echo "$url" >> "$dir/.guides"
    else rm -f "$dest"; fi
    rm -f "$dest.html"
  fi
  cat "$sources"; rm -f "$sources"
}
echo "$links" | pmap 8 follow_link >> "$sources"

# 5: a contribution doc that points at another repo as a whole ("See the [main repository]
# (https://github.com/libjxl/libjxl)"): that repo's contribution rules govern this one too, so its
# docs get the same sweep, one level deep. READMEs are left out; their links are badges and credits.
uprepos=$(find "$dir/$repo" -type f 2>/dev/null | grep -iE '/(CONTRIBUT|HACKING|DEVELOPMENT|GOVERNANCE)[^/]*$|/\.github/[^/]*TEMPLATE|pull_request_template' \
  | while IFS= read -r f; do grep -oE 'https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?([)>"'"'"' ]|$)' "$f" 2>/dev/null; done \
  | sed -E 's#^https?://github\.com/##; s#[/)>"'"'"' ]+$##; s#\.git$##' \
  | grep -v -i -x -F -e "$repo" -e "$owner/.github" | grep -v -E '^(orgs|sponsors|features|marketplace|apps|settings)/' | sort -u | head -3)
for up in $uprepos; do
  uref=$(ref_of "$up"); [ -n "$uref" ] || continue
  list_tree "$up" "$uref" 2>/dev/null | grep -E '^[^/]+$|^\.github/[^/]+$|^docs?/[^/]+$' | grep -iE "$NAME_RE" | grep -v -iE "$SKIP_RE" | head -15 \
    | fetch_many "$up" "$uref" "upstream repo named in $repo's contribution docs"
done

# Report every source. A mention counts as a rule when rule language sits within a
# line of it; product docs that merely talk about AI stay out of the verdict.
POLICY_RE='\bmust\b|please (uncomment|fill|answer|check|tick|state|disclose|declare|mark|label)|uncomment|REQUIRED|must not|required|requires|disclos|declare|prohibit|forbid|\bban(ned|s)?\b|not (be )?accept|will be closed|be closed|reject|not allowed|allowed|permitted|polic(y|ies)|human[- ]?(written|authored|in the loop|review)|your own words|yourself|label(led)?|in a quote|<details>|responsib|do not (use|submit|open)|don.t (use|submit|open)'
CTX_RE='pull request|\bPRs?\b|\bissues?\b|\bcomments?\b|contribut|submi(t|ssion)|\bpatch(es)?\b|commit message|descriptions?|reviewers?|maintainers?'
rules=0; mentions=0; : > "$dir/.mention_srcs"
while IFS=$'\t' read -r src at why; do
  f="$dir/$src"
  case "$src" in http*) f="$dir/live/$(echo "$src" | sed -E 's#^https?://##; s#[^A-Za-z0-9._/-]#_#g').txt" ;; esac
  [ -f "$f" ] || continue
  lines=$(grep -n -i -E "$AI_RE" "$f" 2>/dev/null | cut -d: -f1 | head -40)
  [ -z "$lines" ] && continue
  case "$src" in http*) grep -qxF "$src" "$dir/.guides" || { mentions=$((mentions + 1)); echo "$src" >> "$dir/.mention_srcs"; continue; } ;; esac
  block=""
  for n in $lines; do
    ctx=$(sed -n "$(( n > 1 ? n - 1 : 1 )),$(( n + 2 ))p" "$f" | tr '\n' ' ' | tr -s ' ')
    if echo "$ctx" | grep -q -i -E "$POLICY_RE" && echo "$ctx" | grep -q -i -E "$CTX_RE"; then block="$block
$n: $(echo "$ctx" | cut -c1-320)"; fi
  done
  if [ -n "$block" ]; then
    rules=$((rules + 1))
    echo "### $src ($why, at $at)"
    echo '```'; echo "$block" | sed '/^$/d' | awk '!seen[$0]++' | head -8; echo '```'
  else
    mentions=$((mentions + 1)); echo "$src" >> "$dir/.mention_srcs"
  fi
done < "$sources"
if [ -s "$dir/.mention_srcs" ]; then
  echo "Mentions without rule language (skim only if the work touches them):"
  sed 's/^/- /' "$dir/.mention_srcs" | head -12
fi
echo "$rules" > "$dir/.found"

# 5: maintainers enforcing an AI policy in earlier threads.
echo
echo "### Maintainer comments on AI or LLM use in earlier issues and PRs"
wait
enf=$(cat "$dir/.enf" 2>/dev/null)
if [ -n "$enf" ]; then echo "$enf" | sed '/^$/d' | head -8; else echo "- none found"; fi

checked=$(cut -f1 "$sources" | sed 's/^/  - /')
echo
if [ "$(cat "$dir/.found")" -gt 0 ]; then
  echo "**AI POLICY: RULE FOUND** in $(cat "$dir/.found") source(s)$([ -n "$enf" ] && echo ", and maintainers have applied one in earlier threads"). Read each passage above in full, quote the binding rule in recon.md, and follow it. Sources checked:"
elif [ -n "$enf" ]; then
  echo "**AI POLICY: NO WRITTEN RULE, BUT MAINTAINERS HAVE PUSHED BACK.** Read the comments above: they are the policy in practice. Treat the strictest one as binding. Sources checked:"
elif [ -s "$dir/.mention_srcs" ]; then
  echo "**AI POLICY: MENTIONS ONLY.** AI comes up, but nothing reads as a contribution rule. Say so in recon.md. Sources checked:"
else
  echo "**AI POLICY: NONE FOUND.** Sources checked:"
fi
if [ -n "$checked" ]; then echo "$checked"; else echo "  - (no contribution docs found anywhere)"; fi
