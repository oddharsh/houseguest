#!/usr/bin/env bash
# Which builds besides prod could behave differently for this bug?
#
#   channels.sh --repo owner/name --paths a,b [--q "terms"]... [--package NAME]
#               [--prod REF|VERSION] [--channel name=REF]... [--as-of DATE]
#
# Finds the builds people run besides the stable release: the default branch (head),
# branches named beta/canary/next/nightly/develop/preview, the newest GitHub prerelease,
# and the package's npm dist-tags. For each, it compares against prod on GitHub, with
# nothing built or cloned, and asks whether anything changed that could change the repro:
#   - a commit touching --paths (files or folders where the bug lives),
#   - a commit whose message has every word of a --q,
#   - the package manifest above --paths (dependencies changed).
# A channel that differs needs its own repro; one that doesn't is skipped, and the
# prod result stands for it. An experimental build of a commit already listed only matters for
# flag-gated code. Ends with REPRODUCE ON and SKIP lines, plus a line for recon.md.
#
# --prod     what the user runs: a tag, a version (tried as <package>@V, vV, V), or a sha.
#            Default: npm's latest for --package, else the newest stable GitHub release.
# --channel  add a build by hand, like nightly=release-nightly-2026-10-01 (tag, branch, or sha).
# --as-of    see the channels as they stood then (replays).

set -uo pipefail
repo="" paths="" pkg="" prod="" asof=""
queries=() extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --paths|--files) paths="$2"; shift 2 ;;
    --q) queries+=("$2"); shift 2 ;;
    --package) pkg="$2"; shift 2 ;;
    --prod) prod="$2"; shift 2 ;;
    --channel) extra+=("$2"); shift 2 ;;
    --as-of) asof="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "channels.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { echo "channels.sh: --repo is required" >&2; exit 2; }
[ -n "$paths" ] || [ ${#queries[@]} -gt 0 ] || { echo "channels.sh: pass --paths (where the bug lives) or --q (terms), or nothing can be compared" >&2; exit 2; }

T="9999"; [ -n "$asof" ] && { case "$asof" in *T*) T="$asof" ;; *) T="${asof}T00:00:00Z" ;; esac; }
# Failed calls are recorded, so a channel whose evidence couldn't be fetched reads UNKNOWN, never SAME.
errf=$(mktemp); trap 'rm -f "$errf"' EXIT
api() { gh api "$@" 2>/dev/null || { echo 1 > "$errf"; return 1; }; }
left=$(gh api rate_limit --jq '.resources.core | "\(.remaining) \(.reset | todate)"' 2>/dev/null)
[ -n "$left" ] && [ "${left%% *}" -lt 150 ] && { echo "channels.sh: only ${left%% *} GitHub API calls left until ${left#* }; a run needs about 100, so wait rather than get guesses" >&2; exit 2; }
short() { echo "${1:0:9}"; }

