Important: 1, Nit: 1, Pre-existing: 1

The fix itself is right. I traced it against both fixtures. In `test_UTF-16BE.txt` (`feff 0068 ... 0064 000a 0074 ...`) the first `read_until(b'\n')` stops after `00 0a` at length 26, so the new guard skips `read_utf16_line` and line 2 stays line 2. In `test_UTF-16BE-complicated.txt` (`feff 4e0a ...`) the read stops after `4e 0a`, the tail isn't `00 0a`, and the old path still runs. Because the BOM sits at bytes 0 to 1, even length means the `0x0A` is a low byte, so the parity check is the correct alignment test. The new test fails on base: the merged line prints as `   1 hello world\nthis is a test\n`. The existing `utf16` test can't see the bug because it runs `--plain`, as the body says.

## Important

**1. Changelog entry still carries the `#XXXX` placeholder** (`CHANGELOG.md:29`).

`CONTRIBUTING.md`, "Changelog entry format": "Please replace `#123` with the number of your pull request (not issue) and `@user` by your GitHub username." The entry reads `see #XXXX (@cindykrafft)`. Change it to `see #4076`.

## Nit

**2. Nothing tests the `len() % 2 == 0` half of the guard** (`src/input.rs:298`).

If someone deletes the parity check, every test still passes. Neither fixture has a first line whose first `0x0A` byte is a high byte right after a `0x00` low byte. The input that breaks is U+0100 followed by U+0A05 (`feff 0100 0a05 000a`): the first read ends at `01 00 0a` (odd length). Without the parity check that would count as a complete line and split U+0A05 in half. A unit test beside `utf16le_issue3367` in `src/input.rs`, asserting `first_line == b"\xfe\xff\x01\x00\x0a\x05\x00\x0a"`, would pin it. The comment above the guard could also say why the length has to be even. Right now it only names the U+4E0A case, which the `ends_with` check covers.

## Pre-existing

**3. `read_utf16_line` ignores code-unit alignment** (`src/input.rs:382-388`, last touched in a995764, before base).

Its end-of-line check compares the last 2 bytes and never looks at parity. So every line after the first can still split mid-character in both encodings:
- BE: U+0100 U+0A05 (`01 00 0a 05`) ends the line at `01 00 0a`.
- LE: U+0A05 U+0100 (`05 0a 00 01`) ends the line at `05 0a 00`.

This PR handles parity correctly for the first read and doesn't make the later reads any worse. It belongs in its own PR.

Would merge once the changelog number is filled in.
