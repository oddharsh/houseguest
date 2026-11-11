#!/usr/bin/env bash
# Test for the phase meter and its report: hooks/meter.sh and skills/oss-pr/scripts/outcomes.sh.
#
#   bash tests/meter.sh
#
# Builds subagent transcripts in the line shape Claude Code writes, feeds meter.sh the
# SubagentStop JSON, and compares each log line to a literal. Then runs outcomes.sh on that log.
# Prints the cases that differ and exits 1 if any do.
#
# Needs jq and git. Touches no network and nothing outside a temp directory: `gh` is a stub that
# knows the user "me", their fork me/proj of up/proj, their own repo me/own, and 3 PRs of theirs
# on up/proj: #7 from fix-x, merged; #9 from sit, closed after a maintainer committed it by
# hand; and #11 from wt-branch, closed. A lookup for branch boom fails.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
# Your own git config may rewrite remote URLs (url.<base>.insteadOf).
export HOUSEGUEST_STATE="$W/state" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
LOG="$HOUSEGUEST_STATE/phases.jsonl"

mkdir "$W/bin"
cat > "$W/bin/gh" <<'EOF'
#!/bin/bash
pr() {  # pr <number> <state> <author> <ended> <reviews asking for changes> <commits citing it>
  echo '{"data": {"repository": {"pullRequests": {"nodes": [{"number": '"$1"', "url": "https://github.com/up/proj/pull/'"$1"'",
    "state": "'"$2"'", "author": {"login": "'"$3"'"}, "createdAt": "2026-11-01T12:00:00Z", "mergedAt": null, "closedAt": "'"$4"'",
    "reviews": {"totalCount": '"$5"'}, "timelineItems": {"nodes": '"$6"'}}]}}}}'
}
cite() { echo '{"commitRepository": {"nameWithOwner": "'"$1"'"}, "commit": {"oid": "'"$2"'", "author": {"user": {"login": "'"$3"'"}}}}'; }
case "$*" in
  "api user"*) echo me ;;
  "repo view me/proj"*) echo up/proj ;;
  "repo view me/own"*) echo me/own ;;
  "api graphql -f o=up -f r=proj -f b=fix-x "*) pr 7 MERGED me 2026-11-03T12:00:00Z 1 '[]' ;;
  # A commit in your fork that cites the PR isn't the maintainers landing it; one in their repo is.
  "api graphql -f o=up -f r=proj -f b=sit "*) pr 9 CLOSED me 2026-11-02T00:00:00Z 0 "[$(cite me/proj f0f0 me), $(cite Up/Proj abc123 me)]" ;;
  "api graphql -f o=up -f r=proj -f b=wt-branch "*) pr 11 CLOSED me 2026-11-02T00:00:00Z 0 "[$(cite up/proj d00d someone)]" ;;
  # Someone else's PR from a branch of the same name.
  "api graphql -f o=up -f r=proj -f b=feat/no-pr "*) pr 12 OPEN stranger "" 0 '[]' ;;
  "api graphql -f o=up -f r=proj -f b=boom "*) echo "gh: HTTP 502" >&2; exit 1 ;;
  *) echo "gh: unexpected call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$W/bin/gh"
export PATH="$W/bin:$PATH"

cases=0 failed=0
miss() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; }
same() {  # same <what> <got> <want>
  cases=$((cases + 1))
  [ "$2" = "$3" ] || miss "$1
  got:  $2
  want: $3"
}

