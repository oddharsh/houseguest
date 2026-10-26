Review of sharkdp/bat#3877, "Detect binary content beyond the first line" (repo at /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/sharkdp_bat_3877/repo)

I found nothing that would make me close this. The fix looks correct and I couldn't find a regression. The tests fail if the bug comes back. The CHANGELOG entry matches CONTRIBUTING's format and the "Closes #N, see #PR" style other entries use, and the overlap with #3763 is disclosed. I'd request one simplification, and a sentence in the body about a known limit.

Policy and duplicates
- No AI policy. CONTRIBUTING asks for a changelog entry and an integration test, and the PR has both.
- The overlap with #3763 (same init path, separate issue #2262) is disclosed in the body. I can't see from the shallow history that reading only the first line was a deliberate choice, so it's not an intent conflict.

Correctness (checked by reading, nothing to flag)
- Calling `fill_buf()` before `read_until` doesn't add a read beyond the one `read_until` needs. With interactive stdin, typing "foo\n" still costs exactly one read.
- The `if !inspection_prefix.is_empty()` guard (src/input.rs:278) is needed. Without it, empty input triggers a second `read()` after EOF, so a tty would need Ctrl-D twice. `input_detection_does_not_read_twice` catches its removal: the second read returns WouldBlock, so `try_new` errors.
- The long-first-line fallback (src/input.rs:282-288) matters for pipes. When a read delivers less than the first line, the old code inspected more bytes than the new prefix would.

Findings
1. Known limit missing from the body. Detection still stops at whatever the first read returned. Case: `(printf 'hdr\n'; sleep 1; printf 'x\0y') | bat`. The first `fill_buf` gets only "hdr\n", so the input is UTF_8 and the NUL gets printed. That's no worse than before, but "Root cause" reads as if the 1024-byte scan always happens. One sentence in the body covers it: piped input that arrives in small chunks still gets a shorter inspection.

2. The code duplicates the dependency's own limit. `CONTENT_INSPECTION_LIMIT` and the `.min(...)` calls (src/input.rs:12, 274, 284) repeat a cap that content_inspector applies inside `inspect()`. The PR's own comment at line 268 says so ("content_inspector scans at most 1024 bytes"). I couldn't open the crate source offline; I recall it as `MAX_SCAN_SIZE = 1024` in 0.2.4. `has_zip_signature` only calls `starts_with`, so truncation doesn't affect it either. With the cap gone, the copy, the clear/extend and the constant can all go. Inspect the buffer directly and re-inspect only if the first line ran past it:
   ```rust
   let buffered = reader.fill_buf()?;
   let buffered_len = buffered.len();
   let mut content_type = inspect_content_type(buffered);
   let mut first_line = vec![];
   if buffered_len > 0 {
       reader.read_until(b'\n', &mut first_line)?;
   }
   if first_line.len() > buffered_len {
       content_type = inspect_content_type(&first_line);
   }
   ```
   This behaves the same as the PR, including the empty-input guard and the long-line fallback. It drops the 1 KiB `to_vec()` copy, the constant, and about 10 lines of code and comments.

3. Part of a test pins the dependency. The second half of `binary_detection_scans_beyond_first_line_and_preserves_input` (src/input.rs, from `drop(reader);` to the UTF_8 assertion) moves the NUL to byte 1025 and expects UTF_8. That checks content_inspector's internal cap, not bat code. If the crate raised its limit, this test would fail with no bat bug involved. Drop it, and the tests shouldn't refer to `CONTENT_INSPECTION_LIMIT` (finding 2 removes it): `vec![b'a'; 1024]` with the NUL at index 1023 is enough. The first half (BINARY detection plus the byte-for-byte replay check) is the part worth keeping.

4. Body nit: the em dash in "Validation" ("— clean run: 455 passed, 5 ignored") reads as tooling output. I couldn't check those numbers: the build needs network, which this review didn't use. CI will confirm.

Lean ladder (contributor's lines only)
- Rung 1, code that needn't exist: the constant plus truncation, and the clear/extend fallback (finding 2). That's about 10 lines.
- Rung 1, test: the boundary half of the unit test (finding 3). About 6 lines.
- Rungs 2-4: no existing helper is skipped. The PR reuses `inspect_content_type`, and the integration test copies the setup of `header_zip_file_is_binary`.
- There's only one concern, so nothing needs splitting.

Verdict: I'd merge after finding 2 and the body sentence from finding 1. I'm not blocking on correctness.

Lean: -16 lines possible

Network: none
