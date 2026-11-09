Important: 0, Nit: 2, Pre-existing: 0
No blocking issues

Would merge. It's test-only, it drops both imports from the private `_pytest` package (`tests/conftest.py`, `tests/test_cli.py`), and every remaining call is public `MonkeyPatch` API. Policy checks:

- AI policy (`pallets/.github/CONTRIBUTING.md`, "AI-Generated Contributions"): nothing in the diff or body reads as machine-written. The body has a human typo ("it actually lead to") and double spaces after periods, and it argues its own trade-off in plain terms.
- PR template (`.github/pull_request_template.md`): it links an issue (`Fixes #6071`). No CHANGES entry is needed, since CONTRIBUTING says "Don't add an entry for changes that only affect documentation or project internals."

I checked the body's example against the old code, and it holds. Old `test_load_dotenv` appended `(os.environ, "FOO", notset)`, so its teardown deleted a user-set `FOO` for the rest of the session. That made `test_dotenv_optional` and `test_disable_dotenv_from_env` pass in a full run and fail alone with `FOO` set in the shell. The two added `monkeypatch.delenv("FOO", False)` lines fix exactly that.

For the 5 standard keys, the new per-test `delenv` still gives every test a clean start, even after code under test writes `os.environ` directly (`src/flask/cli.py:481` `FLASK_DEBUG`, `src/flask/cli.py:675` `FLASK_RUN_FROM_CLI`). The next test's fixture records the leaked value and deletes it. No session- or module-scoped fixture in `tests/` could see a leak between tests.

I couldn't check the pytest 9.1 claim offline: `uv.lock` pins pytest 9.0.3, and the body quotes no failure. Reaching into `monkeypatch._setitem` is fragile on its face, though, so the change stands on that alone.

## Nits

**1. `tests/conftest.py:24`: the bare `yield` does nothing.** The fixture has no teardown of its own; the `delenv` calls register on `monkeypatch`, whose own teardown undoes them. Neighbors with no teardown just return (`modules_tmp_path`, `site_packages` in the same file). Delete `yield` and the blank line above it, and the fixture still runs before each test.

**2. `tests/test_cli.py:536-537` and `559-560`: the dotenv keys now leak for the rest of the session.** The deleted comment ("can't use monkeypatch.delitem since the keys don't exist yet") named this case. `monkeypatch.delenv(item, False)` on a missing key records nothing, so `load_dotenv()` leaves `FOO=env`, `BAR=bar`, `SPAM=1`, and `HAM=火腿` behind after `test_load_dotenv`, and `test_dotenv_path` leaves `EGGS=0`. Before this PR, both tests deleted those keys at teardown. Nothing in the suite breaks today: the only tests that assert on these keys are the two this PR patched. The body discloses the trade-off and argues for it, so I'd merge as is. If you'd rather keep the old guarantee, `monkeypatch.setenv(item, "")` before each `delenv` makes `monkeypatch` record the key as unset, so teardown removes it again.

Lean: -2 lines possible
