Important: 3, Nit: 4, Pre-existing: 0

## Important

**1. The headline memory number can't be reproduced, and it may not apply to the build users run.**

The body says "Measured on a synthetic benchmark: peak memory 75.325 MB → 20.107 MB" and "cuts allocation overhead across the hot formatting path." It names no script, no input file, no Python version, no measuring tool, and no build.

- The build matters here. Release wheels are mypyc-compiled: `pyproject.toml:144` configures the mypyc hook and `pyproject.toml:190` sets `HATCH_BUILD_HOOKS_ENABLE = "1"` for cibuildwheel. Compiled native classes already have no per-instance `__dict__`; the maintainers say so in `src/blib2to3/pgen2/grammar.py:103` ("mypyc generates objects that don't have a __dict__"). So the `__slots__` savings on `Node`/`Leaf` may only show on a pure-Python install. The body should say which build produced 75 → 20 MB and give the number for the other one.
- "Cuts allocation overhead across the hot formatting path" is a speed claim with no time measured on base or HEAD. Some of the diff points the other way. `Base(ABC)` (`src/blib2to3/pytree.py:55`) gives `Node` and `Leaf` the `ABCMeta` metaclass, so in the pure-Python build every `isinstance(x, Leaf)` where `x` is a `Node` (and the reverse) misses CPython's exact-type fast path and calls `ABCMeta.__instancecheck__`. `src/black` has 79 `isinstance(..., Leaf|Node)` sites (`git grep -c`).
- Fix: run `profiling/mix_huge.py` (or the other `profiling/` inputs the repo already keeps) on base and HEAD, compiled and uncompiled. Report peak memory from one tool (`tracemalloc` or `/usr/bin/time -l`) and wall time from `hyperfine --warmup 3`. Without that, drop the numbers from the body and the "Performance" changelog line.

**2. The body claims changes the diff doesn't make, or does the reverse of.**

- "Removed dead fields (`used_names` ...)": the parser still builds the set on every parse. `src/blib2to3/pgen2/parse.py:168` adds a `"used_names"` slot, `parse.py:233` still allocates `self.used_names: set[str] = set()`, and `parse.py:338` still does `self.used_names.add(value)` for every NAME token. Removing the only reader (the deleted `self.rootnode.used_names = self.used_names`) leaves a write-only set on the hottest path in the parser. Delete all three lines.
- "Removed avoidable intermediate allocations": these lines add allocations the base didn't make.
  - `src/black/lines.py:484`: `self.leaves[1:]` copies the whole leaf list on every `str(line)`. The base walked an iterator. `str(line)` runs constantly (`is_line_short_enough`, `run_transformer` at `src/black/linegen.py:2160`).
  - `src/blib2to3/pytree.py:429-430`: builds a full `{id(x): None}` dict and a copy of it, then the loop below overwrites every key in both. Two extra N-entry dicts per `update_sibling_maps` call.
  - `src/black/output.py:92` and `src/black/trans.py:1405`: build a tuple just to pass it to `extend`, where the base made two `append` calls with no tuple.

**3. Most of the diff is a second concern: drive-by refactors that don't touch memory.**

`docs/contributing/the_basics.md` doesn't forbid this, but the PRs this one sits beside each do one thing (#5232, #5194 and #5178 touch only `pytree.py`, plus `comments.py` for #5232, and `CHANGES.md`). Here, each of the following needs its own review for equivalence, and none changes per-instance memory:

