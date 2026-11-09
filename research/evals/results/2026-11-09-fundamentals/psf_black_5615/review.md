Important: 0, Nit: 3, Pre-existing: 0
No blocking issues

The fix is in the right place. `_is_valid_standalone_fmt_comment` waved every `STANDALONE_COMMENT` through before the `is_fmt_skip and prev.type in WHITESPACE` check could run, so an own-line `# fmt: skip` after a blank line reached `_generate_ignored_nodes_from_fmt_skip` and grabbed the previous sibling. Inside brackets the preceding leaf is never `NEWLINE`/`INDENT`/`DEDENT`, so the bracket cases (`fmtskip_after_bracket_with_comment.py`, `line_ranges_fmt_skip_in_brackets.py`) keep their path. I also looked for a base fixed point this would reformat (the stability policy question): a base-formatted file has the comment directly under the statement, which makes it a `COMMENT` at index 0 that base already rejects, so I couldn't build one. The changelog entry is one sentence, user-facing, under "Stable style", as `the_basics` asks.

## Nits

**1. The same condition now lives twice, and the new branch packs it into a negated compound.** `src/black/comments.py:273` returns `not (is_fmt_skip and prev is not None and prev.type in WHITESPACE)`, and `src/black/comments.py:281` still tests `is_fmt_skip and prev.type in WHITESPACE` for the non-standalone path. The neighbors branch as `if ...: return False`. Hoist the existing check above the standalone branch and drop the second copy:

```python
prev = preceding_leaf(leaf)
if is_fmt_skip and prev is not None and prev.type in WHITESPACE:
    return False
if comment.type == STANDALONE_COMMENT:
    return True
if not prev:
    return True
if is_fmt_off and prev.type not in WHITESPACE and prev.type != STANDALONE_COMMENT:
    return False
return True
```

That's equivalent on every path (for a non-standalone comment with `prev` in `WHITESPACE` both orders return `False`; with `prev is None` both return `True`), and it removes the 2-line comment at :271-272, whose "not the statement above either" describes the old bug rather than the code. The docstring at :266-267 ("We only want standalone comments") is now half wrong for `# fmt: skip`; one clause there covers it.

**2. The first block of the new test doesn't exercise the bug, and the crash from the description isn't a test case.** In `tests/data/cases/fmtskip_own_line_between_statements.py:5-8` the comment sits in the prefix of `y`, whose parent `expr_stmt` is the first child of its `simple_stmt`. `_generate_ignored_nodes_from_fmt_skip` (`src/black/comments.py`, the `prev_sibling = parent.prev_sibling` fallback) only climbs one level, finds no previous sibling, and yields nothing, so as far as I can read it, base already produces this block's expected output. The class and method blocks are what fail on main. Swap the `x`/`y` block for the description's own repros, which do take the buggy path because the comment lands on `ENDMARKER` (a child of `file_input`): `x = 1\n\n# foo  # fmt: skip\n` and the `import a\n# foo  # fmt: skip\n\n` input that crashes with "produced different code on the second pass". The crash is what the checklist leans on to justify a stable-style change, so it should be pinned. They need their own case file, since both rely on the comment being last.

**3. Description.** "in the middle of a file an extra blank line can appear instead" has no example; either show the input or cut the clause. The corpus numbers ("6 of the failing files in a 6,000-file run") can't be checked by anyone here, and "6 of" what total is left out. The title is hard to parse; something like "Fix own-line `# fmt: skip` after a blank line skipping the previous statement" reads in one pass. The "Generated with Claude Code" footer duplicates the disclosure line above it; the disclosure alone is enough.

Would merge with nit 2 addressed; 1 and 3 are optional.

Lean: -2 lines possible
