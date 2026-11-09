Important: 4, Nit: 5, Pre-existing: 0

## Important

**1. The memory number has no reproducer, and the build it describes isn't named.**
The body says "Measured on a synthetic benchmark: peak memory 75.325 MB → 20.107 MB" with no script, no input file, no Python version, and no word on compiled vs. pure Python. That last one decides whether the number means anything for users. `pyproject.toml:144-165` compiles every module this PR touches except `output.py` with mypyc, and `src/blib2to3/pgen2/grammar.py:103` already says "mypyc generates objects that don't have a __dict__". So in the wheel most people install, `Leaf` and `Node` already have no per-instance dict, and `__slots__` probably saves close to nothing there. Please post the script (the repo ships inputs in `profiling/`, e.g. `profiling/mix_huge.py`), the command, the Python version, and numbers for both the pure-Python install and a `HATCH_BUILD_HOOKS_ENABLE=1` build.

The body also says the PR "Removed avoidable intermediate allocations in hot paths like `r = r0 | r1`". The evidence doesn't support that:
- `src/blib2to3/pytree.py:939`, `:970`, `:1034`: `r0 | r1` allocates one new dict, exactly like `r = {}; r.update(r0); r.update(r1)` did. These lines also sit in `WildcardPattern` / `generate_matches`, which nothing in `src/black` or `tests` calls (`grep -rn 'Pattern\|generate_matches' src/black tests` finds no use). They're not a hot path.
- `src/black/output.py:92` and `src/black/trans.py:1405`: `lst.extend((a, b))` builds a 2-tuple on every call that the two `append` calls never did. That's one more allocation per iteration in CPython, the opposite of the stated goal.
- `src/black/lines.py:484`: `self.leaves[1:]` copies the leaf list on every `str(line)` where the old code walked an iterator. It trades the old `comments` list for a new list of leaves.

**2. Most of the diff isn't the memory change.**
The useful part is `__slots__` on `Base`/`Node`/`Leaf` (and maybe the slots dataclasses). Everything below is a separate refactor that has to be reviewed against mypyc and the stable style on its own:
- `src/black/linegen.py:1057-1061`: `if/else` on `should_hug` folded into `should_hug = not ...`
- `src/black/lines.py:200`: `_is_triple_quoted_string` collapsed to one `startswith`
- `src/black/lines.py:479-489`: `Line.__str__` rewritten
- `src/black/output.py:92`, `src/black/trans.py:1402-1408`: `append` pairs turned into `extend`
- `src/black/trans.py:2264`: `ends_with_comma` collapsed
- `src/blib2to3/pgen2/pgen.py:40`, `:51-54`, `:125`: `sorted()` and a list comprehension, plus `next` renamed to `next_`
- `src/blib2to3/pytree.py:43`: `type(val) == int` to `is int`
- `src/blib2to3/pgen2/driver.py` (base line 19): unused `import io` dropped
- `src/blib2to3/pytree.py:55-123`: `Base` turned into an `ABC` with `@abstractmethod`; the old `__new__` assert already blocked instantiation, and nothing about memory needs a new metaclass on the class every `isinstance(x, Leaf)` check goes through
- `src/blib2to3/pytree.py:567-1035`: the whole `BasePattern` hierarchy rewritten (new `__init__`, `ABC`, slots, `newcontent`/`wrapped_content` defaults), all in code black never calls

Please cut this PR down to the slots change and send the rest separately, if at all.

**3. `used_names` is half removed.**
The body says it "Removed dead fields (`used_names` and `fixers_applied`)". The reader at the old `parse.py:395` is gone, but the writer is still there: `src/blib2to3/pgen2/parse.py:338` still runs `self.used_names.add(value)` for every NAME token, into a set that `parse.py:233` creates and nothing reads. The PR even adds it to the new `__slots__` at `parse.py:168`. If the field is dead, delete all three lines; that's the only part of this hunk that saves memory per file.

