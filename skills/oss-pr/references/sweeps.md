# Sweeps: find-and-replace by meaning

A sweep is one prompt that finds every instance of a pattern and rewrites each one. Georgios Konstantopoulos's example: "find all implicit state machines, encode the legal states in the type system, and eliminate the bug class at compile time." He calls these superpowered find-and-replace prompts ([Effective Swarm Riding for Engineers](https://www.paradigm.xyz/writing/swarms), 2026-11-20). A plain grep can't find their targets because the pattern lives in what the code means. An agent can, which makes fixing the whole class nearly as cheap as fixing the instance you noticed.

Phase 3 runs a sweep when its trigger shows up in the change. The review loop runs one whenever an Important finding names a bug class (SKILL.md, "Review rounds"). Every sweep that runs goes in the ledger, so the user can reuse the prompt elsewhere.

## The fence

In someone else's repo, a sweep rewrites only lines inside your diff. Every instance outside it goes in `sweeps.md` as `path:line`. Phase 5 may mention them in one sentence of the body: "The same pattern shows up in 4 other places; happy to send those separately." Never widen the diff to finish a sweep. A repo-wide sweep is a second PR, and only after a maintainer asks for one (`defaults.md`, "Scope of a contribution").

The house rules still come first. If the module models state with optional fields, or the repo builds its regexes inline, follow it (`defaults.md`, "Where this conflicts with a repo"). A sweep that would make your code foreign gets listed and goes unapplied.

## Prompt shape

A sweep prompt that works names 4 things:

1. **The pattern,** precise enough that two agents would flag the same lines.
2. **The replacement,** in the repo's own idiom.
3. **The scope:** a directory, a module, or the diff.
4. **The check that says it's done:** a compile error, a differential run, a benchmark number, a query count.

The check matters most. "Optimize X" has no finish line, while "make X 10x faster, measured by `<bench>`" gives the agent a number to climb toward and a point to stop. An agent can grade its own sweep against a check, so leave it running unattended. When the check is a number, the sweep is a hillclimb: run it step by step per `proof.md`, "Hillclimbing."

## The catalog

Each entry gives the trigger phase 3 watches for, then the prompt with the parts to fill in, then the check.

Each heading is also a handle. "Run the whole-rows sweep on `src/db`" is a complete prompt: find the entry, fill in the scope, and use its check. Konstantopoulos's prompts work the same way, packing a style guide into "using TigerStyle." The user's own prompts depend on these names, so an entry keeps its name once it's in the catalog.

### Implicit state machines

- **Trigger:** two or more booleans or optionals that change together, or code that checks one flag before trusting another field.
- **Prompt:** "Find every implicit state machine in `<scope>`: flags and optional fields that change together. Encode the legal states as one sum type so the illegal combinations stop compiling, and match every variant without a catch-all."
- **Check:** a type test that fails to compile on the base for an illegal state (`proof.md`, "Type tests"), and an exhaustive match the compiler enforces.

### Whole rows for a few fields

- **Trigger:** a query, ORM call, or API fetch that loads a whole row, document, or object, then reads 1 or 2 fields of it.
- **Prompt:** "Find every place in `<scope>` that loads a whole row from the database just to read a couple of fields, and select only the fields it uses."
- **Check:** the query log or the selected column list on base and HEAD, plus the existing tests for each caller.

### Sequential awaits that don't depend on each other

- **Trigger:** 2 or more awaits in a row where no later call uses an earlier result.
- **Prompt:** "Find every run of sequential awaits in `<scope>` whose calls don't depend on each other, and run them concurrently (`Promise.all`, `tokio::join!`, `asyncio.gather`, `errgroup`)."
- **Check:** timing on base and HEAD per `proof.md`, "Performance". Read each call's error and ordering behavior first: concurrent calls fail together, can hit a rate limit together, and can finish out of order.

### Constant work rebuilt on every call

- **Trigger:** a regex, formatter, collator, or lookup table built from constant input inside a function or loop.
- **Prompt:** "Find every regex, formatter, or lookup table in `<scope>` built from a constant inside a function or loop, and build it once at module scope."
- **Check:** the repo's benchmark on the path. `lean.md` asks for a number, so a hoist with no measurable change doesn't ship on its own merits.

### Unbounded loops, queues, and retries

- **Trigger:** a loop over external data, a retry, a queue, or recursion with no fixed limit.
- **Prompt:** "Find every loop over external data, retry, queue, and recursion in `<scope>`. State each one's maximum, and make passing it an error."
- **Check:** a test that feeds one input past the limit and asserts the exact error. From TigerStyle's "put a limit on everything" (`defaults.md`, "Error handling").

### One fact stated in many places

- **Trigger:** the change edits a number, default, version, or limit that docs, tests, or UI copy repeat.
- **Prompt:** "Find every place in `<scope>` that states `<the fact>`. Check each against `<the source of truth>`, fix the stale ones, and derive the copy from the source wherever the code can."
- **Check:** a grep for the old value on HEAD that returns only the lines meant to keep it, with each one named.

### Differential gap-closing

- **Trigger:** a port, rewrite, or speedup.
- **Prompt:** "Differentially test `<new>` against `<old or reference>` over seeded, generated inputs, and close every gap."
- **Check:** the differential run itself (`proof.md`, "Differential runs"), with the input count and seed.

## Recording

Phase 3 appends one entry to `$LEDGER/sweeps.md` per sweep it runs:

```markdown
- Sweep: <catalog name, or NEW: a short name>
  Trigger: <what showed up, path:line>
  Prompt: <the prompt as run, with the scope and the check filled in>
  Inside the diff: <n> rewritten (path:line, ...)
  Outside: <n> listed (path:line, ...)
  Check: <command> -> <result>
```

When a change shows a bug class the catalog doesn't name, run it anyway and mark it `NEW`. Those entries are how the catalog grows.

## Handing them back

When the job ends, whether it's posted, stopped, or parked, show the user each entry in `sweeps.md` as a prompt they can paste. Give the filled-in prompt, what it found, and the check that proved it. Then name the entries marked `NEW`, and offer to add each one to this catalog with its trigger and check. The user gets the reusable prompt, and the next job gets the trigger.
