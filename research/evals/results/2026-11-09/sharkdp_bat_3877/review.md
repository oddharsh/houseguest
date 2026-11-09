Important: 1, Nit: 2, Pre-existing: 1

The fix targets the right spot and both new tests fail on `base` (the unit test sees `a\n` as the whole sample; the integration test's `packet-header\n` first line has no NUL). The changelog entry follows the CONTRIBUTING.md format. One regression in error handling stands between this and a merge.

## Important

**1. The new `fill_buf()` call drops the `Interrupted` retry that `read_until` gave the first read.**

- `src/input.rs:273`: `let buffered = reader.fill_buf()?;`

On `base`, the first read went through `BufRead::read_until`, which std documents as ignoring every `ErrorKind::Interrupted` and retrying. `BufReader::fill_buf` makes one `read` call and returns its error as is. So the first read of every input now fails on EINTR where it used to retry.

Concrete case: a library user calls `PrettyPrinter::input_from_reader(r)` (or `Input::from_reader`) with a reader whose first `read()` returns `io::Error::from(io::ErrorKind::Interrupted)` and then returns data. This happens with a socket or pipe read in a process that installed a signal handler without `SA_RESTART`. On `base`, `Input::open` succeeds and prints the data. On HEAD, `try_new` returns `Err` and bat reports "Interrupted system call" for that input. Every later line read still goes through `read_until` and still retries, so only the new call behaves differently.

Fix: retry `Interrupted` around the `fill_buf()` call the way `read_until` does. Add a test next to `input_open_returns_initial_read_errors` (`src/input.rs:481`) with a reader that returns `Interrupted` once and then `b"text\n"`, and assert `content_type == Some(ContentType::UTF_8)`.

## Nits

**1. The fallback comment names the wrong trigger, and the body leaves out the limit that follows from it.**

`src/input.rs:282` says "A custom BufRead implementation may expose less than 1024 bytes at a time." The common case is stdin. `controller.rs:116` passes `io::stdin().lock()`, whose `fill_buf` returns one `read(2)`: one line on a terminal, one chunk on a pipe. So the fallback runs for ordinary `cmd | bat`. It also means piped binary still slips through when the producer's first write ends before the NUL, e.g. `{ printf 'hdr\n'; sleep 0.1; printf 'x\0'; } | bat` is still detected as UTF-8. Name stdin in the comment, and add one sentence to the body's Compatibility section saying piped input only gets the bytes of its first read inspected.

**2. `CONTENT_INSPECTION_LIMIT` restates a limit `content_inspector` already enforces (lean, rungs 1 and 4).**

The body says "`content_inspector` checks up to 1024 bytes", and `inspect_content_type` adds only a `starts_with` ZIP check. Passing the whole buffered slice or the whole first line gives the same answer as truncating both to 1024. Dropping the constant (`src/input.rs:12`) and both `.min(CONTENT_INSPECTION_LIMIT)` slices (`src/input.rs:274`, `284`-`287`) reduces the block to a plain choice of the longer sample:

```rust
let buffered = reader.fill_buf()?.to_vec();
let mut first_line = vec![];
if !buffered.is_empty() {
    reader.read_until(b'\n', &mut first_line)?;
}

// stdin can return less than the first line in one read
let sample = if first_line.len() > buffered.len() {
    &first_line
} else {
    &buffered
};
let content_type = inspect_content_type(sample);
```

The copy grows from 1 KiB to at most 8 KiB (`BufReader`'s default capacity), which doesn't register next to opening a file. The second half of `binary_detection_scans_beyond_first_line_and_preserves_input` (`src/input.rs:447`-`453`, NUL at byte 1024 stays UTF-8) then goes too. It pins `content_inspector`'s internal scan size rather than anything bat decides, and it would break on a dependency bump that changes no bat behavior.

## Pre-existing

**1. `read_line_unbuffered` has the same missing `Interrupted` retry.** `src/input.rs:328` calls `self.inner.fill_buf()?` directly, so `--unbuffered` mode fails on EINTR where the buffered path retries. It dates from 167dda6 (`--unbuffered`, #3583), before `base`, and this PR doesn't touch it.

Request changes for Important 1. With that fixed I'd merge.

Lean: -12 lines possible
