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
# Pages outside GitHub can only be read live; the output marks them.
# --keep DIR leaves the fetched docs in DIR so other checks can grep them.
# Read-only: GET requests only.

set -uo pipefail

repo="" asof="" keep=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --as-of) asof="$2"; shift 2 ;;
    --keep) keep="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "policy.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { echo "policy.sh: --repo owner/name is required" >&2; exit 2; }
owner="${repo%%/*}"
asof_ts="9999"
if [ -n "$asof" ]; then case "$asof" in *T*) asof_ts="$asof" ;; *) asof_ts="${asof}T00:00:00Z" ;; esac; fi

if [ -n "$keep" ]; then dir="$keep"; mkdir -p "$dir"; else dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT; fi
sources="$dir/.sources"; : > "$sources"

AI_RE='\bLLMs?\b|large language model|AI[- ]?(generated|assisted|assistance|tools?|agents?|policy|use|usage|written|authored)|generative AI|machine[- ]generated|chatgpt|copilot|claude|gemini|\bGPT\b|vibe[- ]cod|slop'
NAME_RE='(^|/)(CONTRIBUTING|CONTRIBUTE|HACKING|DEVELOPMENT|GOVERNANCE|AI_POLICY|AI-POLICY|AGENTS|CLAUDE|TRIAGE)(\.(md|rst|txt|adoc))?$|(^|/)LLMS?[^/]*\.(md|rst|adoc)$|^(\.github/)?README(\.(md|rst|txt|adoc))?$|(^|/)[^/]*(ai|llm|genai)[-_ .]?(policy|policies|usage|use|contribution|contributions|guidelines|rules)[^/]*\.(md|rst|txt|adoc)$|(^|/)[^/]*contribut[^/]*\.(md|rst|txt|adoc)$|^\.github/(PULL_REQUEST_TEMPLATE|ISSUE_TEMPLATE|DISCUSSION_TEMPLATE)|pull_request_template'
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
tree=$(list_tree "$repo" "$ref" 2>"$dir/.trunc")
[ -s "$dir/.trunc" ] && echo "- note: $repo's tree is too large to list in full; nested policy files may be missed"
echo "$tree" | grep -iE "$NAME_RE" | grep -v -iE "$SKIP_RE" | head -40 \
  | while IFS= read -r p; do fetch "$repo" "$ref" "$p" "repo"; done

# 3: org-wide defaults in owner/.github.
if [ "$repo" != "$owner/.github" ] && gh api "repos/$owner/.github" --jq .full_name >/dev/null 2>&1; then
  oref=$(ref_of "$owner/.github")
  if [ -n "$oref" ]; then
    list_tree "$owner/.github" "$oref" 2>/dev/null | grep -iE "$NAME_RE|^profile/README\.md$" | head -20 \
      | while IFS= read -r p; do fetch "$owner/.github" "$oref" "$p" "org default ($owner/.github)"; done
  fi
fi

# 4: follow contribution links one level, out of the repo if needed.
links=$( { grep -rhoE 'https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(blob|tree)/[^ )">'"'"'`]+' "$dir" 2>/dev/null
           grep -rhoE 'https?://[^ )">'"'"'`]+' "$dir" 2>/dev/null | grep -iE 'contribut|policy|policies|guideline|\bai\b|llm|code-of-conduct|governance' ; } \
         | sed 's/[.,;:]*$//; s/#.*$//' | grep -v -E '[$]\{|\{\{|%7B' | sort -u | head -25)
echo "$links" | while IFS= read -r url; do
  [ -z "$url" ] && continue
  if echo "$url" | grep -qE '^https?://github\.com/[^/]+/[^/]+/(blob|tree)/'; then
    lrepo=$(echo "$url" | sed -E 's#^https?://github\.com/([^/]+/[^/]+)/(blob|tree)/[^/]+/.*#\1#')
    lpath=$(echo "$url" | sed -E 's#^https?://github\.com/[^/]+/[^/]+/(blob|tree)/[^/]+/##')
    echo "$lpath" | grep -qiE "$NAME_RE|polic|guideline|\.md$" || continue
    echo "$lpath" | grep -qiE '\.(md|rst|txt|adoc)$' || continue
    lref=$(ref_of "$lrepo"); [ -n "$lref" ] && fetch "$lrepo" "$lref" "$lpath" "linked from $repo"
  elif ! echo "$url" | grep -qiE '^https?://([a-z0-9-]+\.)*(github\.com|shields\.io|badge|crates\.io|docs\.rs|npmjs\.com|opensource\.guide|contributor-covenant\.org|choosealicense\.com|creativecommons\.org|semver\.org|keepachangelog\.com|conventionalcommits\.org|opensource\.org|apache\.org/licenses|gnu\.org)'; then
    safe=$(echo "$url" | sed -E 's#^https?://##; s#[^A-Za-z0-9._/-]#_#g')
    dest="$dir/live/$safe.txt"; mkdir -p "$(dirname "$dest")"
    if curl -sL --max-time 10 "$url" | sed -e 's/<[^>]*>/ /g' | tr -s ' \t' > "$dest" 2>/dev/null && [ -s "$dest" ]; then
      printf '%s\t%s\t%s\n' "$url" "live" "linked page outside GitHub (read live, not as of then)" >> "$sources"
    else rm -f "$dest"; fi
  fi