**4. Nothing shows the mypyc build was built or tested.**
This PR adds class features to compiled modules that the codebase has repeatedly flagged as fragile under mypyc: `@dataclass(slots=True, ...)` at `src/black/lines.py:41`, `:496`, `:507`, `:547`, `src/black/brackets.py:59`, `src/black/comments.py:40`, `src/black/ranges.py:528`, `src/blib2to3/pgen2/driver.py:39`; and `ABC` bases at `src/blib2to3/pytree.py:55` and `:567`. The neighbours say why that matters: `src/black/trans.py:238` ("Ideally this would be a dataclass, but unfortunately mypyc breaks when used with `abc.ABC`"), `src/black/linegen.py:107` (`@dataclass + Generic breaks mypyc`), and `src/black/handle_ipynb_magics.py:378`. CI tests the compiled wheels (`pyproject.toml:183`, `pytest ... -k "not incompatible_with_mypyc"`). Please say in the body that you built with `HATCH_BUILD_HOOKS_ENABLE=1` and ran the suite against it, and paste the result.

## Nits

**5. `eq=False` and `repr=False` change behavior and save no memory.** `slots=True` is the only flag that affects layout. `eq=False` makes `Line(mode=m) == Line(mode=m)` go from `True` to `False` (and makes these classes hashable by identity). `repr=False` turns `repr(ProtoComment(...))` into `<black.comments.ProtoComment object at 0x...>`, which is what you'll see in a pytest failure or a debugger. Instances: `lines.py:41`, `:496`, `:507`, `:547`, `brackets.py:59`, `comments.py:40`, `ranges.py:528`, `driver.py:39`. I couldn't find an in-repo caller that compares these, so this is about debuggability, but drop both flags unless you have a reason.

**6. Some of the new `__slots__` do nothing.** `StringMerger.__slots__ = ()` at `src/black/trans.py:425` can't remove the instance dict, because `StringTransformer` (`trans.py:209`) has no slots and sets `self.line_length` in `__init__` (`trans.py:241`). Same for `PgenGrammar.__slots__ = ()` at `src/blib2to3/pgen2/pgen.py:15`: `Grammar` (`grammar.py:31`) has no slots, and `Grammar.dump` checks `hasattr(self, "__dict__")` at `grammar.py:106`. `Parser` (`parse.py:160-169`) and `TokenProxy` (`driver.py:51`) get created once per parse, so their slots save bytes per file and add a list that must be kept in sync with `__init__`. Delete all four.

**7. `update_sibling_maps` got bigger for no gain.** `src/blib2to3/pytree.py:428-439` pre-fills `prev_sibling_map` with a dict comprehension and `.copy()`s it, then overwrites every key in the loop. That's two extra passes and an extra dict per call. The new guard at `:438` can't fire, because the only callers (`pytree.py:199`, `:213`) are a child asking its parent, so `children` is never empty. And its comment, "if self.children is empty!", says the opposite of the condition it sits on. Revert this hunk.

**8. `Leaf.__init__` changed what an explicit empty prefix means.** `src/blib2to3/pytree.py:487` is now `self._prefix = prefix or self._prefix`, where base had `if prefix is not None:`. Given `Leaf(token.NAME, "x", context=("  ", (1, 0)), prefix="")`, base gives `prefix == ""` and HEAD gives `"  "`. No caller in the repo passes both today, but keep the `is not None` check.

**9. `Node.__init__`'s docstring and contract went stale.** `src/blib2to3/pytree.py:252-253` still says it takes "a sequence of child nodes, and an optional context keyword argument", but `context` is gone. `Base.__init__` (`pytree.py:69`) also dropped the old `list(children)` copy, so `Node` now keeps the caller's list (and a tuple would break the first `append_child`). Fix the docstring, and say in the body that `Node` now takes ownership of `children`.

Lean: -85 lines possible (the added lines that go away if findings 2, 3, 6, and 7 revert or delete the hunks; the base lines they replaced come back)

Not ready to merge. Split out the slots change, show numbers for both builds, and confirm the mypyc suite passes.
