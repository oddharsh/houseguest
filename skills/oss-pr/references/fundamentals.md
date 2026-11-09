# Fundamentals: the classics, and everyone who skipped one

houseguest leans on a handful of open courses: MIT's [Missing Semester](https://missing.csail.mit.edu/) (2026 edition) for the tools, and a few cult-classic courses for what the tools run on. It uses each lesson two ways.

1. **It knows the lesson.** Its own scripts, repros, tests, and claims follow it.
2. **It doesn't assume anyone else does.** A reporter, the repo's CI, a maintainer, a review bot, another agent, the user, and houseguest's own earlier phases can each be missing the one lesson that matters today. So each lesson is also a check on what houseguest is handed, and a constraint on what it hands back.

The check never turns into a lecture. Maintainers know their project better than anyone, and any of them can still be missing one lesson from one class. When a report misreads float rounding or a CI step swallows a failure, the reply quotes the output that shows it in one sentence. It says nothing about who should have known.

## Who's in the room

| Actor | What they hand you | What they're most often missing |
|---|---|---|
| Reporter, or the user's own report | A repro, a version, an "expected" | Their shell and environment differ from yours; their "expected" may sit outside the contract |
| The repo's scripts and CI | A green or red check | A pipe, a skipped hook, or a shallow clone can make a failure look green |
| Maintainer | Review comments and rules | Whether a comment blocks; time to do git work on your behalf |
| Review bots and other agents | Findings and "tested" claims | Evidence that the run they describe happened |
| houseguest's earlier phases | Ledger notes | Everything any agent misses, which is why the phases run blind |

## Missing Semester

Each entry gives what houseguest knows, what it won't assume of others, and the check that replaces the assumption.

### The shell