clone() {  # clone <dir> <origin url> <branch>: a repo sitting on that branch
  git init -q "$1" && git -C "$1" remote add origin "$2" && git -C "$1" symbolic-ref HEAD "refs/heads/$3"
}
# transcript <agent id> <session> <cwd> <launch prompt> <output tokens of the last request>
# Two requests. The first spans two lines, as Claude Code writes one per content block. gitBranch
# is "HEAD", as it is wherever the session started outside the clone.
transcript() {
  jq -n -c --arg a "$1" --arg s "$2" --arg d "$3" --arg p "$4" --argjson out "$5" '
    {agentId: $a, gitBranch: "HEAD", cwd: $d, sessionId: $s} as $base
    | {input_tokens: 10, output_tokens: 100, cache_read_input_tokens: 1000, cache_creation_input_tokens: 50} as $u1
    | ($base + {type: "user", timestamp: "2026-11-01T10:00:00.000Z", message: {role: "user", content: $p}}),
      ($base + {type: "assistant", timestamp: "2026-11-01T10:00:05.000Z", message: {id: "m1", model: "model-a", usage: $u1,
        content: [{type: "text", text: "Reading."}]}}),
      ($base + {type: "assistant", timestamp: "2026-11-01T10:00:06.000Z", message: {id: "m1", model: "model-a", usage: $u1,
        content: [{type: "tool_use", id: "t1", name: "Read", input: {}}]}}),
      ($base + {type: "user", timestamp: "2026-11-01T10:00:07.000Z", message: {role: "user",
        content: [{type: "tool_result", tool_use_id: "t1", content: "oss-pr"}]}}),
      ($base + {type: "assistant", timestamp: "2026-11-01T10:01:30.000Z", message: {id: "m2", model: "model-a",
        usage: {input_tokens: 5, output_tokens: $out, cache_read_input_tokens: 2000, cache_creation_input_tokens: 0},
        content: [{type: "text", text: "Done."}]}})' > "$W/agent-$1.jsonl"
}
stop() {  # stop <agent id> <agent type>: the hook, as Claude Code calls it
  jq -n --arg p "$W/agent-$1.jsonl" --arg t "$2" '{hook_event_name: "SubagentStop", agent_id: "x", agent_type: $t,
    agent_transcript_path: $p, cwd: "/elsewhere"}' | bash "$ROOT/hooks/meter.sh"
}
line() { jq -c -S "$1" "$LOG" 2>/dev/null; }  # line <jq filter>: matching log lines, keys sorted
lines() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
job='[.phase, .branch, .ledger, .remote]'

F="$W/my clones/fork"; mkdir "$W/my clones" "$W/scratch"
clone "$F" https://github.com/me/proj.git sit
clone "$W/own" git@github.com:me/own.git fix-own
clone "$W/wt" https://github.com/me/proj.git wt-branch
mkdir -p "$F/.git/worktrees/w1"

# --- meter.sh ------------------------------------------------------------------
# The session sits outside the clone, the clone's path has a space, and the ledger comes after
# another path on the same line.
transcript a1 s1 "$W/scratch" "You are running phase 4 (proof) of the houseguest oss-pr skill. Read /p/skills/oss-pr/references/proof.md and write $F/.git/houseguest/fix-x/proof.md." 20
out=$(stop a1 general-purpose 2>&1); rc=$?
same "the hook exits 0 and prints nothing" "$rc|$out" "0|"
same "a phase launched as a general-purpose agent, its job from the ledger it was given" "$(line 'select(.agent == "a1")')" \
  "{\"agent\":\"a1\",\"branch\":\"fix-x\",\"cwd\":\"$W/scratch\",\"end\":\"2026-11-01T10:01:30.000Z\",\"ledger\":\"$F/.git/houseguest/fix-x\",\"phase\":\"proof\",\"remote\":\"https://github.com/me/proj.git\",\"requests\":2,\"session\":\"s1\",\"start\":\"2026-11-01T10:00:00.000Z\",\"tokens\":{\"model-a\":{\"cache_read\":3000,\"cache_write\":50,\"in\":15,\"out\":120}},\"tools\":1,\"type\":\"general-purpose\",\"v\":1}"

# A subagent that isn't houseguest's leaves no line, though a tool result of its mentions oss-pr.
transcript b1 s1 "$F" "Find where the config is parsed." 20
stop b1 general-purpose
same "an unrelated subagent is skipped" "$(lines)" 1

transcript a2 s1 "$W/scratch" "Review this pull request." 30
stop a2 houseguest:maintainer-review
same "a blind plugin agent: its phase from its type, and no job outside a clone" "$(line "select(.agent == \"a2\") | $job")" '["review",null,null,null]'

