#!/usr/bin/env bash
# SubagentStop: log what each houseguest phase spent, in a file that outlives the clone.
#
#   meter.sh            the hook: reads Claude Code's SubagentStop JSON on stdin
#   meter.sh FILE...    measure subagent transcripts (agent-<id>.jsonl) by hand: runs from before
#                       the hook existed, or again once a transcript has finished writing. The
#                       agent type comes from FILE's .meta.json
#
# Appends one JSON line per run to $HOUSEGUEST_STATE/phases.jsonl (default
# ~/.local/state/houseguest): the phase, the session, the job it ran for, its first and last
# timestamps, API requests, tool calls, and tokens by model. Tokens and not dollars, since a
# token count can be priced on any later date. skills/oss-pr/scripts/outcomes.sh reads the log;
# a run measured twice has two lines with the same `agent`, and readers keep the last.
#
# A run is houseguest's when its agent type is houseguest:<name>, or its launch prompt names
# oss-pr. The phase is the plugin agent's own, or the "phase N" the launch prompt opens with
# ("Launch" in SKILL.md); a prompt with neither is logged as "unknown". Every other subagent is
# skipped after one line is read.
#
# The job is the ledger the launch prompt names: the PR gate wants a ledger named for the branch
# the PR opens from, so that name is the PR's head. A blind phase is never given the ledger, and
# falls back to the branch and remote of the directory the session sat in; outcomes.sh moves it
# to the session's job when the session named only one.
#
# Prints nothing and always exits 0: exit 2 from a SubagentStop hook keeps the subagent running.
#
# Claude Code documents agent_transcript_path, and says the file is written asynchronously, so
# the hook can miss a run's last request. The line shape it doesn't document; this reads the one
# Claude Code 2.1.308 to 2.1.322 wrote (checked 2026-11-10), and tests/meter.sh pins each field.

set -u
log="${HOUSEGUEST_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/houseguest}/phases.jsonl"

# remote <git options>: the upstream remote is where the PR goes. A fork cloned without one has
# only origin, and outcomes.sh asks GitHub for its parent.
remote() { git "$@" remote get-url upstream 2>/dev/null || git "$@" remote get-url origin 2>/dev/null; }

measure() {  # measure <transcript> <agent type> <the hook's cwd, or "">
  local f="$1" type="$2" row cwd gitdir branch="" ledger="" url
  [ -s "$f" ] || return 0
  case "$type" in
    houseguest:*) ;;
    *) head -n 1 "$f" | grep -q 'oss-pr' || return 0 ;;
  esac
  # Claude Code writes one line per content block, so a request's usage repeats: count each
  # message id once. The ledger match runs from the first path on its line to the first
  # .git/houseguest/<branch>, with any ledger file after the branch cut off.
  row=$(jq -c 'select(.type == "user" or .type == "assistant") | {type, timestamp, cwd, gitBranch, sessionId, agentId,
        id: .message.id, model: .message.model, usage: .message.usage,
        prompt: (.message.content | if type == "string" then . else "" end),
        tools: [.message.content[]? | objects | select(.type == "tool_use") | .id]}' "$f" 2>/dev/null \
    | jq -s -c --arg type "$type" --arg cwd "$3" '
      .[0] as $launch
      | ({"intent-check": "intent", "maintainer-review": "review", "final-check": "final"}) as $ids
      | (if $type | startswith("houseguest:") then $type[11:] | ($ids[.] // .)
         else [$launch.prompt[0:400] | match("[Pp]hases? ([0-7])").captures[0].string][0]
           | if . then ["intent", "recon", "style", "write", "proof", "copy", "review", "final"][tonumber] else "unknown" end
         end) as $phase
      | (map(select(.usage != null)) | group_by(.id) | map(.[-1])) as $requests
      | {v: 1, agent: $launch.agentId, type: $type, phase: $phase, session: $launch.sessionId,
         cwd: ($launch.cwd // $cwd), branch: $launch.gitBranch,
         ledger: ([$launch.prompt
           | match("(?:^|[\\s\\x60\"\\x27(:=])(/[^\\x60\"\\x27<>\\n]*?/\\.git(?:/worktrees/[^/\\s]+)?)/houseguest/([A-Za-z0-9._/-]+)").captures
           | {git: .[0].string, branch: (.[1].string | sub("[./]+$"; "") | sub("/[^/]+\\.[A-Za-z]+$"; ""))}][0]),
         start: .[0].timestamp, end: .[-1].timestamp,
         requests: ($requests | length), tools: (map(.tools[]) | unique | length),
         tokens: ($requests | group_by(.model) | map({key: .[0].model, value: {
           in: (map(.usage.input_tokens) | add), out: (map(.usage.output_tokens) | add),
           cache_read: (map(.usage.cache_read_input_tokens) | add),
           cache_write: (map(.usage.cache_creation_input_tokens) | add)}}) | from_entries)}' 2>/dev/null)
  [ -n "$row" ] || return 0
  cwd=$(jq -r '.cwd // empty' <<<"$row"); gitdir=$(jq -r '.ledger.git // empty' <<<"$row")
  # A match that began at an earlier path on the line: drop leading words until a directory is left.
  while [ -n "$gitdir" ] && [ ! -d "$gitdir" ]; do
    case "$gitdir" in *" /"*) gitdir="/${gitdir#* /}" ;; *) break ;; esac
  done
  if [ -n "$gitdir" ]; then
    branch=$(jq -r '.ledger.branch' <<<"$row"); ledger="$gitdir/houseguest/$branch"
    url=$(remote --git-dir="${gitdir%/worktrees/*}")
  else
    # The transcript's gitBranch is the session's branch when it started, and reads "HEAD" for a
    # session started outside the clone (232 of 803 runs on 2026-11-10), so ask git.
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    url=$(remote -C "$cwd")
  fi
  row=$(jq -c --arg b "$branch" --arg l "$ledger" --arg r "$url" '
    .branch = (if $b != "" then $b elif .branch == "HEAD" then null else .branch end)
    | .ledger = (if $l == "" then null else $l end) | .remote = (if $r == "" then null else $r end)' <<<"$row")
  mkdir -p "$(dirname "$log")" && printf '%s\n' "$row" >> "$log"
}

if [ $# -eq 0 ]; then
  input=$(cat)
  field() { jq -r ".$1 // empty" <<<"$input" 2>/dev/null; }
  measure "$(field agent_transcript_path)" "$(field agent_type)" "$(field cwd)"
  exit 0
fi
for f in "$@"; do
  measure "$f" "$(jq -r '.agentType // empty' "${f%.jsonl}.meta.json" 2>/dev/null)" ""
done
exit 0
