Important: 3, Nit: 4, Pre-existing: 0

I wouldn't merge this as is. The Node/Leaf `__slots__` change might be worth having, but it's buried under a dozen unrelated rewrites, and the memory number isn't backed by anything a reviewer can rerun.

## Important

**1. No single focus: one memory change bundled with unrelated refactors and rewrites of dead code.**

The title and changelog entry are about Node and Leaf memory. Most of the diff isn't. Each of these is unrelated to Node/Leaf memory and should be reverted from this PR (or sent separately if you think it stands on its own):

- Control-flow restyles with no allocation change: `src/black/linegen.py:1058-1061` (now with 2 stray blank lines) (`should_hug = not ...`), `src/black/lines.py:200` (merged `startswith` tuples), `src/black/trans.py:2264` (`ends_with_comma = ...`), `src/blib2to3/pytree.py:623` (if-block folded into a ternary), `src/blib2to3/pytree.py:43` (`==` to `is`), `src/blib2to3/pytree.py:817` (lambda removal), `src/blib2to3/pgen2/pgen.py:40,51-54,125` (`sorted()`, list comprehension, `next` renamed to `next_`).
- An unused-import cleanup: `src/blib2to3/pgen2/driver.py` (removed `import io`, line 19 at base).
- Rewrites of the pattern-matching classes, which Black never calls: `BasePattern`, `LeafPattern`, `NodePattern`, `WildcardPattern`, `NegatedPattern` and `generate_matches` (`src/blib2to3/pytree.py:567-1035`). `git grep -E "Pattern\b|generate_matches" -- src/black tests/*.py` finds no caller. The existing comment at `pytree.py:735` already says so ("I don't even think this code is used anywhere"). Slots, new `__init__`s and `r0 | r1` there change nothing for a Black run. They also remove a guard: `BasePattern(ABC)` declares no abstract methods, so `BasePattern()` now succeeds where the old `__new__` asserted "Cannot instantiate BasePattern".
- `Base(ABC)` plus `@abstractmethod` (`pytree.py:15,55,84-117`). This is an API-style change, not a memory one. It also puts `ABCMeta` on `Leaf` and `Node`, so every `isinstance(x, Leaf)` where `x` is a `Node` now goes through `ABCMeta.__instancecheck__` in pure-Python runs. That's not a cost I'd take in a perf PR without a timing.
- `eq=False` and `repr=False` added to 7 dataclasses (`brackets.py:59`, `comments.py:40`, `lines.py:41,496,507,547`, `ranges.py:528`, `driver.py:39`). Generated `__eq__`/`__repr__` live on the class, so dropping them saves 0 bytes per instance. They do change behavior: `RHSResult`, `LinesBlock`, `EmptyLineTracker` and friends now print as `<... object at 0x...>` while debugging.

Suggested shape: keep `__slots__` on `Base`/`Node`/`Leaf`, the `fixers_applied`/`context` removal if maintainers want it, and `slots=True` on `Line`/`BracketTracker` if a measurement shows they matter. Drop the rest.

**2. The headline number (75.325 MB to 20.107 MB) has no reproducible source, and the mechanism doesn't apply to the build most users run.**

- The body says "Measured on a synthetic benchmark" with no script, no input file, no Python version, and no build named. The repo already ships inputs for exactly this in `profiling/` (`mix_huge.py`, `dict_huge.py`, `list_huge.py`). Please report peak RSS on those, before and after, with the command you ran.
- Black's wheels are compiled with mypyc (`pyproject.toml:144-163`), and `pytree.py`, `lines.py`, `brackets.py`, `comments.py`, `parse.py`, `driver.py` and `trans.py` aren't in its `exclude` list. Compiled native classes store attributes in a fixed struct with no per-instance `__dict__`. The repo says this itself at `src/blib2to3/pgen2/grammar.py:103` ("mypyc generates objects that don't have a `__dict__`"). So `__slots__` and `slots=True` should save nothing for mypyc-wheel users, and the body should either show a mypyc measurement or say the gain is pure-Python only.
- Nothing says the mypyc build was attempted. `src/black/linegen.py:107` records that a dataclass feature combination already broke mypyc once ("@dataclass + Generic breaks mypyc"), and this PR adds `slots=True` dataclasses and `ABC` bases to compiled modules. Please build with `HATCH_BUILD_HOOKS_ENABLE=1` (or however you build the mypyc wheel) and run the suite against it.

