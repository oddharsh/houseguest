# Defaults when the repo is silent

These rules are fallbacks for questions the repo's tooling, written docs, and neighboring code leave unanswered. Anything the repo does differently wins, every time, even when the rule below looks better. They're adapted from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT), rewritten for a contributor working in someone else's codebase.

These defaults never justify changing code a maintainer wrote or suggested, code outside your diff, or a working idiom the file already uses. They only decide questions that nothing else answers.

pstack was written for people shaping their own code, so it pushes hard on restructuring. A guest can't do that. Every rule here applies only to lines your diff already adds or changes; code outside that fence stays as you found it. `deslop.md` covers casts, mock-only tests, narrating comments, and defensive slop, so this file skips what it already says.

## Comments

- **Match the comment density and voice of the file you're editing.**
  Why: a maintainer reads your diff next to its neighbors, so a lone heavily commented function in a terse file looks foreign.
- **Comment when the code bends around something you can't change: a vendor quirk, platform bug, protocol rule, or external API.**
  Why: the reader can't recover that fact from the code, and it's the most common comment worth keeping.
  Good: `// iOS Safari fires blur before click; see https://bugs.webkit.org/show_bug.cgi?id=<n>`
- **Link the issue, RFC, or spec when a constraint can't be expressed in code.**
  Why: a link lets the maintainer verify the claim, and it stays accurate longer than a paraphrase.
- **When your own new code needs a comment to explain a surprise, reshape the code instead.**
  Why: rename, extract, or type the thing so the surprise disappears; the comment would only defend it.
  Bad: `n := 3 // number of retries` Good: `maxRetries := 3`
- **Keep license headers, public API doc comments, and formatter directives the repo already uses.**
  Why: these carry contracts or tooling behavior, so they're the standing exceptions to "fewer comments."
- **Encode a constraint in a test or type before writing a warning comment.**
  Why: `// IMPORTANT: do not reorder` gets ignored, while a failing test can't be.
- **Don't add a lint or type suppression to get CI green.**
  Why: when the rule catches real bugs, the suppression hides one; fix the code or ask the maintainer.
  Covers `eslint-disable`, `@ts-ignore`, `# type: ignore`, `# noqa`, `#[allow(...)]`, `//nolint`, Swift `// swiftlint:disable`.
- **Scope any suppression you can't avoid to one line, and name the reason.**
  Why: a file-wide disable silently covers code written later by someone who never saw it.
- **Leave existing comments outside your diff alone, even ones that break these rules.**
  Why: comment cleanup in someone else's file is a drive-by change the PR didn't ask for.

## Naming and reader load

pstack measures maintainability by reader load: how many layers a reader traces and how much state they hold in their head. Apply it to what you add, never as license to flatten what's there.

- **Use the word the codebase already uses for a concept, and keep using it.**
  Why: a second name for the same thing makes readers wonder whether it's a second thing.
  Bad: a new `fetchAccount` beside the existing `loadUser`.
- **Name a value for its meaning in the domain.**
  Why: names like `data`, `info`, `result2`, or `tmpMap` push the meaning back onto the reader.
- **Don't add a wrapper, adapter, or helper with one caller.**
  Why: each layer is one more hop between a reader's question and the answer.
  Bad: `def get_config(): return load_config()`
- **Don't add a layer that forwards the same arguments to a function with the same shape.**
  Why: a pass-through hides nothing, so it costs a hop and buys no clarity.
- **Prefer locals and return values over new fields, module state, or globals.**
  Why: mutable state the reader must track is the second half of reader load, independent of layer count.
- **Derive a value instead of storing a second copy that must stay in sync.**
  Why: two sources of truth drift the first time someone updates only one.
  Bad: `is_done` and `done_at` both stored. Good: `is_done = done_at is not None`.
- **Search for an existing helper before writing one.**
  Why: two ways to do one task means future contributors copy whichever they find first.
- **Make arguments hard to swap when two share a type and mean different things.**
  Why: `move(src, dst)` with two strings compiles either way round.
  Per language: options object in TS/JS, keyword-only args in Python, a params struct in Go, Rust, or Zig. Swift labels already do this. Skip on hot paths, and follow the repo's call style first.
- **Don't add parameters, flags, or config for cases nobody asked for.**
  Why: speculative options are surface a maintainer must now support forever.

A quick test for anything you add: can a new reader answer "where does X come from?" and "what can change X?" in under 30 seconds?

## Types and boundaries

These generalize across typed languages. For new types and functions your change introduces, apply them. For existing types, follow their current shape even when it's looser.

- **Model mutually exclusive states as one sum type.**
  Why: a bag of optional fields lets contradictory combinations compile.
  Bad: `{ done: bool, doneAt?: Date }` Good: `Open | Done(at)`.
  Per language: TS discriminated union, Rust or Swift enum with payloads, Zig tagged union, Python union of dataclasses with `match`. Go has no sum types, so follow the repo's idiom.
