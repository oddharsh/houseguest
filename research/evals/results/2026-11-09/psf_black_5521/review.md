Important: 2, Nit: 2, Pre-existing: 0

I couldn't run Black for this review (no environment), so everything below comes from reading `src/black/trans.py` at HEAD. The inputs are there so you can run them.

## Important

**1. The guard covers one path into the crash, and the crash's cause sits in `StringSplitter`, which other paths still reach.**

Your description of the mechanism checks out. `StringSplitter.do_transform` orphans the string at `src/black/trans.py:1684` (`insert_str_child = insert_str_child_factory(LL[string_idx])`). Only after that does it bail on depth at `src/black/trans.py:1738-1745` (`max_break_width < 0` -> `TErr("Unable to split ... at such high of a line depth")`). The new check at `src/black/trans.py:2098-2107` only stops `StringParenWrapper` from building that too-deep line when the match came from `_prefer_paren_wrap_match`. Every other matcher in `do_splitter_match` (`_return_match`, `_assign_match`, `_binary_match`, `_dict_or_lambda_match`, `_trailing_comma_tuple_match`) builds the same `depth=line.depth + 1` string line (`src/black/trans.py:2549-2558`). `StringSplitter` then picks that line up and hits the same orphan-then-bail sequence. A string-led line that `StringSplitter` takes directly, like a call argument (`arglist` isn't in `matching_nodes`), reaches it too.

The inputs I'd expect to take the same path, under `--unstable --line-length=4`:

```python
x = "so I should be braked"  # c
```

```python
f(
    "so I should be braked",  # c
)
```

The first goes through `_assign_match`. 4 - 1 - 4 = -1, so the wrapped line fails the depth guard after the orphan. The second never gets wrapped, and `StringSplitter` orphans it at depth 1 and bails the same way. Please run both on this branch. If either one crashes or fails the second-pass check, fix it at the root instead. Moving the depth check in `StringSplitter.do_transform` above the `insert_str_child_factory` call (or into `do_splitter_match`/`_validate`) covers every caller in one place. Then the paren-skipping in `StringParenWrapper` only has to justify itself as a style improvement. If neither crashes, say why in the body, since the error message you added names a condition that every matcher can hit.

**2. The "can't be split" half of `_wrapped_line_can_fit` changes behavior #5544 chose on purpose, at the default line length, and no test reaches it.**

`_prefer_paren_wrap_match` already returns `None` unless `can_be_split(...) or has_custom_splits(...) or line.comments` (`src/black/trans.py:1449-1455`). So the `self.can_be_split(string_value) or self.has_custom_splits(string_value)` half at `src/black/trans.py:2171-2173` only changes the result when the match came through `line.comments`. That's the case the comment above it still says gets wrapped on purpose: "or if the line has comments that will be moved to the LPAR", added in #5544 (commit 92494b5, 2026-10-22). The PR overrides that clause and leaves the comment saying the opposite.

Concrete input, `--unstable` at the default line length of 88. The string is 89 characters, and its only space sits at index 2, which is below `MIN_SUBSTR_SIZE`, so `can_be_split` is False:

```python
x = [
    "a bcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",  # comment
]
```

On base, `_prefer_paren_wrap_match` returns 0 because of the comment. The no-space check at `src/black/trans.py:2141-2153` doesn't fire because the string has a space. So Black wraps it, with `# comment` moved to the `(`. On this branch, 2 * 4 + 89 > 88, 88 - 1 - 8 >= 0, and `can_be_split` is False, so the wrap is refused. That contradicts the body's "Output at the default line length is identical in every mode." It also sits outside what the CHANGES entry describes (small line lengths and deep nesting).

The new test can't catch a regression here either. All four elements in `preview_long_strings__small_line_length.py` sit at depth 1 under `--line-length=8`. That makes `8 - 1 - 2 * 4 = -1`, so every one of them exits on the depth check before the `and (...)` runs. Replacing `src/black/trans.py:2171-2173` with `return self.line_length - 1 - new_depth * 4 >= 0` keeps the test green. Either drop the second half (if only the depth case causes the crash), or keep it and update the comment at `src/black/trans.py:1449-1451`, add a case like the one above, and say in the body that this reverses part of #5544.

## Nit

**3. The corpus numbers in the body can't be checked.** "1,486 real files", "16 test case results and 2 files that crash on main now format", and "the list nested 20 deep at the default line length" come with no command, no file list, and no output. The only test runs at `--line-length=8`, so nothing in the PR covers the deep-nesting case, which is the one real users hit. Either paste the script and the 2 crashing files, or cut the numbers down to what the test shows.

**4. `_wrapped_line_can_fit` copies two formulas from elsewhere in the file.** `new_depth * 4 + str_width(string_value) <= self.line_length` repeats `max_string_width = self.line_length - ((line.depth + 1) * 4)` at `src/black/trans.py:2145`. `self.line_length - 1 - new_depth * 4 >= 0` repeats `max_break_width` from `src/black/trans.py:1738-1741`, with nothing pointing back to it. If `StringSplitter`'s budget changes, this check silently drifts from the guard it predicts. The new error string at `src/black/trans.py:2104-2106` is also a near-copy of the one at `src/black/trans.py:2151-2153`.

## Lean

- `src/black/trans.py:2159-2173`: the new method has one caller and re-derives what the existing "won't fit and can't be split" block at `src/black/trans.py:2139-2153` already computes (`max_string_width`, `has_custom_splits`). That block already runs after every matcher. Extending its condition with the depth case removes the helper, the second error message, and the extra `if` at the call site. It also covers the other matchers in finding 1. Keep it as nested `if`s the way that block reads now, not one compound condition.
- If finding 1's root-cause move in `StringSplitter.do_transform` alone fixes the crash, most of the `StringParenWrapper` change becomes optional and can go to its own PR as a style change.

Lean: -16 lines possible
