Important: 0, Nit: 3, Pre-existing: 0
No blocking issues

I read the change against its caller (`convert_one_fmt_off_pair`, `src/black/comments.py:415`) and `_generate_ignored_nodes_from_fmt_skip` (`src/black/comments.py:863`). The root cause in the body holds. `list_comments` types a comment STANDALONE_COMMENT only when a newline precedes it in the prefix, and the early `return True` sent those past the `prev.type in WHITESPACE` check that already ignores the no-blank-line case (`fmtskip4.py`). Old black was never stable on an input where the skip fired: the blank line got eaten, and the next pass took the non-standalone path. So no file it had already formatted changes, and stable is the right place under the crash exception. Bracket cases keep `prev` as a bracket or token and still return True. I couldn't run the suite offline (no `pytokens` in the cache), so the test results are the author's.

## Nits

**1. The new condition duplicates the check four lines below it.** `src/black/comments.py:273` returns `not (is_fmt_skip and prev is not None and prev.type in WHITESPACE)`, which is `if not prev: return True` (`:275`) plus `if is_fmt_skip and prev.type in WHITESPACE: return False` (`:281`) folded into one negated compound. Only `fmt: skip` needs to skip the early return, so the whole fix can be one changed line:

```python
    if comment.type == STANDALONE_COMMENT and not is_fmt_skip:
        return True

    prev = preceding_leaf(leaf)
```

A standalone `# fmt: skip` then falls through to the existing checks and gets the same answer the PR computes. The one exception is a comment carrying both `fmt: off` and `fmt: skip`, which would also hit the `fmt: off` check at `:279`. That costs nothing: `prev` stays where it was, and the 2-line comment at `:271-272` goes. That comment's "not the statement above either" also reads as a note about the old bug, not about the code.

**2. The first block of the test doesn't exercise the bug.** In `tests/data/cases/fmtskip_own_line_between_statements.py:5-8` (`x   =   1`, blank, `# a comment  # fmt: skip`, `y   =   [1,2]`), the comment sits in the prefix of `y`. `y` is the first child of `expr_stmt`, whose `prev_sibling` is None, so `_generate_ignored_nodes_from_fmt_skip` yields nothing on base and `x = 1` gets formatted there too. Only the `class A` and `def g` blocks fail on `main`. The crash the body and CHANGES lead with (`import a`, `# foo  # fmt: skip`, blank line, EOF, where the ENDMARKER's prev sibling is the import) isn't in the test. Swap the `y` block for that input so the "could crash" in the changelog has a test behind it.

**3. Drop the robot footer from the body.** The last line (`🤖 Generated with [Claude Code](...)`) repeats the AI disclosure line just above it. Black has no AI policy that asks for either, and the disclosure sentence is enough.

Would merge as is. Nit 1 is the one I'd ask for in passing.

Lean: -3 lines possible