- **Parse external data once, at the boundary, into a typed value.**
  Why: code inside the boundary can then trust the type and skip re-checking.
  Boundaries: JSON, RPC payloads, CLI args, env vars, config files, DB rows, IPC.
- **Use the parsing or schema tool the repo already trusts.**
  Why: serde, pydantic, Codable, zod, or Go struct tags already own validation there; don't bolt on a second one.
- **Inside the boundary, don't re-validate data the boundary already checked.**
  Why: redundant nil checks deep in a call chain give false safety and hide where the real guarantee lives.
- **Don't assert a fact the compiler can't prove unless a check right before it proves it.**
  Why: each unchecked claim is a crash the compiler can't warn about.
  Covers TS `as` and `!`, Swift `!` and `as!`, Rust `.unwrap()` in library code, Go `v.(T)` without `, ok`, Python `cast()`, Zig `.?` and `@ptrCast`.
- **Match every variant so a new variant breaks the build.**
  Why: the compiler then points the next contributor at every place that needs a new case.
  Per language: Rust `match` and Swift `switch` without a catch-all, Zig `switch` without `else`, Python `assert_never`, TS `never` check. Go needs a linter like `exhaustive`; use it only if the repo does.
- **Derive types from the file that owns the shape: protobuf, OpenAPI, GraphQL, or a migration.**
  Why: a hand-copied type drifts the first time the schema changes.
- **Strengthen a type only where your code would otherwise need an assertion or a "can't happen" panic.**
  Why: the panic marks where the type is too weak; elsewhere, extra precision only adds reader load.
  Example: `sum([])` is 0, so a plain list is fine. `first()` has no answer for empty input, so it wants a non-empty type or an optional result.
- **Give semantic primitives their own type in new code when a mix-up is a real risk.**
  Why: `UserId` and `OrderId` are both strings, and a swap compiles silently.
  Per language: Rust `struct UserId(String)`, Go `type UserID string`, Python `NewType`, Swift wrapper struct, TS brand. Skip it when the repo passes raw primitives.
- **Keep decision logic in plain functions and the I/O or framework glue thin.**
  Why: logic without framework dependencies can be tested without the framework.

### TypeScript specifics

These are TS-only. Most also apply to JS projects that typecheck with JSDoc.

- **Type external data as `unknown`, then narrow it.** Why: `any` turns off checking for everything it touches.
- **Use `satisfies` where you'd reach for `as` on a literal.** Why: it checks the value without widening `"dark"` to `string`.
  Bad: `{ theme: "dark" } as Config` Good: `{ theme: "dark" } satisfies Config`
- **Narrow in this order: discriminant check, `in`, `typeof` or `instanceof`, a type guard, then `as` after validation.** Why: earlier options let the compiler verify the narrowing.
- **Make a type guard check everything its name claims, and name it `isX` or `hasX`.** Why: a lying guard is worse than `as`, because the name says it's safe.
- **Add a `const _exhaustive: never = x;` default arm to switches over a union.** Why: TS won't flag a missing case otherwise.
- **Infer types from the repo's existing schema, like `z.infer<typeof UserSchema>`.** Why: one schema then owns both validation and the type. Don't add zod for one guard.
- **Reach for `Pick`, `Omit`, `ReturnType`, `Parameters`, `Awaited`, and `typeof` before declaring a new interface.** Why: derived types follow their source when it changes.
- **If the repo already brands IDs, match its exact brand shape.** Why: a second branding convention is a second way to do one task.

## Tests

- **Call the code the way its users do, and assert the exact result they'd see.**
  Why: a test that would still pass if every function returned `undefined` proves nothing.
  Bad: `assert result is not None` Good: `assert parse_date("2026-10-13") == date(2026, 10, 13)`
- **Avoid loose assertions: truthy, defined, not-throws, greater-than-zero, or called-at-all.**
  Why: they pass on wrong values, so they can't catch the regression you're guarding against.
- **Write the expected value as a literal.**
  Why: an expected value computed by the code under test agrees with any bug in it.
- **Pair an absence assertion with a presence assertion on another input.**
  Why: "nothing came back" also passes when the code is broken for every input.
- **For a bug fix, add a test that fails before the fix and passes after, when the repo has a cheap test path near the bug.**
  Why: maintainers trust a fix they can watch fail first; `proof.md` records both runs.
- **When the neighboring tests state properties, snapshot output, or test types, test your fix the same way, beside one literal case.**
  Why: the literal case shows the bug, and the property, snapshot, or type test states the rule, so the next change that breaks it fails loudly. `checks.md` lists what the repo keeps near your files. Never add the framework.
- **Skip the new test when it needs heavy harness setup, brittle mocks, or big fixture churn.**
  Why: pstack's rule fits here: "Prefer no new test over a bad test." Describe the closest real check in the PR instead.
- **Run real code instead of mocking it when it runs locally.**
  Why: a mock tests your guess about the dependency, and the guess is usually what's wrong.
  Mock what you can't run: the network, clocks, paid services.