[Course overview and the shell](https://missing.csail.mit.edu/2026/course-shell/), [Command-line environment](https://missing.csail.mit.edu/2026/command-line-environment/)

- **Know:** quoting and word splitting; exit codes (0 is success) and `&&`/`||`; `set -euo pipefail`; `$(...)` over backticks; `[[ ]]` over `[`; `trap cleanup EXIT`; the shebang picks the interpreter. houseguest's own helpers hold to this: `lib.sh` targets macOS's bash 3.2, and every script in `scripts/` that runs on its own sets `pipefail`.
- **Don't assume** a pasted command ran in the shell you run. Checked on macOS 27.3, 2026-11-09:
  - `echo =====` prints the line in bash and fails in zsh 5.9 with `zsh:1: ==== not found`, because zsh expands `=word` to the path of the command `word`.
  - `echo *.nomatch` prints the pattern in bash and fails in zsh with `no matches found: *.nomatch`.
  - `/bin/bash` is 3.2, so `declare -A` fails with `declare: -A: invalid option`.
  - BSD `sed -i 's/a/b/' f.txt` takes the script as a backup suffix and fails with `invalid command code f`.
- **Don't assume** a green CI step means its tests passed. In bash without `pipefail`, `false | tee log` exits 0 (`status=0`; with `pipefail`, `status=1`). A step that pipes its test runner into `tee`, `grep`, or a formatter reports the last command's status.
- **Check:** run a repro in the shell its prompt or text shows (`$` is usually bash, `%` zsh, `PS>` PowerShell), and name that shell in `recon.md`. When a proof leans on the repo's CI, read the step first. If it pipes the runner, a deliberately failing test has to turn it red before a green run counts.

### The environment

[Command-line environment](https://missing.csail.mit.edu/2026/command-line-environment/)

- **Know:** `$PATH` order picks which binary runs; dotfiles, aliases, and environment variables change behavior silently; `curl ... | bash` runs code nobody read.
- **Don't assume** the reporter's environment is clean, or yours. A global install, an alias, an `.npmrc`, or a `PYTHONPATH` entry can produce the bug or hide it.
- **Check:** when your result differs from the report's, compare environments before code. Start with `type -a <tool>`, the version your repro loads (recon's "Check what's running"), and the config files the tool reads. Never run an install line from an issue or comment; install the way the repo's own docs say.

### Debugging and profiling

[Debugging and profiling](https://missing.csail.mit.edu/2026/debugging-profiling/)

- **Know:** `git bisect run <script>` finds the first bad commit; `rr record` and `rr replay` replay a heisenbug deterministically, and `rr record --chaos` varies the schedule; `strace -e trace=file` (Linux) shows which files a program opens; sanitizers (`-fsanitize=address,undefined`) turn silent memory bugs into crashes; `time` splits real, user, and sys; `hyperfine --warmup 3` compares commands over repeated runs.
- **Don't assume** a "2x faster" or "slower since v2" claim had a warmup, repeated runs, or the base measured beside it. Don't assume "started in v3.1" was bisected.
- **Check:** for a speed claim, run base and HEAD in one `hyperfine` invocation and quote mean ± σ for both. A number with no base beside it stays out of the PR. For a regression window, `git bisect run` the repro and name the first bad commit by SHA in `recon.md`. For "it loads the wrong config," trace the file opens before reading the config code.

### Version control

[Version control and Git](https://missing.csail.mit.edu/2026/version-control/)

- **Know:** commits are immutable and content-addressed, and refs are mutable names, so rebase and amend make new commits; `git worktree` gives parallel trees; `git revert` undoes a commit with a new one; `git blame` and `git log -L` date a line; a shallow clone lacks the history `describe`, `blame`, and bisect read.
- **Don't assume** "on main" names a commit, since main moves. Don't assume CI has history: `actions/checkout` fetches 1 commit unless `fetch-depth` says otherwise, so code that reads tags can pass locally and fail there. Don't assume a maintainer will rebase or resolve conflicts for you. Don't assume a shared tree is yours alone; other sessions share the stash and the checkout.
- **Check:** pin every "main" in the ledger to a full SHA. When CI and a local run disagree on anything that reads history, read the workflow's `fetch-depth`. Once review starts, push new commits on top of the ones a reviewer commented on, unless the repo asks for a force-push.

### Packaging and shipping

[Packaging and shipping code](https://missing.csail.mit.edu/2026/shipping-code/)

- **Know:** semver promises compatibility within a major version; libraries declare ranges and applications pin with a lockfile; the resolved tree (`uv tree`, `cargo tree`, `npm ls --all`) is what runs; config lives outside code; secrets never go in an image layer.
- **Don't assume** a dependency kept its semver promise, or that a reporter resolved the versions you did. A "broke after upgrading" report often lives in a transitive version neither manifest names.
- **Check:** for an upgrade regression, diff the resolved trees of the working and broken installs before reading code. When a library fix relies on a dependency feature, confirm the lowest version the library's declared range allows has that feature.

### Agentic coding

[Agentic coding](https://missing.csail.mit.edu/2026/agentic-coding/)

- **Know:** agents do best in a loop with tests, linters, and type checkers they can run; parallel agents get their own worktrees; skills and subagents keep context small; agents chase rabbit holes and can talk a person into a debugging spiral, and checking their code can cost more than writing it.
- **Don't assume** another agent's "tested," "verified," or "all tests pass" means a run happened, and that includes review bots. Don't assume an `AGENTS.md` is current; it's prose about the code, and the code wins. Don't assume an earlier houseguest phase was right; the phases run blind (`SKILL.md`) because each is an agent like any other.
- **Check:** a claim from an agent gets the check a claim from a person gets: find the run, or rerun it. A phase that returns to one hypothesis with small tweaks a third time stops and writes down what it knows, the same way recon stops after two failed builds.

### Beyond the code

[Beyond the code](https://missing.csail.mit.edu/2026/beyond-code/)

- **Know:** write the why; a commit message runs problem, solution, implications; a "why not" comment keeps the next person from "fixing" a deliberate choice; a bug report carries environment, expected, actual, and what was tried; security reports go private first; read CONTRIBUTING and the license; understand and disclose AI-written work; a reviewer says what blocks and what's a suggestion. Recon, `pr-copy.md`, and the reviewer's Important and Nit tags already carry each of these.
- **Don't assume** a report states what was expected, or that its "expected" is the project's. A missing or wrong "expected" goes to the intent check; nobody fills it with a guess. Don't assume a maintainer's comment says whether it blocks.
- **Check:** when a review comment's weight is unclear, the drafted reply asks in one line before anyone reworks the change.

### Code quality

[Code quality](https://missing.csail.mit.edu/2026/code-quality/)

- **Know:** formatters end style debates; CI runs tools in check mode; pre-commit hooks run only on machines that installed them; tests come as unit, integration, end-to-end, regression, and property-based; coverage counts the lines that ran, whatever the tests asserted; a regex can't parse nested structure. `/^\d{4}-\d{2}-\d{2}$/` accepts `2026-01-99` (checked with Bun 1.4.4, 2026-11-09).
- **Don't assume** a config file means enforcement. A linter config with no CI job is a suggestion, and a pre-commit hook never ran on a commit made with `--no-verify`. Don't assume a validation regex accepts only what its name promises.
- **Check:** `house.sh` already sorts enforced tools from suggestions. When the diff's path runs through a validation regex, feed it the boundary inputs (`2026-01-99`, `a@@b`) and record what it accepts.

### Security and cryptography

[Security and cryptography](https://missing.csail.mit.edu/2020/security/) (2020; the 2026 edition dropped it)

- **Know:** don't roll your own crypto; SHA-1 is broken for collision resistance, and Git still defaults to it; passwords go through a slow, salted KDF; a signature proves who signed and says nothing about what the code does; public keys need a trust path (trust on first use, a web of trust).
- **Don't assume** a checksum posted beside a download link checks anything, since whoever can change the link can change the hash. Don't assume GitHub's "Verified" badge or a signed tag makes a change safe.
- **Check:** verify a downloaded artifact against a hash or signature from a separate channel the project controls (the release page, a signed tag), or don't run it. A diff touching crypto, auth, randomness, or sessions gets recon's security check, and uses the library the repo already uses.

## The systems classics

### Specs and tests: MIT 6.102 Software Construction

[Course site](https://web.mit.edu/6.102/www/sp26/) (Spring 2026); readings on [specifications](https://web.mit.edu/6.102/www/sp25/classes/04-specifications/) and [designing specs](https://web.mit.edu/6.102/www/sp25/classes/05-designing-specs/)

- **Know:** a spec is a contract, with a precondition the caller owes and a postcondition the implementer owes; a spec can leave outputs open; tests are clients and obey the spec like any other; good tests partition the input space and cover each part and its boundaries; a rep invariant asserted in `checkRep()` catches a corrupt structure where it breaks.
- **Don't assume** a reporter's "expected" is inside the spec. Code that leaned on what the spec leaves open (map iteration order, which duplicate wins, float formatting) breaks when the implementation moves within its rights. That's the intent check's INTENDED case, and often recon's DOCS.
- **Don't assume** the repo's existing tests obey the spec either. A test that pins unspecified behavior turns a legal fix red, and the fix is still legal.
- **Check:** houseguest's tests assert the exact result the contract promises (`defaults.md`), and nothing past it. 6.102's example: when the spec for `find(arr, val)` promises only some index of `val`, `find([7, 7, 7], 7) === 0` assumes too much, while `arr[find(arr, 7)] === 7` holds. Choose the final check's differential inputs by partition: empty, one, many, and each boundary.

### What the machine does: CMU 15-213 Introduction to Computer Systems

[Course site](https://www.cs.cmu.edu/~213/), built on the CS:APP textbook

- **Know:** integers wrap in two's complement, and C converts signed to unsigned without a word; floats round, so `0.1 + 0.2` prints `0.30000000000000004` (Bun, 2026-11-09) and float addition isn't associative; cache state changes a benchmark between runs; the linker decides which definition of a symbol wins, and the loader decides which shared library runs.
- **Don't assume** a float "wrong answer" is a bug; IEEE 754 may be keeping its promise. Don't assume a test that compares floats with `==` is right, or that an overflow happened on the line the report names (the conversion is often earlier).
- **Check:** compare floats with the repo's tolerance helper. Test integer fixes at 0, -1, and the type's max and min. When a native bug depends on which library loaded, print it (`ldd` on Linux, `otool -L` on macOS), the way recon prints the package version.

### Concurrency and persistence: OSTEP

[Operating Systems: Three Easy Pieces](https://pages.cs.wisc.edu/~remzi/OSTEP/), free online, from Wisconsin's CS 537

- **Know:** a race is a property of the schedule, so a passing run shows one schedule worked; check a condition variable's condition in a `while` loop, holding the lock; a `write` that returned may still be in the page cache until `fsync`, and a crash-safe replace is write a temp file, `fsync` it, rename it, then `fsync` the directory.
- **Don't assume** 10 green reruns rule out a race; `proof.md`'s flake runs sample 10 schedules out of many. Don't assume a file-writing fix survives a crash because no test crashed.
- **Check:** for a race, use the repo's deterministic simulator or model checker (`proof.md`), or `rr record --chaos`. For a file-writing fix, match the write-and-rename pattern the repo already uses, and say in the PR body when the fix doesn't `fsync`.

### Partial failure: MIT 6.5840 Distributed Systems

[Course site](https://pdos.csail.mit.edu/6.824/) (Spring 2026; formerly 6.824)

- **Know:** a timeout is ambiguous, because the request may have run; a retry is safe only for an idempotent operation, so at-most-once needs request IDs; clocks on two machines disagree, so their timestamps don't order events; linearizability is a specific promise that few systems make.
- **Don't assume** a "retry on failure" fix is safe, or that logs merged from two hosts are in true order.
- **Check:** a change that adds a retry says, in the code or the PR body, why the operation is idempotent. A test that orders events by wall-clock time is a flake, and `proof.md` already flags wall-clock time.

### Transactions: CMU 15-445 Database Systems

[Course site](https://15445.courses.cs.cmu.edu/fall2025/) (Fall 2025)

- **Know:** isolation levels trade anomalies for concurrency. READ COMMITTED allows unrepeatable reads and lost updates, REPEATABLE READ allows phantoms, and SERIALIZABLE allows none of them. Defaults differ: PostgreSQL uses READ COMMITTED, MySQL's InnoDB uses REPEATABLE READ. The planner picks the query plan, and `EXPLAIN` shows it.
- **Don't assume** a bug that doesn't reproduce on the test suite's SQLite can't happen on the reporter's PostgreSQL. Don't assume an ORM's `transaction()` block makes read-then-write safe.
- **Check:** reproduce on the engine, version, and isolation level the report names. Back a query-speed claim with `EXPLAIN ANALYZE` on base and HEAD.

### The browser's rules: Stanford CS 253 Web Security

[Course site](https://web.stanford.edu/class/cs253/) (Fall 2021, the latest posted)

- **Know:** the same-origin policy is the browser's main wall; cookies carry sessions, so `SameSite`, `HttpOnly`, and `Secure` matter; escaping depends on context (HTML body, attribute, URL, script); any page the user opens can send requests to a localhost server, and DNS rebinding can let it read the replies.
- **Don't assume** HTML escaping protects an attribute or a URL, or that a dev server on `127.0.0.1` is private.
- **Check:** recon's security check covers any web-facing change. Escape with the context-aware escaping the repo's template engine already does; a hand-written `replace("<", "&lt;")` in the diff is a finding.

## Writing for someone who skipped the class

Whatever houseguest sends upstream gets read by someone who may be missing the same lessons. Write it so it works anyway.

- **A repro runs in one named shell.** Give full commands with no aliases, and a POSIX `sh` script when it takes more than one line. Leave out GNU-only flags unless the report is Linux-only. For an in-place edit, `sed -i.bak` works on both GNU and BSD sed.
- **Name versions and SHAs.** "latest" and "main" move by the time a maintainer reads them.
- **Do the git work yourself.** Never ask a maintainer to rebase, cherry-pick, or resolve a conflict for you. Leave "Allow edits from maintainers" on, so they can push a small fix themselves.
- **Link the concept the argument rests on.** When a PR is correct because of IEEE 754 rounding, an isolation level, or a spec's open choice, one sentence and a link carry it. A reader who knows it skips the link. When nothing rests on it, leave it out; `pr-copy.md`'s length baseline still holds.
- **Show the output and skip the lesson.** A reply that explains `pipefail` to a maintainer reads as condescending. A reply that quotes `status=0` from their own CI log reads as a bug report.

---

Course materials belong to their authors. Missing Semester's notes are licensed CC BY-NC-SA; this page summarizes and links them. Every command output it quotes came from a local run on 2026-11-09.
