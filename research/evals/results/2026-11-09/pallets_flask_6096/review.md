Important: 1, Nit: 2, Pre-existing: 0

The fix itself is right, and it mirrors how Werkzeug's own test client picks the cookie host (`urlsplit(...).hostname or "localhost"`). Both new test cases fail on base: `"[::1]:8080".partition(":")` gives host `"["` and then `int(":1]:8080")` raises, and the session cookie gets stored under domain `"["`, so the follow-up request at `[::1]` never sends it. Dropping the `t.cast` at `src/flask/app.py:751` also checks out, because `host` now narrows to `str` and mypy runs with `strict = true` (`pyproject.toml:131`), which would flag the cast as redundant.

## Important

**1. A bug fix opened against `main` instead of `stable`.**
`pallets/.github/CONTRIBUTING.md`, "Create a Pull Request": "The "stable" branch is the target for bug and documentation fixes, otherwise the target is "main"." The base here is `514fc6b Merge branch 'stable'`, and `CHANGES.rst` opens on `Version 3.2.0 / Unreleased`, so this is `main`. The `.partition(":")` calls in `Flask.run` and `FlaskClient.session_transaction` predate 3.2, so 3.1.x users hit the same `[::1]:8080` crash. Rebase onto `stable` and retarget; a maintainer merges `stable` into `main` afterward, as `514fc6b` shows.

## Nit

**1. Port parsing moved ahead of the explicit-port check.** `src/flask/app.py:727` reads `server_url.port` whenever `SERVER_NAME` is set, even when the caller passed `port`. With `SERVER_NAME = "example.com:abc"` and `app.run(port=8000)`, base ran on 8000 because `int(sn_port)` sat behind `elif sn_port:`; HEAD raises `ValueError: Port could not be cast to integer value as 'abc'`. The same goes for an out-of-range port like `example.com:99999`. That config is malformed, so failing loudly may be fine, but it's a behavior change the body doesn't mention. Either say so in one line, or keep the `.port` read in the branch that uses it.

**2. The new test builds its own client instead of using the fixture.** `tests/test_testing.py:174-176` does `client = app.test_client()`, while the test right above it, `test_session_transactions(app, client)`, takes the `client` fixture from `tests/conftest.py:50`, which returns exactly that. Take `client` as a parameter and drop the line.

Lean: -1 lines possible