# A ref name or version to a commit sha, or nothing.
sha_of() {
  local r="$1" s
  echo "$r" | grep -q -E '^[0-9a-f]{7,40}$' && { s=$(api "repos/$repo/commits/$r" --jq .sha) && [ -n "$s" ] && { echo "$s"; return; }; }
  for cand in "$r" ${pkg:+"$pkg@$r"} "v$r"; do
    s=$(api "repos/$repo/commits/$(printf '%s' "$cand" | jq -sRr @uri)" --jq .sha) && [ -n "$s" ] && { echo "$s"; return; }
  done
}
# A branch's tip as of T.
branch_at() { api "repos/$repo/commits?sha=$(printf '%s' "$1" | jq -sRr @uri)&until=$T&per_page=1" --jq '.[0].sha // empty'; }
# A tag for a version, in the shapes repos use: 1.2.3, v1.2.3, pkg@1.2.3, oxlint_v1.2.3,
# crates_v0.153.0, 0.4.21-jpeg. All tags come from one ls-remote; the character after the version
# must end it (0.4.21 shouldn't match 0.4.210). With several matches, one naming the package wins.
alltags=""
tag_for() {
  local v="$1" vre m
  [ -n "$alltags" ] || alltags=$(git ls-remote --tags "https://github.com/$repo" 2>/dev/null | awk '{print $2}' | sed 's#^refs/tags/##; s#\^{}$##' | sort -u)
  vre=$(printf '%s' "$v" | sed 's/[.+]/\\&/g')
  m=$(echo "$alltags" | grep -E "(^|[^0-9.])v?$vre(\$|[-_+][A-Za-z])")
  [ -n "$m" ] || return 1
  { [ -n "$pkg" ] && echo "$m" | grep -F -e "$pkg" -e "${pkg##*[-/@]}"; echo "$m"; } | head -1
}
sha_of_tag() { api "repos/$repo/commits/$(printf '%s' "$1" | jq -sRr @uri)" --jq .sha >/dev/null && echo "$1"; }
# A registry version to a commit: the commit the registry recorded (npm gitHead, the crate's
# .cargo_vcs_info.json), a sha inside a canary version, or a tag. A match whose commit is far from
# the publish date is wrong (oxc's v0.1.1 from 2023 for oxlint 1.78), so it's rejected.
ver_sha() {
  local v="$1" pub="${2:-}" s="" h tg d
  case "$eco" in
    npm) h=$(npm view "$pkg@$v" gitHead 2>/dev/null) ;;
    crates) h=$(curl -sL -H 'User-Agent: houseguest (github.com/oddharsh/houseguest)' "https://static.crates.io/crates/$pkg/$pkg-$v.crate" | tar xzO "$pkg-$v/.cargo_vcs_info.json" 2>/dev/null | jq -r '.git.sha1 // empty' 2>/dev/null) ;;
    *) h="" ;;
  esac
  [ -n "$h" ] && s=$(sha_of "$h")
  [ -z "$s" ] && h=$(echo "$v" | grep -o -E '[0-9a-f]{7,40}' | head -1) && [ -n "$h" ] && s=$(sha_of "$h")
  [ -z "$s" ] && tg=$(tag_for "$v") && s=$(sha_of "$tg")
  # Last resort: the last commit to the package's folder on the default branch before it was published.
  if [ -z "$s" ] && [ -n "$pub" ]; then
    case "$eco" in
      npm) dir=$(npm view "$pkg@$v" repository.directory 2>/dev/null) ;;
      *) dir="" ;;
    esac
    s=$(api "repos/$repo/commits?sha=$(api "repos/$repo" --jq .default_branch)&until=$pub&per_page=1${dir:+&path=$(printf '%s' "$dir" | jq -sRr @uri)}" --jq '.[0].sha // empty')
    [ -n "$s" ] && { echo "channels.sh: $pkg@$v names no commit or tag; using the last commit${dir:+ to $dir} before it was published (${s:0:9}), an approximation" >&2; echo "$s"; return 0; }
  fi
  [ -n "$s" ] || return 0
  if [ -n "$pub" ]; then
    d=$(api "repos/$repo/commits/$s" --jq .commit.committer.date)
    # Built at most a day after publishing (clock skew) and at most 90 days before it.
    if [ -n "$d" ] && jq -e -n --arg d "$d" --arg p "$pub" '(($d | sub("\\.[0-9]+"; "") | fromdate) - ($p | sub("\\.[0-9]+"; "") | fromdate)) as $x | $x > 86400 or $x < -7776000' >/dev/null; then
      echo "channels.sh: $pkg@$v (published ${pub:0:10}) mapped to commit ${s:0:9} from ${d:0:10}; that's too far apart to be its build, so it's ignored" >&2
      return 0
    fi
  fi
  echo "$s"
}
# Versions compare by their numeric release part; prereleases carry letters (-beta.1, rc1, .dev0).
JQV='def base: sub("^v"; "") | split("-")[0] | [scan("[0-9]+")] | map(tonumber) | .[:3];
     def pre: sub("^v"; "") | test("[A-Za-z]");'