done

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
    | while IFS= read -r p; do fetch "$up" "$uref" "$p" "upstream repo named in $repo's contribution docs"; done
done

# Report every source. A mention counts as a rule when rule language sits within a
# line of it; product docs that merely talk about AI stay out of the verdict.
POLICY_RE='\bmust\b|please (uncomment|fill|answer|check|tick|state|disclose|declare|mark|label)|uncomment|REQUIRED|must not|required|requires|disclos|declare|prohibit|forbid|\bban(ned|s)?\b|not (be )?accept|will be closed|be closed|reject|not allowed|allowed|permitted|polic(y|ies)|human[- ]?(written|authored|in the loop|review)|your own words|yourself|label(led)?|in a quote|<details>|responsib|do not (use|submit|open)|don.t (use|submit|open)'
CTX_RE='pull request|\bPRs?\b|\bissues?\b|\bcomments?\b|contribut|submi(t|ssion)|\bpatch(es)?\b|commit message|descriptions?|reviewers?|maintainers?'
ENF_RE='(AI|LLM)[- ]?(generated|written|authored|assisted) (PRs?|pull requests?|code|issues?|comments?|contributions?|descriptions?|text|patch(es)?|changes?|reports?)|(this|your|the|entire|whole) (PR|pull request|issue|comment|contribution|description|code|report)[^.]{0,40}(AI|LLM)[- ]?(generated|written)|(seems|looks|reads|is) (like it was |to be |)(AI|LLM)[- ]?(generated|written)|generated (by|with) (an? )?(AI|LLM|ChatGPT|Claude|Copilot)|(AI|LLM)[- ](policy|policies)|your (AI|LLM|agent|bot)|\bslop\b|(written|wrote) (by|with) (an? )?(AI|LLM|ChatGPT|Claude|Copilot)|human[- ]written|in your own words'
rules=0; mentions=0; : > "$dir/.mention_srcs"
while IFS=$'\t' read -r src at why; do
  f="$dir/$src"
  case "$src" in http*) f="$dir/live/$(echo "$src" | sed -E 's#^https?://##; s#[^A-Za-z0-9._/-]#_#g').txt" ;; esac
  [ -f "$f" ] || continue
  lines=$(grep -n -i -E "$AI_RE" "$f" 2>/dev/null | cut -d: -f1 | head -40)
  [ -z "$lines" ] && continue
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
# GitHub search allows at most 5 boolean operators per query, so split the terms.
nums=""
for terms in '(LLM OR "AI-generated" OR "AI generated" OR "AI-assisted")' '(ChatGPT OR Copilot OR Claude OR slop)'; do
  q="repo:$repo in:comments $terms"
  [ "$asof_ts" != "9999" ] && q="$q created:<$asof_ts"
  nums="$nums $(gh api -X GET search/issues -f q="$q" -f per_page=10 --jq '.items[].number' 2>/dev/null | grep -E '^[0-9]+$')"
done
nums=$(echo $nums | tr ' ' '\n' | sort -rn | uniq | head -16)  # newest threads first
enf=""
for n in $nums; do
  got=$(gh api "repos/$repo/issues/$n/comments?per_page=100" 2>/dev/null | jq -r --arg t "$asof_ts" --arg re "$AI_RE" --arg enf "$ENF_RE" --arg n "$n" '
    (if type == "array" then .[] else empty end) | select(.created_at < $t) | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR"))
    | select(.user.type != "Bot") | select(.body | test($enf; "i"))
    | "- #\($n) **\(.user.login)** (\(.author_association), \(.created_at[:10])): \(.body | gsub("\\s+"; " ") | .[:300])"' 2>/dev/null | head -2)
  [ -n "$got" ] && enf="$enf
$got"
done
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
