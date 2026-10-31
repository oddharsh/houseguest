Important: 0, Nit: 2, Pre-existing: 0
No blocking issues

The diagnosis holds up against the code. `list_comments` types a comment after a blank line (or not first in its prefix) as `STANDALONE_COMMENT`, and `_is_valid_standalone_fmt_comment` returned `True` for those before the `is_fmt_skip and prev.type in WHITESPACE` check at `src/black/comments.py:281` could run. A comment directly under a statement is typed `token.COMMENT` and does reach that check, so the two spellings disagreed. `fmtskip4.py` already pins the "own-line skip skips nothing" behavior, so this aligns the blank-line case with an intended rule rather than changing one. Inside brackets the previous leaf is never `NEWLINE`/`INDENT`/`DEDENT`, so `fmtskip_in_parens.py` and `fmtskip_after_bracket_with_comment.py` keep going down the `True` path. Changelog entry is under "Stable style," one sentence, no internals; the stable placement is fine under the "fixing crashes" exception in the contributing basics, and the 162-file byte-identical run backs "code that formatted before formats the same." Would merge.

## Nits

**1. `src/black/comments.py:273` restates the check two branches below it (`:281`).** For a comment that carries `# fmt: skip` and not `# fmt: off`, `return not (is_fmt_skip and prev is not None and prev.type in WHITESPACE)` gives exactly what falling through gives: `if not prev: return True` (`:275`), then `if is_fmt_skip and prev.type in WHITESPACE: return False` (`:281`), then `return True`. So the fix can be one changed line, with `prev = preceding_leaf(leaf)` left where it was:

```python
    if comment.type == STANDALONE_COMMENT and not is_fmt_skip:
        return True
```

That drops the moved `prev` line and the folded three-way `not (...)` that a reader has to parse against `:281` anyway; a one-line comment above it ("`# fmt: skip` on its own line skips nothing, same as below") would still fit. The only input where the two versions differ is a comment carrying both directives (`# fmt: off  # fmt: skip`) after a non-whitespace leaf, which then also hits the `is_fmt_off` check at `:279`. I don't think anyone writes that, but say so if you care about it.

**2. `pr-body.md`, last line.** The "🤖 Generated with [Claude Code]" footer repeats the AI disclosure sentence right above it, and it's the one line in the body that reads as tool boilerplate. Drop it and keep the disclosure sentence, which already names the tool, the model, and what was verified.

Lean: -3 lines possible