# --- Registry versions, as {versions: [{v, t}], tags: {name: version}} -------------------
eco=npm; case "$pkg" in crates:*) eco=crates; pkg=${pkg#crates:} ;; pypi:*) eco=pypi; pkg=${pkg#pypi:} ;; npm:*) pkg=${pkg#npm:} ;; esac
reg=""
if [ -n "$pkg" ]; then
  case "$eco" in
    npm) reg=$(npm view "$pkg" dist-tags time --json 2>/dev/null | jq -c '{versions: [.time | to_entries[] | select(.key != "created" and .key != "modified") | {v: .key, t: .value}], tags: .["dist-tags"]}') ;;
    crates) reg=$(curl -s -H 'User-Agent: houseguest (github.com/oddharsh/houseguest)' "https://crates.io/api/v1/crates/$pkg" | jq -c '{versions: [.versions[]? | select(.yanked | not) | {v: .num, t: .created_at}], tags: {}}') ;;
    pypi) reg=$(curl -s "https://pypi.org/pypi/$pkg/json" | jq -c '{versions: [.releases | to_entries[] | select(.value | length > 0) | {v: .key, t: (.value | map(.upload_time_iso_8601) | min)}], tags: {}}') ;;
  esac
  [ "$(echo "$reg" | jq '.versions | length' 2>/dev/null)" -gt 0 ] 2>/dev/null || { echo "channels.sh: no $eco versions found for $pkg" >&2; reg=""; }
fi

# --- Prod ---------------------------------------------------------------------------
prod_label="" prod_sha="" prod_ver=""
if [ -n "$prod" ]; then
  prod_sha=$(sha_of "$prod"); prod_label="$prod"
  echo "$prod" | grep -q -E '^v?[0-9]+\.[0-9]+' && prod_ver="${prod#v}"