**3. The description's allocation claims (items 2 to 4) are contradicted by the diff.**

- "Removed avoidable intermediate allocations in hot paths like `r = r0 | r1`": `pytree.py:939,970,1034` sit in `WildcardPattern._iterative_matches`, `_recursive_matches` and `generate_matches`, which Black never calls (see 1). The new form also builds exactly one dict, same as the `{}` plus two `update()` calls it replaced.
- "Simplified unnecessary ... object creations": `lines.py:484` `self.leaves[1:]` copies the leaf list, where the old code walked an iterator over it. `pytree.py:429-430` (`update_sibling_maps`) now pre-fills both dicts with `None` and copies one, then overwrites every entry in the loop: about 4N+1 dict writes for N children versus 2N+1 before, producing identical maps. `output.py:92` and `trans.py:1405` replace two `append`s with `extend()` of a freshly built 2-tuple, one extra allocation each. `output.py` is excluded from mypyc as "Not performance sensitive" (`pyproject.toml:151-154`) anyway.
- "Removed dead fields (`used_names` ...)": the parser still builds the set. `parse.py:233` creates it and `parse.py:338` adds every NAME token to it; the PR removed only the line that attached it to the root node (old `parse.py:395`) and added a `"used_names"` slot for it at `parse.py:168`. If it's dead, delete the slot, the initializer, and the `add()` (and its comment at `parse.py:337`).
- The `update_sibling_maps` guard at `pytree.py:438` ("if self.children is empty!") covers a call that can't happen: its only callers (`pytree.py:199,213`) run on `self.parent`, which has at least one child. Revert that hunk.

## Nits

**N1. Stale docstring.** `Node.__init__`'s docstring at `pytree.py:253` still says it takes "an optional context keyword argument", but the PR removed `context` from the signature.

**N2. Two constructor contracts changed by packing an `if` into an `or`.**
- `pytree.py:487` `self._prefix = prefix or self._prefix`: `Leaf(t, v, context=(" ", (1, 0)), prefix="")` used to get prefix `""` (old code: `if prefix is not None`) and now gets `" "`.
- `pytree.py:69` `children or []`: `Node` no longer copies its list (old `list(children)`), so `kids = [a]; n = Node(sym, kids); kids.append(b)` now puts `b` into `n.children` without setting `b.parent` or invalidating the sibling maps. An empty list passed in is still replaced, so aliasing depends on length.

No caller in `src/` hits either case today (the parser's raw child lists are discarded after `convert`), so this is a nit. Keep the old `if prefix is not None` branch, and either keep the copy or write down that `Node` takes ownership of the list.

**N3. Slots that do nothing.** `trans.py:425` `StringMerger.__slots__ = ()` and `pgen.py:15` `PgenGrammar.__slots__ = ()` sit on classes whose bases have no `__slots__` (`StringTransformer`, `trans.py:209`, which sets attributes at `trans.py:241-242`; `CustomSplitMapMixin`, `trans.py:345`; `Grammar`, `grammar.py:31`). Instances still get a `__dict__`. `driver.py:51` reserves a `"logger"` slot that `TokenProxy` never assigns. Drop all three.

**N4. Changelog wording.** The contributing guide (`the_basics.html`, "News / Changelog Requirement") says: "Avoid referencing Black internals or the implementation details of the change." "Reduce memory requirement for Node and Leaf class" names internals; "Reduce memory use when formatting large files" (with the measured figure, once there is one) would match. Neighboring entries bend this rule too, hence nit.

Lean: -85 lines possible (revert the hunks listed in Important 1 and 3, plus N3).
