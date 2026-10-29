# Lean: the smallest PR that fully solves the issue

A small PR gets read the day it arrives; a big one waits for a free afternoon that never comes. Maintainers review every line you add, then own it for years, so each line you leave out is review time and maintenance you hand back. Write the change the way the laziest senior developer in the room would: the whole fix, with the least new code.

This adapts [ponytail](https://github.com/DietrichGebert/ponytail)'s laziness ladder for a guest. Ponytail trims your own code; here the house rules still come first, and the code you're allowed to trim is your own diff.

## Before you write

Read the issue and the code it touches. List every place the change must reach: callers, tests, fixtures, config, exports, docs the repo keeps in sync. That list is the scope. Anything the issue didn't ask for is out of it.

## The ladder

Take the first rung that fully works:

1. **Does it need to exist in this PR?** Drop features, options, and flexibility nobody asked for, and name them in one line of the PR body if a reviewer might wonder. A second fix you found along the way is a second PR.
2. **Is it already in this codebase?** A helper, a constant, a pattern three files over. Use it the way the neighbors do. This is the rung guests skip most, and the one reviewers catch most ("import this from exports.ts instead").
3. **Does the standard library or the platform do it?** Use it, unless the repo has its own wrapper; a house helper beats a native call.
4. **Does an installed dependency do it?** Use it. Never add a dependency for a few lines; a new dependency is a decision for maintainers, and needs an issue that asked for it.
5. **Can it be one line a reader gets at a glance?** One line.
6. **Otherwise,** the minimum code that works.

## Rules that hold on every rung

- **Be lazy about the solution and thorough about the change.** Finish every part the issue needs, including the callers, tests, and fixtures your change breaks.
- **No abstraction, wrapper, option, or "for later" code** nobody asked for. Keep the structure the repo already has: its layers, interfaces, and conventions.
- **Deletion beats addition, inside your own diff.** Code a maintainer wrote stays, unless the fix requires changing it (see `style.md`).
- **Fewer lines only when each stays as easy to read.** Don't fold two branches into a ternary or a compound condition so they can share setup. A Blink CL merged a JSON branch and a string branch into `!(is_object ? Stringify(...) : ToString(...)).ToLocal(&out)`, and the reviewer asked for nested `if`s back. A line the reader parses twice costs more than the two lines it replaced. Branch the way the neighbors branch.
- **Fix the root cause once.** Grep every caller of the function you touch, and fix the shared code rather than one caller.
- **Guard the whole failure set.** When the fix catches a call that can fail, list every way it fails (from its docs, its signature, or its source) before you write the guard. Reviewers think in that set. The same CL guarded `ToString()` against a `Symbol` and drew two questions: aren't there other cases, and shouldn't they be tested? `ToString()` also fails on an object whose `toString` throws, on stack overflow, and on termination. The guard usually covers the set already, so the comment and the tests are what have to say so.
- **Code you move keeps its error handling and validation,** and its doc comment.
- **Between options of equal size, take the one that's correct on edge cases.**
- **One good test per cause,** the kind that fails when the bug comes back, mirroring the tests beside it. When the guarded call fails in several ways, test each one a public input can reach, and name the rest in the PR body. Trivial changes need none, unless the repo requires one.
- **A known limit goes in the PR body,** in one sentence with when it would matter. Ponytail marks these with `shortcut:` comments; in someone else's repo that's a foreign convention, so keep it out of the code.

Never cut: validation at trust boundaries, error handling that prevents data loss, security, accessibility, anything the issue asked for, or anything the house rules require (a changeset, a test, a docs line).

## One concern per PR

A PR that does two things gets reviewed at the speed of the harder one, and the easy half waits. Split when:
- the diff fixes a bug and adds a feature (two changesets is the tell);
- it touches two packages for unrelated reasons;
- it carries a refactor the fix doesn't need.

The second PR can follow once the first lands, or go up beside it with a line linking the two.

## Check it

`housecheck.sh` measures the diff against PRs other people got merged in this repo (size check Z1), and flags more than one concern (Z2), a new dependency (Z3), and a new option or flag (Z4). Each flag gets fixed or acknowledged with a reason, like any other flag. The maintainer-reviewer pass in `pr-copy.md` then reads the diff with the same ladder and ends with how many lines could go.

---

Adapted from ponytail by DietrichGebert, MIT License:

> Copyright (c) 2026 DietrichGebert
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