elif [ -n "$reg" ]; then
  # npm's latest tag when looking at now; otherwise the highest stable version published before T.
  v=$(echo "$reg" | jq -r --arg t "$T" "$JQV"'if $t == "9999" and .tags.latest then .tags.latest
       else [.versions[] | select((.v | pre | not) and .t < $t)] | max_by(.v | base) | .v end // empty')
  if [ -n "$v" ]; then
    prod_ver="$v"; prod_label="$pkg@$v ($eco)"
    prod_sha=$(ver_sha "$v" "$(echo "$reg" | jq -r --arg v "$v" '[.versions[] | select(.v == $v) | .t] | first // empty')")
    [ -n "$prod_sha" ] || { echo "channels.sh: couldn't find the commit $pkg@$v was built from (no gitHead, no matching tag); pass --prod <tag|sha>" >&2; exit 2; }
  fi
fi
if [ -z "$prod_sha" ] && [ -z "$prod" ]; then
  rel=$(api "repos/$repo/releases?per_page=50" | jq -r --arg t "$T" --arg p "${pkg:+$pkg@}" \
    '[.[] | select((.draft | not) and (.prerelease | not) and .published_at < $t) | select($p == "" or (.tag_name | startswith($p)))] | first | .tag_name // empty')
  [ -n "$rel" ] && { prod_sha=$(sha_of "$rel"); prod_label="$rel (newest stable release)"; prod_ver="${rel##*@}"; prod_ver="${prod_ver#v}"; }
fi
if [ -z "$prod_sha" ] && [ -z "$prod" ]; then
  # No releases or registry: the highest version tag whose commit predates T.
  for tg in $(api "repos/$repo/tags?per_page=100" --jq '.[].name' | jq -R -r -s --arg p "${pkg:+$pkg@}" "$JQV"'split("\n") | map(select(length > 0)
        | select(ltrimstr($p) | test("^v?[0-9]+(\\.[0-9]+)+$"))) | sort_by(ltrimstr($p) | base) | reverse | .[:8][]'); do
    s=$(sha_of "$tg"); d=$(api "repos/$repo/commits/$s" --jq .commit.committer.date)
    [ -n "$s" ] && [[ "$d" < "$T" ]] && { prod_sha="$s"; prod_label="$tg (highest version tag)"; prod_ver="${tg##*@}"; prod_ver="${prod_ver#v}"; break; }
  done
fi
if [ -z "$prod_sha" ] && [ -z "$prod" ] && [ -z "$pkg" ]; then
  # No registry, releases, or version tags: people run the default branch, so head is prod.
  d0=$(api "repos/$repo" --jq .default_branch); prod_sha=$(branch_at "$d0")
  [ -n "$prod_sha" ] && prod_label="$d0 (no releases or version tags, so head is the only build)"
fi
[ -n "$prod_sha" ] || { echo "channels.sh: couldn't find prod${prod:+ for $prod}; pass --prod <tag|version|sha> for the build the user runs" >&2; exit 2; }

# --- The other channels: "name<TAB>label<TAB>sha<TAB>how to get it" ----------------------
chans=""
addc() { [ -n "$3" ] && chans="$chans$1	$2	$3	$4
"; }
default=$(api "repos/$repo" --jq .default_branch)
# Some repos rebuild a rolling release from head on every commit (Bun's `canary`, a `nightly` tag):
# that's the cheap way to run head. Only meaningful now, since the release keeps no history.
head_how="build $default from source at that commit, following CONTRIBUTING"
if [ "$T" = 9999 ]; then
  for rt in canary nightly tip; do
    u=$(api "repos/$repo/releases/tags/$rt" --jq .html_url) && [ -n "$u" ] && { head_how="install the rolling $rt release, rebuilt from $default ($u), or build from source"; break; }
  done
fi
addc head "$default @ $(short "$(branch_at "$default")")" "$(branch_at "$default")" "$head_how"
for b in $(api "repos/$repo/git/matching-refs/heads/" --jq '.[].ref' | sed 's#^refs/heads/##' | grep -i -x -E 'beta|canary|next|nightly|develop|dev|preview|unstable|staging' | head -5); do
  [ "$b" = "$default" ] && continue
  s=$(branch_at "$b"); addc "$b" "branch $b @ $(short "$s")" "$s" "build branch $b from source at that commit"
done
pre=$(api "repos/$repo/releases?per_page=50" | jq -r --arg t "$T" --arg p "${pkg:+$pkg@}" \
  '[.[] | select((.draft | not) and .prerelease and .published_at < $t) | select($p == "" or (.tag_name | startswith($p)))] | first | "\(.tag_name)\t\(.html_url)" // empty')
[ -n "$pre" ] && addc prerelease "release ${pre%%	*}" "$(sha_of "${pre%%	*}")" "download the assets at ${pre#*	}"
if [ -n "$reg" ]; then
  # npm: each dist-tag besides latest, as it stood at T (the newest version with the same prerelease id).
  # Other registries: the newest prerelease. Only builds published after prod count: tags for older
  # lines (legacy, backport, a beta from last year) aren't newer builds. Canary versions often carry a
  # lower version number than prod (19.3.0-canary vs 19.3.1), so this goes by publish time.
  echo "$reg" | jq -r --arg t "$T" --arg pv "$prod_ver" --arg eco "$eco" "$JQV"'
      .versions as $vs
      | ([$vs[] | select(.v == $pv) | .t] | first // "") as $pt
      | def newer: . as $v | ([$vs[] | select(.v == $v) | .t] | first // "9999") >= $pt
          and ($pv == "" or ($v | pre) or ($v | base) >= ($pv | base));
      if $eco == "npm" then
        .tags | to_entries[] | select(.key != "latest" and (.key | test("^[A-Za-z][A-Za-z0-9_-]*$"))) | select(.value | newer)
        | .key as $k | .value as $v
        | (if $t == "9999" then $v else
            (([$v | capture("-(?<id>[A-Za-z]+)")?] | first | .id) // $k) as $id
            | [$vs[] | select(.v | test("-" + $id + "\\b")) | select(.t < $t)] | max_by(.t) | .v // empty end)
        | select(. != null and . != "") | "\($k)\t\(.)"
      else [$vs[] | select((.v | pre) and .t < $t) | select(.v | newer)] | max_by(.t) | select(. != null) | "prerelease\t\(.v)" end' 2>/dev/null | head -6 > "${TMPDIR:-/tmp}/hg-tags.$$"
  while IFS=$'\t' read -r tag ver; do
    [ -n "$ver" ] || continue
    s=$(ver_sha "$ver" "$(echo "$reg" | jq -r --arg v "$ver" '[.versions[] | select(.v == $v) | .t] | first // empty')")
    case "$eco" in npm) how="npx $pkg@$ver (or install it in the repro project)" ;; crates) how="depend on $pkg = \"=$ver\"" ;; pypi) how="pip install $pkg==$ver" ;; esac
    addc "$tag" "$eco $pkg@$tag = $ver" "${s:-unknown}" "$how"
  done < "${TMPDIR:-/tmp}/hg-tags.$$"; rm -f "${TMPDIR:-/tmp}/hg-tags.$$"
fi
for e in ${extra[@]+"${extra[@]}"}; do
  n="${e%%=*}"; r="${e#*=}"; s=$(sha_of "$r"); [ -z "$s" ] && s=$(branch_at "$r")
  if [ -n "$s" ]; then addc "$n" "$r @ $(short "$s")" "$s" "build or install $r"; else chans="$chans$n	$r	unknown	build or install $r (couldn't resolve it)
"; fi
done

# --- Compare each channel with prod ---------------------------------------------------
pjson=$(printf '%s' "$paths" | jq -R 'split(",") | map(select(length > 0) | sub("/+$"; ""))')
# Terms match whole words in commit subjects. Bodies are PR descriptions full of incidental words,
# and short or numeric words ("27", "age") match PR numbers and "message".
qjson=$(printf '%s\n' ${queries[@]+"${queries[@]}"} | jq -R -s 'split("\n") | map(ascii_downcase | split(" ") | map(select(length >= 3 and (test("^[0-9]+$") | not)))) | map(select(length > 0))')
prod_date=$(api "repos/$repo/commits/$prod_sha" --jq .commit.committer.date)

echo "# Build channels: $repo"
echo
echo "Prod: $prod_label, commit $(short "$prod_sha") ($prod_date)"
echo "Paths: ${paths:-none}. Terms: $(printf '%s; ' ${queries[@]+"${queries[@]}"} | sed 's/; $//')${asof:+. As of $T}"

repro="prod ($prod_label)" skip="" flagged="" deps="" sweeps="" recon="prod $prod_label: <reproduces? yes/no>" seen=" $prod_sha "
while IFS=$'\t' read -r name label sha how; do
  [ -n "$name" ] || continue
  echo; echo "## $name: $label"
  if [ "$sha" = unknown ]; then
    echo "- VERDICT: UNKNOWN. $how. Reproduce on it to be safe."
    repro="$repro, $name ($label)"; recon="$recon; $name $label: <yes/no>"; continue
  fi
  case "$seen" in *" $sha "*)
    same=$(printf '%s' "$chans" | awk -F'\t' -v s="$sha" '$3 == s {print $1; exit}'); [ "$sha" = "$prod_sha" ] && same=prod
    # Same source can still ship as a different build: experimental channels turn feature flags on.
    if echo "$name $label" | grep -q -i -E 'experimental|insiders|unstable'; then
      echo "- Same commit as $same, built with experimental flags on. Reproduce on it only if your code path checks a feature flag (search the repo's flags file for the functions in your repro)."
      flagged="$flagged, $name ($label)"; continue
    fi
    echo "- Same commit as $same; nothing to do."; skip="$skip, $name (same commit as $same)"; continue ;;
  esac
  seen="$seen$sha "
  # A branch last touched before prod shipped is stale (an abandoned line), not a newer build.
  # Published builds aren't judged this way: a beta cut from a diverged line can predate prod's commit.
  cdate=$(api "repos/$repo/commits/$sha" --jq .commit.committer.date)
  if [ "${label#branch }" != "$label" ] && [ -n "$cdate" ] && [[ "$cdate" < "$prod_date" ]]; then
    echo "- Last commit ${cdate:0:10}, before prod's ${prod_date:0:10}: stale, not a newer build."; skip="$skip, $name (older than prod)"; continue
  fi
  # A failed compare has its own fallback below, so only the calls after it count as failures.
  cmp=$(api "repos/$repo/compare/$prod_sha...$sha"); : > "$errf"
  status=$(echo "$cmp" | jq -r 'if .ahead_by != null then .status else empty end' 2>/dev/null)
  ahead=$(echo "$cmp" | jq -r '.ahead_by // empty' 2>/dev/null)
  if [ "$status" = identical ] || [ "$status" = behind ] || [ "$ahead" = 0 ]; then
    echo "- Nothing in it that prod lacks ($status)."; skip="$skip, $name (nothing newer than prod)"; continue
  fi
  # Commits on the paths since prod. Exact from the compare when it's complete; when GitHub can't
  # compare (too large, diverged lines), approximate with commits since prod's date.
  pathlog() { for p in $(echo "$pjson" | jq -r '.[]'); do
      api "repos/$repo/commits?sha=$sha&path=$(printf '%s' "$p" | jq -sRr @uri)&since=$prod_date&per_page=30" | jq -r --arg prod "$prod_sha" '.[] | select(.sha != $prod) | "\(.sha[:9]) \(.commit.committer.date[:10]) \(.commit.message | split("\n")[0])"'
    done; }
  tcommits=$(pathlog); touched="" manif=""
  if [ -n "$status" ] && [ "$(echo "$cmp" | jq '.files | length')" -lt 300 ] && [ "$(echo "$cmp" | jq '.commits | length')" -ge "$ahead" ]; then
    approx=""; clist=$(echo "$cmp" | jq -c '[.commits[] | {sha, m: .commit.message, d: .commit.committer.date}]')
    touched=$(echo "$cmp" | jq -r --argjson P "$pjson" '[.files[] | .filename as $f | select(any($P[]; . as $p | $f == $p or ($f | startswith($p + "/"))))] | map("    - \(.filename) (+\(.additions) -\(.deletions))") | .[:12][]')
    manif=$(echo "$cmp" | jq -r --argjson P "$pjson" '.files[].filename | select(test("(^|/)(package\\.json|Cargo\\.toml|go\\.mod|pyproject\\.toml|setup\\.cfg|requirements[^/]*\\.txt|Gemfile|build\\.zig\\.zon)$"))
      | . as $f | ($f | split("/")[:-1] | join("/")) as $d | select($d != "" and any($P[]; . == $d or startswith($d + "/")))')
  else
    approx=" (GitHub's compare came back incomplete or failed, so these are commits since prod's date)"
    clist=$(for pg in 1 2 3; do api "repos/$repo/commits?sha=$sha&since=$prod_date&per_page=100&page=$pg" --jq '.[] | {sha, m: .commit.message, d: .commit.committer.date}'; done | jq -s -c .)
    [ -n "$clist" ] || clist='[]'
  fi
  qcommits=$(echo "$clist" | jq -r --argjson Q "$qjson" --arg prod "$prod_sha" '.[] | select(.sha != $prod) | (.m | split("\n")[0] | ascii_downcase) as $m
      | select(any($Q[]; all(.[]; . as $w | $m | test("\\b" + $w + "\\b")))) | "\(.sha[:9]) \(.d[:10]) \(.m | split("\n")[0])"' | head -8)
  tcommits=$(printf '%s' "$tcommits" | sed '/^$/d' | sort -u -k1,1 | sort -k2 -r | head -12)
  if [ -s "$errf" ] && [ -z "$touched$tcommits$qcommits$manif" ]; then
    echo "- VERDICT: UNKNOWN. GitHub API calls failed while checking it (rate limit or network). Rerun later, or reproduce on it."
    repro="$repro, $name ($label)"; recon="$recon; $name $label: <yes/no>"; continue
  fi
  echo "- ${ahead:-Some} commits newer than prod$approx."
  if [ -n "$touched$tcommits" ]; then echo "- Touching your paths:"; [ -n "$tcommits" ] && echo "$tcommits" | sed 's/^/    - /'; [ -n "$touched" ] && { echo "  Files:"; echo "$touched"; }; fi
  [ -n "$qcommits" ] && { echo "- Commit messages matching your terms:"; echo "$qcommits" | sed 's/^/    - /'; }
  [ -n "$manif" ] && echo "- Package manifest changed: $(echo "$manif" | tr '\n' ' ')(dependencies may differ)"
  # Repo-wide sweeps (dead code, renames, formatting, README edits) touch every file without
  # changing behavior. When they're all that touched the paths, the agent reads them before building.
  substantive=$(printf '%s\n%s\n' "$tcommits" "$qcommits" | sed '/^$/d' | cut -d' ' -f3- \
    | grep -v -i -E '(remove|delete|drop) (the )?(dead|unused|leftover|orphaned)|dead code|^(chore|docs|style|ci|build)(\(|:)|\b(rename|reformat|formatting|typos?|clippy|lint fix|update readme|readme)\b|^update [A-Za-z./_-]+\.md$|^bump ')
  if [ -n "$tcommits$qcommits" ] && [ -z "$substantive" ] && [ -z "$manif" ]; then
    echo "- VERDICT: SWEEPS ONLY. Every listed commit is a cleanup, rename, format, or docs change. Read them; reproduce only if one could change the behavior."
    sweeps="$sweeps, $name ($label)"
  elif [ -z "$touched$tcommits$qcommits" ] && [ -n "$manif" ]; then
    echo "- VERDICT: DEPENDENCIES ONLY. No commit touches your paths or names the bug; only the package manifest changed. Reproduce on it only if the bug could come from a dependency."
    deps="$deps, $name ($label)"; recon="$recon"
  elif [ -n "$touched$tcommits$qcommits$manif" ]; then
    echo "- VERDICT: DIFFERS. Get it ($how) and run the repro."
    n=$(printf '%s\n%s\n' "$tcommits" "$qcommits" | sed '/^$/d' | cut -d' ' -f1 | sort -u | wc -l | tr -d ' ')
    repro="$repro, $name ($label)"; recon="$recon; $name $label: <yes/no> ($n relevant commit(s))"
  else
    echo "- VERDICT: SAME for this bug. None of its commits touch your paths, mention your terms, or change the package manifest."
    skip="$skip, $name (no relevant changes)"; recon="$recon"
  fi
done <<EOF
$chans
EOF

echo
echo "REPRODUCE ON: $repro"
skip="${skip#, }"; echo "SKIP: ${skip:-nothing}"
flagged="${flagged#, }"; [ -n "$flagged" ] && echo "ONLY IF FLAG-GATED: $flagged"
deps="${deps#, }"; [ -n "$deps" ] && echo "ONLY IF DEPENDENCY-RELATED: $deps"
sweeps="${sweeps#, }"; [ -n "$sweeps" ] && echo "READ THE COMMITS FIRST (sweeps only): $sweeps"
echo
echo "For recon.md (fill in each result):"
echo "- Reproduces on: $recon${skip:+; skipped: $skip}"