transcript a3 s2 "$F" "Follow the oss-pr skill's recon reference. The ledger is \`$F/.git/worktrees/w1/houseguest/feat/no-pr\`." 20
stop a3 general-purpose
same "no phase number, and a worktree's ledger" "$(line "select(.agent == \"a3\") | $job")" \
  "[\"unknown\",\"feat/no-pr\",\"$F/.git/worktrees/w1/houseguest/feat/no-pr\",\"https://github.com/me/proj.git\"]"

transcript a4 s3 "$W/own" "Run phase 1 (recon) of the houseguest oss-pr skill." 20
echo '{"agentType": "general-purpose"}' > "$W/agent-a4.meta.json"
bash "$ROOT/hooks/meter.sh" "$W/agent-a4.jsonl"
same "by hand, the type from .meta.json; with no ledger, the job from where the session sits" "$(line "select(.agent == \"a4\") | $job")" \
  '["recon","fix-own",null,"git@github.com:me/own.git"]'

transcript a5 s2 "$F" "Run phase 5 (copy) of the houseguest oss-pr skill. Ledger: $F/.git/houseguest/boom/" 20
stop a5 general-purpose
transcript a6 s2 "$F" "Reproduce the report on base and HEAD." 20
stop a6 houseguest:final-check
same "a blind phase inside the clone: the branch git reports, whatever gitBranch says" "$(line "select(.agent == \"a6\") | $job")" \
  '["final","sit",null,"https://github.com/me/proj.git"]'

transcript a7 s4 "$W/scratch" "Run phase 0 of the houseguest oss-pr skill." 20
stop a7 general-purpose
transcript a8 s5 "$W/wt" "Run phase 3 (write the change) of the houseguest oss-pr skill." 20
stop a8 general-purpose

before=$(lines)
out=$(echo 'not json' | bash "$ROOT/hooks/meter.sh" 2>&1); rc=$?
same "garbage on stdin still exits 0, silent" "$rc|$out" "0|"
out=$(jq -n '{agent_type: "houseguest:final-check", agent_transcript_path: "/nonexistent.jsonl"}' | bash "$ROOT/hooks/meter.sh" 2>&1); rc=$?
same "a missing transcript still exits 0, silent, and logs nothing" "$rc|$out|$(lines)" "0||$before"

# --- outcomes.sh ---------------------------------------------------------------
# A run measured again once its transcript finished writing, after its worktree is gone: the
# later line has the full count and no job.
rm -rf "$W/wt"
transcript a8 s5 "$W/wt" "Run phase 3 (write the change) of the houseguest oss-pr skill." 60
stop a8 general-purpose
same "the later line of a removed worktree" "$(line "select(.agent == \"a8\") | $job" | tail -n 1)" '["write",null,null,null]'

rows=$(bash "$ROOT/skills/oss-pr/scripts/outcomes.sh" --json 2>"$W/err"); rc=$?
same "a failed lookup exits 3" "$rc" 3
same "and is named on stderr" "$(grep -c 'PRs from boom on up/proj' "$W/err")" 1
row() { printf '%s\n' "$rows" | jq -c "select(.branch == \"$1\") | $2"; }
# s1 named one ledger, so its blind review counts toward that job.
same "the merged job: PR, days, change requests, and the session's blind run" \
  "$(row fix-x '[.repo, .pr, .runs, .rounds, .seconds, .out, .in, .cache_read]')" \
  '["up/proj",{"number":7,"url":"https://github.com/up/proj/pull/7","state":"MERGED","landed":null,"days":2,"changes_requested":1},2,1,180,250,130,6000]'
# s2 named two ledgers, so its blind final check stays on the branch the session sat on.
same "a PR closed after a commit of yours in their repo cites it" "$(row sit '[.pr.number, .pr.state, .pr.landed, .pr.days, .runs]')" '[9,"LANDED","abc123",0.5,1]'
same "a PR closed with only someone else's commit citing it; last counts, first known job" \
  "$(row wt-branch '[.pr.number, .pr.state, .pr.landed, .runs, .out]')" '[11,"CLOSED",null,1,160]'
same "a branch where the only PR is someone else's" "$(row feat/no-pr '[.repo, .pr]')" '["up/proj",{"state":"none"}]'
same "a failed lookup isn't none" "$(row boom '.pr')" '{"state":"LOOKUP FAILED"}'
same "a session outside any clone that named no ledger" "$(printf '%s\n' "$rows" | jq -c 'select(.branch == null) | [.repo, .pr]')" '[null,{"state":"no GitHub remote"}]'
same "a job on your own repo is left out" "$(row fix-own '.repo')" ""

table=$(bash "$ROOT/skills/oss-pr/scripts/outcomes.sh" 2>/dev/null)
same "the table's totals" "$(printf '%s\n' "$table" | tail -n 3)" \
"6 jobs: 2 merged (1 landed by hand), 1 closed unmerged, 0 open, 3 with no PR.
Output tokens per merged PR: 445 (every job's output tokens over 2 merged).
1 jobs on repos you own left out."

echo "$cases cases, $failed failed"
[ "$failed" -eq 0 ]
