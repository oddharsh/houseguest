Important: 0, Nit: 2, Pre-existing: 0
No blocking issues

I checked the one place this could go wrong: the 5 standard keys. Flask's own code writes 2 of them straight into `os.environ` (`FLASK_RUN_FROM_CLI` at `src/flask/cli.py:675`, `FLASK_DEBUG` at `src/flask/cli.py:481`), so after a `runner.invoke(FlaskGroup())` test they now stay set until the next test starts. The new autouse fixture still deletes them before every test body. No fixture in `tests/` has a wider scope (`git grep "scope=" -- tests` is empty), so nothing runs in that gap. Each test still starts clean, which was the old fixture's job.

The body's claims hold against the code. `test_dotenv_optional` and `test_disable_dotenv_from_env` assert `"FOO" not in os.environ` (`tests/test_cli.py:572`, `:581`), and before this change nothing cleared `FOO` for them. The private `_pytest` imports and `monkeypatch._setitem` pokes are gone from `tests/`, and `delenv(key, False)` matches the call the old fixture already made.

Would merge.

## Nits

**1. `tests/conftest.py:23`: the bare `yield` has no teardown after it.** The fixture only does setup, so it doesn't need to be a generator. Neighbors that have no teardown `return` (`app`, `client`), and `leak_detector` yields only because it asserts afterward. Drop the `yield` and the blank line above it.

**2. Dotenv keys now leak past their test, and the body only half-says so.** `load_dotenv` writes with `os.environ[key] = value` (`src/flask/cli.py:769`). `monkeypatch.delenv` on a key that's absent records no undo. So after `test_load_dotenv` (`tests/test_cli.py:536`), `FOO=env`, `BAR=bar`, `SPAM=1`, and `HAM=火腿` stay set for the rest of the session. After `test_dotenv_path` (`:559`), `EGGS=0` does too. The old `notset` entries deleted them at teardown. The removed comment on `:537` ("can't use monkeypatch.delitem since the keys don't exist yet") recorded that reason.

No current test reads those keys, and the 2 `delenv("FOO")` lines cover the 2 tests that assert on `FOO`. So nothing breaks today, and the body does say a test can leave the environment dirty. It should also say that `test_load_dotenv` and `test_dotenv_path` now do, every run. Otherwise the next test that asserts on `SPAM` or `BAR` will fail depending on test order, and nobody will know why.

Lean: -2 lines possible