- **Don't weaken or rewrite an existing assertion to make your change pass.**
  Why: unless the behavior is meant to change, and the PR says so, a changed assertion is a hidden regression.
- **Verify the real artifact before calling it done: run the feature or read the actual output.**
  Why: "it compiles" and "the tests pass" are proxies; the bug report described real behavior.

## Scope of a contribution

pstack tells owners to leave the design simpler than they found it and to hunt for bold restructurings. In a guest repo, the diff is the fence, and those instincts shrink to fit inside it.

- **Change only the lines the fix or feature needs.**
  Why: every unrelated line costs the maintainer review time and raises merge-conflict risk.
- **Refactor only inside lines your diff already touches, and only when it makes your change smaller or clearer.**
  Why: restructuring someone else's module is a design decision that belongs to them.
- **Subtract before you add, inside the fence.**
  Why: if your fix leaves a branch, helper, or import dead in code you touched, delete it so nobody has to prove it's dead later.
- **Don't add guards, validators, options, or compatibility paths beyond what the issue needs.**
  Why: speculative code is code the maintainer must now read, test, and keep.
- **Fix the bug where it starts.**
  Why: a null check that silences a crash leaves the real bug in place and adds a guard someone must later explain.
  Bad: `if user is None: return` Good: find why the caller passes `None`, and fix the caller.
- **Reproduce first, then keep asking "why" until you reach the cause.**
  Why: a fix chosen before reproducing usually treats the symptom you happened to see.
- **Ship only lines that trace to evidence.**
  Why: a "might help" change is a hypothesis; when a run disproves it, revert what it motivated.
- **When the root cause sits outside a reasonable scope, land the smallest correct fix and name the root cause in the PR.**
  Why: a public API change or a fix in another module is the maintainer's call; ask before widening.
- **Fix the same bug pattern only where your change already reaches; list other instances in the PR.**
  Why: pstack says fix every instance, but a repo-wide sweep turns a small fix into an unreviewable one.
- **Don't introduce a second way to do something the repo already does.**
  Why: the next contributor copies whichever way they find first, so both keep spreading.
- **Don't split, move, or reorganize files to make room for your change.**
  Why: moves wreck `git blame` and conflict with open PRs; if a file is getting too big, say so in the PR.
- **Don't add a dependency for something the repo or standard library already does.**
  Why: every dependency is a supply-chain and upgrade cost the maintainer inherits.
- **Keep one PR to one change, and propose a useful refactor separately.**
  Why: small PRs are easier to review and revert, and an unrequested refactor sinks the fix riding with it.

## Error handling

- **Validate input and handle errors at the boundary, then propagate them inside.**
  Why: when handling is scattered, nobody can tell where the guarantee actually lives.
- **Never swallow an error.**
  Why: the failure resurfaces later, somewhere further from its cause.
  Bad: `except Exception: pass`, `_ = err`, `catch {}`, `let _ = fallible();`
- **Wrap errors with context in the repo's style.**
  Why: "file not found" with no path or operation sends the next debugger hunting.
  Per language: Go `fmt.Errorf("load config: %w", err)`, Rust `?` with the repo's context crate, Python `raise ... from err`, Zig error unions with `try`, Swift `throws`.
- **Don't add a try/catch, retry, or null check to quiet a failure you haven't explained.**
  Why: it hides a broken contract and leaves the real bug for the next person.
- **Define an error case out of existence when a total function or a stronger input type can do it.**
  Why: an error that can't happen needs no handler, test, or docs.
- **Make an operation safe to rerun when it can be retried or interrupted halfway.**
  Why: "it depends on what state was left behind" means a reconciliation step is missing.
- **Log through the repo's logger, at its usual level, with enough context to debug from an ID.**
  Why: stray `print`, `console.log`, or `dbg!` lines read as debugging residue in a PR.
- **Keep secrets and tokens out of logs and error messages.**
  Why: logs get pasted into public issues, and that's where credentials leak.

## Where this conflicts with a repo

These pstack defaults clash most often with real projects. In each case, the repo wins, and the conflict goes in `style.md` under "Deslop conflicts."

- **Heavy commenting.** Some repos require doc comments on every public item, or comment in long paragraphs. Match their density and format.
- **`any`, `interface{}`, `Any`, or casts at boundaries.** Plenty of repos skip a schema layer and cast parsed JSON directly. Follow the local idiom rather than adding a parser.
- **Pervasive mocking.** If neighboring tests use `jest.mock`, `unittest.mock`, or gomock everywhere, write yours the same way.
- **Defensive checks everywhere.** Some codebases re-check inputs at every layer on purpose. Match it in the code you touch.
- **Layered architecture.** Service, repository, and adapter layers with one implementation each are convention in some projects. Add your code in the matching layer.
- **Optional-field structs and boolean flags.** If the module models state with optionals, extend that shape instead of introducing a sum type for one new case.

## Attribution

Adapted from pstack by Lauren Tan, MIT License, https://github.com/cursor/plugins/tree/main/pstack

```
MIT License

Copyright (c) 2026 Lauren Tan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
