Important: 0, Nit: 3, Pre-existing: 0
No blocking issues

The fix is in the right place (`InputReader::try_new`, the one path both `OpenedInputKind`s go through), the empty-input guard earns its place (without it, a tty stdin closed with Ctrl-D would need a second Ctrl-D, because `read_until` calls `fill_buf` again on an empty `BufReader`), and the changelog entry follows CONTRIBUTING.md's format. The integration test `header_binary_with_null_after_first_line` fails on base (first line `packet-header\n` has no NUL, so base prints no `<BINARY>`) and passes here. Would merge.

## Nits

**1. The fallback comment names the wrong case, and the body leaves out the limit it implies.** `src/input.rs:282-283` says "A custom BufRead implementation may expose less than 1024 bytes at a time." The case that actually hits this is the stock `BufReader<Stdin>` on a pipe whose first `read()` returns a short chunk. Example: `(printf 'hdr\n'; sleep 1; printf 'x\0y') | bat` still classifies as UTF-8, while the same bytes from a file are `<BINARY>`. That's a fair trade (looping `fill_buf` would add the blocking read the PR deliberately avoids), but say so: reword the comment to "a reader such as a pipe may return fewer bytes on its first read," and add one sentence to the body that detection on streamed stdin only sees what the first read returned.

**2. `fill_buf()?` doesn't retry `ErrorKind::Interrupted`, where the `read_until` it now precedes did.** `src/input.rs:273`. `BufRead::read_until` loops on `Interrupted`; `BufReader::fill_buf` propagates it. So a library caller passing `Input::from_reader(r)` where `r`'s first `read` returns `Interrupted` (a socket reader in a program with a non-`SA_RESTART` signal handler) used to succeed and now gets an error from `InputReader::try_new`. bat's own binary installs no signal handlers, so the CLI can't reach this. Either retry on `Interrupted` before taking the prefix, or note it in the body.

**3. `CONTENT_INSPECTION_LIMIT` restates a private constant of `content_inspector`, and the truncation it drives isn't needed.** `src/input.rs:12`, `:274`, `:282-288`. `content_inspector::inspect` already caps its NUL scan at 1024 bytes, and `has_zip_signature` only checks `starts_with`, so both `.min(CONTENT_INSPECTION_LIMIT)` slices and the `clear()`/`extend_from_slice` copy change nothing about the result. The concrete risk is drift: if `content_inspector` raises its scan size, bat keeps truncating to 1024 and the comment at `:268` goes stale. Inspect whichever buffer is longer instead:

```rust
let buffered = reader.fill_buf()?.to_vec();

let mut first_line = vec![];
if !buffered.is_empty() {
    reader.read_until(b'\n', &mut first_line)?;
}

// read_until may have read past what fill_buf exposed.
let sample = if first_line.len() > buffered.len() { &first_line } else { &buffered };
let content_type = inspect_content_type(sample);
```

The unit test can keep its 1024 boundary as a literal, since that boundary is `content_inspector`'s behavior and the test pins it.

Lean: -8 lines possible
