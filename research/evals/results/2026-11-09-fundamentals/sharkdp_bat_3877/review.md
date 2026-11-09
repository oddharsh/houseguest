Important: 1, Nit: 3, Pre-existing: 0

The fix is small, in the right place, and both new detection tests fail on `base`. One branch that keeps the old behavior has no test, so I'd ask for that before merging.

## Important

**1. The fallback branch that keeps first-line detection has no test, so deleting it turns `base`-detected binary into text and nothing goes red.**

`src/input.rs:284-288` replaces the snapshot with the first 1024 bytes of `first_line` when `read_until` had to read past the snapshot. That happens whenever the first `read()` returns a short chunk with no newline in it. A custom `BufRead` can do that, and so can an ordinary `StdinLock` on a pipe.

Concrete case: `(printf 'ab'; sleep 1; printf 'c\0d\n') | bat`. The snapshot is `ab`, `first_line` is `abc\0d\n`. `base` inspects the whole first line and says BINARY. With this PR it says BINARY only because of lines 284-288; remove them and it says UTF-8, which is the bug this PR fixes coming back on a different path.

None of the new tests reach that branch:
- `binary_detection_scans_beyond_first_line_and_preserves_input` (`src/input.rs:435`) reads from a `&[u8]`, whose `fill_buf` exposes all 1025 bytes at once.
- `input_detection_does_not_read_twice` (`src/input.rs:457`) uses inputs that fit in one read.
- `header_binary_with_null_after_first_line` (`tests/integration_tests.rs:2269`) reads a 28-byte file through an 8 KiB `BufReader`.

One unit test covers it: `InputReader::new(BufReader::with_capacity(2, &b"abc\0d\n"[..]))` should give `Some(ContentType::BINARY)`. It passes with the branch and fails without it.

## Nits

**2. The boundary half of the new unit test pins a false negative.** `src/input.rs:447-453` asserts that a file with a NUL at byte 1025 is `UTF_8`. That's `content_inspector`'s own 1024-byte scan limit, not something bat promises; bat's cap at line 274 only bounds the copy. If bat ever scans more of the buffer (the body says #3763 is reworking this same path), a correct improvement turns this test red. Drop lines 447-453; the BINARY half above them already fails on `base`.

**3. The fallback comment names the wrong trigger.** `src/input.rs:282-283` says "A custom BufRead implementation may expose less than 1024 bytes at a time." The common case is bat's own `io::stdin().lock()` (`src/controller.rs:116`) on a pipe whose first `read()` comes back short. Say that, so the next reader doesn't treat the branch as dead code for custom readers only.

**4. The body leaves out the pipe limit.** For stdin, the inspected bytes are whatever the first `read()` returned (or the first line, if longer). So `slow-producer | bat` with a newline in the first chunk and the NUL in a later one still shows as text. That's the right trade-off for not adding a blocking read, and the body already argues it. One sentence under Compatibility saying piped input only sees the first read would keep someone from reopening #3554 for `gpg -d ... | bat`.

Lean: -2 lines possible. Lines 284-288 copy `first_line` into `inspection_prefix` only to pick the longer of two prefixes of the same stream. Keep the `first_line_prefix_len` binding and pick a slice instead (`let sample = if first_line_prefix_len > inspection_prefix.len() { &first_line[..first_line_prefix_len] } else { &inspection_prefix[..] };`), which drops the `clear`/`extend_from_slice` pair and the `mut` on line 272.
