Important: 2, Nit: 2, Pre-existing: 1

The fix is right and small. I traced the BE path on `test_UTF-16BE.txt` (`fe ff ... 00 64 00 0a 00 74 ...`): on base, `read_until(b'\n')` stops at the `00 0a` after "world", then `read_utf16_line` reads on to the next `00 0a`, so line 1 swallows line 2. The new test asserts `   1 hello world\n   2 this is a test\n` and would fail on base, where line 2 prints with no number. The `#3369` history in the body checks out against `CHANGELOG.md:149`. Two things before I'd merge.

## Important

**1. Changelog entry carries a placeholder PR number.** `CHANGELOG.md:29` ends with `see #XXXX (@cindykrafft)`. `CONTRIBUTING.md` says: "Please replace `#123` with the number of your pull request (not issue)". The `require-changelog-for-PRs.yml` check only greps for an added line, so CI won't catch it and `#XXXX` would ship in the release notes. Fix: swap in the real number once the PR is open.

**2. Half of the new guard has no test, so a regression in it passes CI.** The condition at `src/input.rs:298` has two parts, and the tests and the comment cover only one:

- `first_line.ends_with(&[0x00, 0x0A])` handles a `0x0A` that is the low byte of another character (U+4E0A). The comment at `src/input.rs:295-297` names this case, and the existing `utf16be` test (`test_UTF-16BE-complicated.txt`, starts `fe ff 4e 0a`) fails if that half is removed.
- `first_line.len() % 2 == 0` handles a `0x0A` that is the high byte of a character right after one whose low byte is `0x00`. Example: "Āਅ\nx\n" is `fe ff 01 00 0a 05 00 0a 00 78 00 0a`. `read_until` stops at `fe ff 01 00 0a` (5 bytes), which ends in `00 0a`. Only the parity check sends it on to `read_utf16_line`. Delete `first_line.len() % 2 == 0 &&` and every test still passes, while line 1 gets cut mid-character.

Fix: add one test for the misaligned case. The house pattern for exact first-line bytes is the unit test `utf16le_issue3367` at `src/input.rs:620`: build `InputReader::new` on `b"\xFE\xFF\x01\x00\x0A\x05\x00\x0A\x00\x78\x00\x0A"` and assert `first_line == b"\xFE\xFF\x01\x00\x0A\x05\x00\x0A"`. Then add the misaligned case to the comment too, since right now it explains why `ends_with` is there but not why the length must be even.

## Nit

**3. The comment sits between the operands of the `else if`** (`src/input.rs:294-299`), and the negated compound `!(a && b)` makes the reader parse the condition twice. Everywhere else in `try_new`, comments sit above statements. A named local reads in one pass and costs no extra lines:

```rust
let first_line_complete = first_line.len() % 2 == 0 && first_line.ends_with(&[0x00, 0x0A]);
...
} else if content_type == Some(ContentType::UTF_16BE) && !first_line_complete {
```

with the comment above the `let`.

**4. The test comment restates the test name.** `tests/integration_tests.rs:2106` says what `utf16be_first_line_not_merged_with_second` already says. The neighbor at `tests/integration_tests.rs:2117` uses its comment for an issue link; either link the issue or drop the line.

## Pre-existing

**5. `read_utf16_line` ends a line on any terminator pair, aligned or not** (`src/input.rs:382-384`). It checks `buf[len-2] == preceded_by_char && buf[len-1] == read_until_char` with no parity check, so every line after the first still splits mid-character on the same "Āਅ" input from finding 2 (BE `01 00 0a 05`, and the LE mirror `05 0a 00 01`). This PR makes the first line stricter than the rest; it doesn't touch or worsen the later lines, so it belongs in its own PR.

Lean: -1 lines possible

Would merge once 1 and 2 are fixed.
