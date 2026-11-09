Important: 2, Nit: 2, Pre-existing: 1

The diagnosis checks out. On base, `read_until(b'\n')` in `try_new` already stops after `00 0A` for `test_UTF-16BE.txt`, and `read_utf16_line` reads before it checks, so line 2 gets glued onto line 1. The existing `utf16` test runs that file with `--plain`, where the merged line prints the same text, so nothing caught it. The fix is small and in the right place. Two things block it.

## Important

**1. The changelog entry still carries a placeholder PR number, so the changelog CI job fails.**

`CHANGELOG.md:29` ends `see #XXXX (@cindykrafft)`. CONTRIBUTING.md says: "Please replace `#123` with the number of your pull request (not issue) and `@user` by your GitHub username." `.github/workflows/require-changelog-for-PRs.yml` enforces it with `grep "#${PR_NUMBER}\\b.*${PR_SUBMITTER}\\b" <<< "$ADDED"`, which can't match `#XXXX`. Put the real PR number in.

**2. Half of the new guard has no test: deleting `first_line.len() % 2 == 0` keeps every test green.**

`src/input.rs:298` skips the extra read only when the first line has even length and ends in `00 0A`. The parity half is the subtle part, and it guards a case no test reaches: a code unit with low byte `0x00` followed by one with high byte `0x0A`. Input `FE FF 01 00 0A 41 00 0A` (U+0100 U+0A41 newline) makes `read_until` stop after 5 bytes, ending in `00 0A` at an odd offset. Without the parity check, `first_line` would be `FE FF 01 00 0A`, splitting U+0A41 in half, and line 2 would decode as garbage.

Neither BE test covers it. The new `utf16be_first_line_not_merged_with_second` only hits the even case. `utf16be` uses `test_UTF-16BE-complicated.txt`, whose first `0x0A` comes from U+4E0A (`4E 0A`), and that fails `ends_with(&[0x00, 0x0A])` whatever the parity. So the comment's own example (`src/input.rs:297`, "such as U+4E0A") names a case the `ends_with` half handles, not the case the parity half exists for.

Add a unit test beside `utf16le_issue3367` in `src/input.rs` (that's the pattern this file uses for first-line byte boundaries) asserting `reader.first_line == b"\xFE\xFF\x01\x00\x0A\x41\x00\x0A"` for that input, and point the comment at that case instead of U+4E0A.

## Nit

**3. The comment sits inside the `else if` condition, between its two operands.** `src/input.rs:294-299` reads as `else if A // three comment lines && !(B && C) {`, and the reader has to carry `A` across the comment to parse the negated conjunction. Every other content-type branch in this file is a plain `if content_type == ...`. A nested `if !(...)` inside the BE arm, with the comment above it, reads at a glance.

**4. The test comment restates the test name.** `tests/integration_tests.rs:2106`, "The first line of a UTF-16BE file must not swallow the second line," says what `utf16be_first_line_not_merged_with_second` already says. Neighbors use this slot for the issue link (`// Regression test for https://github.com/sharkdp/bat/issues/1922`). Link the issue or PR, or drop the line.

## Pre-existing

**5. `read_utf16_line` ends a line on any trailing `00 0A`, with no parity check.** `src/input.rs:382-388` (untouched here) breaks as soon as `buf` ends in `preceded_by_char, read_until_char`. For a later line, `FE FF 00 61 00 0A 01 00 0A 41 00 0A` ("a", newline, U+0100 U+0A41, newline) gives line 2 as `01 00 0A`, splitting U+0A41. The LE call has the mirror case. This PR adds the right parity check for the first line only; the same check in `read_utf16_line` would be its own PR.

Would merge once 1 and 2 are fixed.

Lean: -1 lines possible