- `src/black/linegen.py:1057-1062`: rewrites the `should_hug` branch in `_first_right_hand_split`. That's formatting logic, so it also needs a diff-shades read in a PR that claims to be about memory.
- `src/black/lines.py:200`: folds `_is_triple_quoted_string` into one `startswith`.
- `src/black/trans.py:2264`: `ends_with_comma` fold.
- `src/blib2to3/pgen2/pgen.py:40, 51-54, 125`: `sorted()` and a list comprehension in grammar generation, which runs once and gets pickled.
- `src/blib2to3/pytree.py:43` (`type(val) is int`), `:623` (an `if` folded into a ternary), `:939, :970, :1034` (`r0 | r1`), `:817` (lambda removal), `:729` (fixes the "unbound when content is None" TODO, which is a bug fix in its own right).
- `src/blib2to3/pgen2/driver.py:19`: drops the unused `import io`.
- `eq=False` and `repr=False` on every dataclass (`src/black/brackets.py:59`, `src/black/comments.py:40`, `src/black/lines.py:41, 496, 507, 547`, `src/black/ranges.py:528`, `src/blib2to3/pgen2/driver.py:39`). `__eq__` and `__repr__` live on the class and cost nothing per instance, so these save no memory. They do change behavior: `BracketTracker() == BracketTracker()` is `True` on base and `False` on HEAD, and `ProtoComment`, `RHSResult`, `LinesBlock`, `EmptyLineTracker` and `_LinesMapping` lose the field reprs a debugger or a failing assert prints.

Keep `slots=True` and the `Node`/`Leaf`/pattern `__slots__` here, and send the rest as a separate cleanup PR (or drop it).

## Nits

**1. `Node.__init__`'s contract changed and its docstring didn't.** `src/blib2to3/pytree.py:252-253` still says "an optional context keyword argument" after `context` was removed. It also says "a sequence of child nodes", but `Base.__init__` (`pytree.py:69`) now stores `children or []` where the base did `list(children)`. So `kids = [leaf]; Node(256, kids).append_child(x)` now mutates `kids`, and `Node(256, (leaf,))` stores a tuple that `append_child` can't append to. Separately, `prefix` moved from the 4th positional slot to the 3rd, so a lib2to3-style `Node(t, kids, ctx)` call now sets `ctx` as the prefix. No in-repo caller hits any of these, but `blib2to3` ships as a top-level package, so the body should say the signature changed. Keep `list(children)` in `Node`, and fix the docstring.

**2. `Leaf`'s prefix handling changed for an explicit empty prefix.** `src/blib2to3/pytree.py:487` is `self._prefix = prefix or self._prefix`; the base had `if prefix is not None:`. `Leaf(token.NAME, "x", context=(" ", (1, 0)), prefix="")` gives prefix `""` on base and `" "` on HEAD. Nothing in-repo passes both, so restore the `is not None` check rather than prove that stays true.

**3. `BasePattern` lost its can't-instantiate guard.** The base's `__new__` asserted "Cannot instantiate BasePattern". HEAD swaps it for `ABC` (`pytree.py:567`), but `BasePattern` declares no `@abstractmethod`, so `BasePattern()` now constructs fine. `Base` keeps its guard only because it gained abstract methods.

**4. Slots that do nothing.** `src/black/trans.py:425` gives `StringMerger` `__slots__ = ()`, but `StringTransformer` (`trans.py:209`) and `CustomSplitMapMixin` (`trans.py:345`) have no `__slots__`, so instances keep a `__dict__`. Same for `PgenGrammar` at `src/blib2to3/pgen2/pgen.py:15` over `Grammar` (`grammar.py:31`). `TokenProxy`'s `"logger"` slot (`src/blib2to3/pgen2/driver.py:51`) is never assigned; that attribute belongs to `Driver`. And the `if previous is not None:  # if self.children is empty!` guard at `pytree.py:438` covers a state `update_sibling_maps` can't reach through `next_sibling`/`prev_sibling`, since the parent always has the child asking.

Lean: -9 lines possible (`trans.py:425-426`, `pytree.py:429-430` and `:437-439` back to the base loop, the `used_names` slot plus `parse.py:233` and `:338`), and about 70 changed lines leave this PR with the drive-by refactors in Important 3.

Wouldn't merge as is. Narrowed to the slots change with a reproducible base-vs-HEAD measurement on both builds, I'd look again.
