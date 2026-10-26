## Review: pallets/flask, "Replace the use of private `monkeypatch` fixture API" (fixes #6071)

**Verdict:** I'd request one change, then merge. It's a small test-only fix (+17/-34) for a real compat break. It links an issue as the PR template asks, and the AI policy doesn't apply here. The one problem is that the PR drops env cleanup the old fixtures did on purpose.

### Policy
- The org CONTRIBUTING (pallets/.github) says "AI-generated PRs and issues are closed on sight." I found no AI tells in the body or code. It has double spaces after periods, "lead" where "led" was meant, and plain phrasing. The author is mgorny, a regular downstream packager. No finding.
- The template's CHANGES.rst line doesn't apply to a change that only touches tests. No finding.

### Findings, most important first

1. **The PR deletes the per-test env reset and replaces it with set-at-start, so variables written directly to `os.environ` now leak between tests.**
   - pytest's `delenv(key, raising=False)` records nothing for a key that's absent. It only records keys that exist, so absent keys never get restored. The old line in `tests/test_cli.py` said exactly this: "can't use monkeypatch.delitem since the keys don't exist yet." The PR deleted that comment along with the workaround.
   - Concrete case: in `test_load_dotenv` (tests/test_cli.py:536), `FOO`, `BAR`, `SPAM` and `HAM` are absent, so nothing is recorded. `load_dotenv()` then writes `FOO=env`, `BAR=bar`, `SPAM=1` and `HAM=火腿` straight into `os.environ`. They stay set for the rest of the session. `test_dotenv_path` then leaks `FOO=flaskenv`, `BAR=bar` and `EGGS=0`.
   - The two new `monkeypatch.delenv("FOO", False)` lines (test_cli.py:568 and :577) are partly patching that new leak. Without them, a full run would fail.
   - The same goes for `src/flask/cli.py:481` (`FLASK_DEBUG`), `:675` (`FLASK_RUN_FROM_CLI`) and `:769` (any dotenv key). These write `os.environ` directly. The old `_reset_os_environ` cleared them after every test; that was its whole docstring.
   - Within a test the 5 FLASK_* vars are still clean, because the autouse fixture deletes them at start, so nothing fails today. Still, the body's "it's fine for a test to leave the environment dirty" quietly gives up a guarantee the old code made on purpose.
   - Fix using only stdlib and public API: in `tests/conftest.py`, wrap the fixture body in `with unittest.mock.patch.dict(os.environ):`, pop the 5 keys, then `yield`. That restores the whole environ after each test, including direct writes. It's one import and one `with` line. The repo has no `mock` usage today, but `monkeypatch` has no public "snapshot environ" API, so stdlib is the right rung.

2. **I couldn't verify the "pytest 9.1" claim.** `uv.lock` pins pytest 9.0.3 (py>=3.10) and 8.4.2, and there's no local pytest to check `_setitem` against. #6071 presumably has the traceback. This is a note, not a blocker, since dropping private `_pytest` imports is worth doing either way.

3. **The body overstates the bug.** "`test_disable_dotenv_from_env` ... failed if `FOO` was set while it was run alone" only happens when the developer's shell exports `FOO`. That's true, but it's a contrived case. A clause saying so would be enough; no change to the code.

### Lean (contributor's lines only)
- `tests/conftest.py:23-24`: the trailing blank line plus `yield` do nothing. `monkeypatch` tears itself down and there's no teardown code after the `yield`. Drop both lines and the fixture becomes a plain function. (If you take finding 1's `patch.dict` fix, the `yield` stays, inside the `with`.)
- Nothing else. Nothing duplicates an existing helper, there are no new options or abstractions, and the change sticks to one concern.

Lean: -2 lines possible

Relevant paths:
- /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/pallets_flask_6095/repo/tests/conftest.py
- /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/pallets_flask_6095/repo/tests/test_cli.py
- /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/pallets_flask_6095/repo/src/flask/cli.py

I didn't run the tests. An offline `uv run` failed because a dependency wasn't cached, and the auto-mode classifier denied a second attempt, so everything above comes from reading the code.

Network: none
