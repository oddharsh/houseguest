# Craft: what's left for the person when code is cheap

In late 2026, Anthropic, Amazon, and Jane Street each published what they now hire or promote engineers for. They agree on a short list, and typing code isn't on it. This page names each skill, the source that names it, the houseguest phase where you practice it, and the evidence it leaves in the ledger for `practice.sh` to count.

houseguest grades each contribution on its own. This page is for the contributor, across jobs.

## The sources

| Source | What it says changed |
|---|---|
| Anthropic, [How employment is changing at Anthropic](https://anthropic.com/research/employment-at-anthropic) (2026-10-16) | Junior technical hires fell from 27% to 9% of technical hires. By August, interactive agent hours outnumbered employee hours 6 to 1, which "makes human attention the bottleneck for agent output." Hiring managers emphasize "autonomy and judgment, relative to technical domain expertise and implementation" |
| Amazon, [the role of the developer in the age of AI](https://aboutamazon.com/news/company-news/amazon-software-engineer-role-guideline-ai) (2026-10-27) | The role guideline describes outcomes, since good AI practice changes too fast to write down. Token counts and lines of code are input metrics: "tokenmaxxing is at odds with frugality." Leaders watch the 10th and 90th percentile of adoption. "If your work does not benefit from current AI tooling, that is a finding, not a failing" |
| Jane Street, [Our software engineering interviews are changing (a little)](https://blog.janestreet.com/software-engineering-interviews-are-changing-a-little) (2026-11-12) | New onsite rounds for campus candidates test "taste about what to build, choosing abstractions that last, and making sure what got built is actually correct." Candidates don't need a worked-out agent method; they need to think clearly about what a tool is good at and when to reach for something else |
| Signals and Threads, [The Changing Craft of Programming](https://signalsandthreads.com/the-changing-craft-of-programming) (Ron Minsky with John Crepezzi) | Verification is now the hard part, because code an agent wrote fails in ways a person would not. Slop breaks code review's social contract, so a plausible feature from a prompt gets treated as a prototype and discussed on its merits. Prototypes thrown away count as real work |
| Felix Rieseberg, [Hunger beats tenure](https://felixrieseberg.com/hunger-beats-tenure-advice-for-junior-engineers) (2026-10-27) | An Anthropic hiring manager dropped the coding interview, since Claude does the test tasks better. He looks for small prototypes that show taste, empathy, and principled thinking, and for engineers who pick business impact over the backlog |
| Steve Ruiz, ["find all of the implicit state machines in my app"](https://x.com/steveruizok/status/2116552016218710389) (2026-10-31) | One prompt that finds a whole bug class by meaning. A grep can't find it. Ruiz runs it "so that I can make them explicit, tends to find conflicts." `sweeps.md` turns prompts of this shape into a catalog |
| Georgios Konstantopoulos, [Effective Swarm Riding for Engineers](https://paradigm.xyz/writing/swarms) (2026-11-20) | Be unreasonably ambitious, name a metric for the agent to climb ("make this 10x faster"), and invest in the environment more than the agent. Its section on deleting comments, docs, skills, unit tests, and CI is the part houseguest disagrees with (below) |

## The skills

### Choosing what to build

Jane Street calls it taste, and Rieseberg looks for it in prototypes. In a houseguest job you practice it at recon, when the job ends in GO, DOCS, JOIN, ASK, or STOP. Saying no to a job costs nothing, while a duplicate PR costs a maintainer's afternoon.

- **Practice:** read `recon.md`'s reason before approving GO, and ask whether a maintainer would want this change at all.
- **Evidence:** the `RECON` column. A run of all-GO jobs means one of two things: you pick well, or recon has stopped biting. Read the last 3 reasons to tell which.

### Verifying what got built

Signals and Threads and Jane Street both put this at the top. Reviewing code an agent wrote means doing the authoring work in review, since the agent's mistakes don't look like a person's.

- **Practice:** the maintainer review and its finding checks. Before you accept or decline an Important finding, read the code it cites yourself. When the finding check refutes one, note whether you had already doubted it.
- **Evidence:** `IMP` and `REFUTED`, from `rounds.md`. Many refuted findings mean the reviewer is noisy; that tells you about the reviewer, and nothing about you. Your evidence is the `caught` lines below.

### Steering the agent

Anthropic's hiring managers want autonomy and judgment. In a job, judgment shows up as the decisions you made where the agent would have gone another way: scoping the PR, rejecting a spec, asking for the size check.

- **Practice:** when a phase proposes something, decide it, and let `decisions.md` say you decided it ("because the user scoped the PR to AVIF").
- **Evidence:** `STEERED` counts `decisions.md` lines that name you, and `REVERSED` counts decisions a later one reversed. A run of jobs where no decision names you means the agent decided everything, and `practice.sh` flags it.

### Knowing where AI doesn't help

Amazon calls this a finding. It's also the skill Jane Street tests: knowing what a tool is good at and when to reach for something else.

- **Practice:** when the agent burned a round on something a profiler, a debugger, `git bisect`, or 10 minutes of your own reading would have settled, write it down.
- **Evidence:** `no-help` lines in `judgment.md`.

### Throwing work away

Signals and Threads counts a discarded prototype as real work. A direction you tried and backed out of is knowledge the next job can use, and a reviewer can use it too (move 4 in `pr-copy.md` names one alternative you passed on).

- **Evidence:** `thrown` lines in `judgment.md`, and `REVERSED`.

### Measuring outcomes

Amazon's guideline measures outcomes, and Konstantopoulos's prompts give the agent a number to climb toward. In houseguest the outcome is a merged PR, and `outcomes.sh` prints output tokens per merged PR. Read that number, not total tokens.

- **Practice:** run `outcomes.sh` when you check your practice. A job in the top 10% of token spend that didn't merge is Amazon's 90th-percentile question: heavy use, and did delivery follow?

## judgment.md

Most of what `practice.sh` counts, the ledger already records. Three things it can't see, so you write them, one line each, in `$LEDGER/judgment.md`:

```
- caught: <what the agent got wrong> | <how you saw it>
- no-help: <where the agent didn't help> | <what did>
- thrown: <what you built and dropped> | <why>
```

For example:

```
- caught: the fix guarded the null at the caller | read the 3 other callers, all pass the same field
- no-help: 2 rounds guessing at the hang | sample(1) on the stuck process named the lock in 30 seconds
- thrown: a cache in front of the box parser | hyperfine showed 0.4 ms of 31 ms; shipped without it
```

The words are yours. The agent may draft a line from `rounds.md` or `decisions.md`, but it goes in only once you say it's true, because a log of judgment the agent wrote for you trains nothing. A job with nothing to record gets no file, and that's fine on its own. `practice.sh` flags it when half of the recent finished jobs have none.

## Where houseguest disagrees with a source

The swarm-riding piece says to delete comments, `docs/`, and skills folders, ban agent-written unit tests, and push to master without CI. houseguest takes the ambition, the sweep prompts, deterministic simulation tests, and its point about investing in the environment, and leaves that section alone:

- **Docs are the oracle.** The intent check decides whether a behavior is deliberate by reading the repo's docs, tests, and history. Delete them and an agent can't tell a feature from a bug, and it acts on that guess at scale. Anthropic's report shows written standing instructions growing, which points the other way.
- **A guest can't push to someone's master.** In someone else's repo, CI and review are the house rules (`SKILL.md`, precedence).
- **Tests stay, with a bar.** `proof.md` drops loose and mock-only tests and keeps tests that fail on the base for the reported reason. That bar removes the tests the piece objects to, without banning the ones that catch regressions.

## Limits

- `practice.sh` reads oss-pr ledgers. Work in your own repos leaves no ledger, so it doesn't show up here.
- The counts come from text patterns in notes that agents and people write. Treat a number as a prompt to read the ledger, never as a score.
- Every source here dates from October or November 2026, and 3 of them describe one employer's hiring. Recheck them in a year.
