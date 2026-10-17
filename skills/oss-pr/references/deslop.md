# Deslop, across languages

This is a review pass over your own diff, run after the code works. It sits 4th in the precedence order: if the repo's tooling, docs, or neighboring code does the thing a principle forbids, the repo wins and you skip the principle. Note every skip in `style.md` under "Deslop conflicts," so the decision is visible.

Sections 1 to 3 translate the Oxlint rules in [dmmulroy/anti-slop](https://github.com/dmmulroy/anti-slop) and [maharshi365/deslop](https://github.com/maharshi365/deslop) (TS/JS only) into principles that apply anywhere. The rule names are kept so you can read the originals. Section 4 is additions for patterns agents produce that those linters don't cover.

Only apply a principle to lines your diff adds or changes. Cleaning up pre-existing code is a separate PR nobody asked for.

## 1. Evidence over assertion (types and data)

The idea underneath most of these: a type is a claim about data, and slop fabricates the claim instead of earning it.

| Principle | From | Looks like |
|---|---|---|
| Parse at the boundary, then trust the type. Don't probe types ad hoc deep inside logic. | `no-runtime-typeof` | TS `typeof x === "string"` mid-function; Python `isinstance` chains in business logic; Go `.(type)` switches on data you already parsed. Go type switches over a real sum type and Python duck typing are idiomatic; check the repo. |
| Don't stack casts to force a type. | `no-chained-type-assertions` | TS `as unknown as T`; Rust `as` chains or `transmute`; Go `interface{}` then assert; Python `cast(T, cast(Any, x))`; Java `(T)(Object)x`. |
| Don't widen known data and narrow it back later. | `no-widen-then-assert`, `no-known-value-widening` | Assigning a typed value to `any`/`unknown`/`object`/`interface{}`/`Any`/`anytype`, then casting it back. |
| Give inputs and outputs real types. | `no-unknown-parameters`, `no-unknown-returns`, `no-object-parameters`, `no-unsafe-dictionary-type` | `unknown`, `object`, `Any`, `dict[str, Any]`, `map[string]interface{}`, `Map<String, Object>` where a concrete type exists. |
| Justify every unavoidable cast or unsafe block in a comment next to it. | `require-safety-comment-for-type-assertion` | Rust's `// SAFETY:` convention is the model. Use whatever marker the repo already uses. |
| Don't add aliases that only rename a type. | `no-pass-through-type-alias`, `no-unknown-type-aliases` | `type UserId = string` used once; `typealias Foo = Bar`. Fine when the repo uses aliases as documentation. |
| Don't duplicate constants or types that already exist. | `no-duplicate-consts`, `no-duplicate-types` | A second `MAX_RETRIES = 3`; a struct identical to one in another module. Search before defining. |
| Use direct access, not reflection, when the name is known. | `no-reflect-get`, `no-reflect-apply` | `Reflect.get(o, "k")`; Python `getattr(o, "k")` with a literal; Java reflection on a known method. |

## 2. Code shape

| Principle | From | Looks like |
|---|---|---|
| One pass when two eager passes do the same job. | `no-array-filter-map` | `.filter().map()` over a large array; Python `[f(x) for x in [y for y in z if p(y)]]`. Lazy iterator chains (Rust iterators, Python generators) are fine. |
| Don't copy the accumulator on every iteration. | `no-reduce-accumulator-copy` | `reduce((acc, x) => ({...acc, [x.k]: x}))`; Python `acc = acc + [x]` in a loop. Quadratic for no reason. |
| Omit optional fields plainly. | `no-conditional-empty-object-spread` | `{...(cond ? {a} : {})}`. Use the repo's normal way to build optional fields. |
| Name things by meaning, not structure. | `no-shape-in-symbol-names` (generalized) | `userShape`, `dataObj`, `resultInfo`, `FooHelper`, `handleStuff`. |
| Don't rename imports for no reason. | `no-renamed-imports` | `import { foo as foo2 }` with no conflict; Python `import numpy as numpy`. |
| Handle every async result and error. | `typescript/no-floating-promises` | Unawaited promises; Python coroutines never awaited; Go `_ = err`; Rust `let _ = fallible()`; Zig `catch {}`. |
| Delete conditions that can't change and code that can't run. | `no-unnecessary-condition`, `no-unreachable` | Null checks on non-nullable values; `if (true)`; code after `return`. |
| Don't call deprecated APIs in new code. | `typescript/no-deprecated` | Check the repo's deprecation markers and changelog. |

## 3. Tests

| Principle | From | Looks like |
|---|---|---|
| Assert on behavior, not only on mock calls. | `no-call-only-assertions` | A test whose only checks are `expect(mock).toHaveBeenCalledWith(...)` or `mock.assert_called_once()`. |
| Prefer real seams over module mocking. | `no-module-mocking` | `jest.mock("../db")`, `vi.mock`, Python `patch("module.thing")` across module boundaries. Use fakes or dependency injection, unless the repo's tests mock pervasively. |
| Don't test that a constant contains its own substring. | `no-poor-substring-tests` | Asserting an error message you just wrote contains a word from it. |
| Don't repeat the same assertion. | `no-repeated-expect-call` | Adjacent identical `expect(...)` or `assert` lines. |

## 4. Agent-specific slop (additions)

None of these come from the linters above. They're the patterns that make maintainers say "AI-generated" on sight.

- **Narrating comments.** `// increment the counter`, `# loop over items`. Delete.
- **Conversation residue.** Comments like `// fixed per issue`, `// now handles empty input`, `// updated to use X`. The comment should make sense to someone who never saw the PR.
- **Defensive code for impossible states.** Null checks, try/catch, and fallbacks around calls that can't fail by construction. A broad catch that logs and continues is the worst version.
- **Speculative generality.** A new interface, factory, config flag, or parameter with one caller and no request for it.
- **Compatibility shims for things nobody shipped.** Keeping an old code path "just in case" when the old path never reached a release.
- **Logging everywhere.** New log lines at every step when neighbors log only on failure.
- **Docs and README edits nobody asked for.** Update docs only when the change alters documented behavior.
- **Emoji, banners, and section-divider comments** in code where the repo has none.
- **Changing unrelated lines.** Whitespace, import order, or quote style on lines you otherwise didn't touch. Revert them; the formatter will handle what CI cares about.

## Running the TS/JS linters locally (optional)

For a TS/JS repo, you can run `ai-deslop` against just your changed files without adding anything to the repo. Install it and write its Oxlint config inside the ledger directory (`$(git rev-parse --git-dir)/houseguest/`), point Oxlint at that config, and pass it only the files in `git diff --name-only <base>...HEAD`. Follow the package README for the current config shape. Treat its output as candidates for the judgment above; a hit that contradicts the repo's own lint config is a skip.
