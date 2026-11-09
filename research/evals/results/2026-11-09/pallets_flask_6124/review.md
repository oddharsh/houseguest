Important: 4, Nit: 0, Pre-existing: 1

## Important

**1. The request context is torn down before the body runs, then torn down again on every chunk.**

`stream_with_context` used to push `ctx` once at the sentinel and hold it until the stream closed. That extra push is what keeps `ctx._push_count` above 0 when `wsgi_app` calls `ctx.pop(error)` at `src/flask/app.py:1616`, so cleanup waits for the stream (`src/flask/ctx.py:481-484`: "It will only trigger cleanup once it has been popped as many times as it was pushed").

The PR drops that push at the sentinel (`src/flask/helpers.py:136` now yields with nothing pushed). So:

- `wsgi_app`'s pop at `app.py:1616` takes the count from 1 to 0 and runs `do_teardown_request`, `request.close()`, `do_teardown_appcontext`, and `appcontext_popped` before the first chunk is produced.
- Each `with ctx:` at `helpers.py:140` pushes from 0 again: it re-sends `appcontext_pushed`, re-runs `match_request()` (`ctx.py:433-445`), and its exit runs the full teardown again.
- The `finally` at `helpers.py:149-150` pushes once more just to call `close()`, even on an exhausted generator, for one more full teardown.

A stream of N chunks now runs every teardown callback N+2 times, the first time before the body starts. Concrete breakage:

- The tutorial's `close_db` teardown (`docs/tutorial/database.rst:57-61`, `g.pop('db')` then `db.close()`) closes the connection before a generator that streams rows from it reads the first row.
- `request.close()` closes uploaded files, so a generator that reads `request.files["f"].stream` gets a closed file.
- Any teardown that isn't idempotent (logging, metrics, releasing a lock) fires once per chunk.

This contradicts the docstring in the touched function, `helpers.py:66-69` ("runs inside the current request context ... even though at the point the generator runs the request context will typically have ended"), and `docs/patterns/streaming.rst:72` ("This will keep the request context active during the generator"). None of the existing streaming tests count teardowns, which is why 492 passing doesn't show it. The fix has to keep one push held across the whole stream and solve the cross-thread close inside that.

**2. The new test's assertion passes with or without the fix.**

`tests/test_helpers.py:295` asserts `"stream-worker" in teardowns`. On HEAD that's satisfied by `wsgi_app`'s own pop on the worker thread (finding 1), before the stream is touched. On base it's satisfied by the `/next` request at line 285, whose teardown also runs on `stream-worker`. If the test fails on base at all, it fails because the main-thread close raises inside generator finalization and `filterwarnings = ["error"]` (`pyproject.toml:108-110`) turns the unraisable warning into an error, which the assertion doesn't name.

The PR template (`.github/pull_request_template.md`) says: "Add tests that demonstrate the correct behavior of the change. Tests should fail without the change." The body doesn't show a red run on base. Two checks would pin the claim:

- In `worker`, before `client.get("/next")`, assert `flask.globals._cv_app.get(None) is None`. That's the stale context the body says it prevents.
- Assert the exact teardown list. Teardown should run once for the stream and once for `/next`, so `teardowns == ["MainThread", "stream-worker"]`. HEAD would produce 4 entries, catching finding 1.

**3. No changelog entry.**

`.github/pull_request_template.md`: "Add an entry in CHANGES.rst summarizing the change and linking to the issue." `CHANGES.rst` isn't in the diff. A behavior change to `stream_with_context` also falls under the same template's "Add `.. versionchanged::` entries in any relevant code docs."

**4. The AI policy applies, and the body has the marks of tool output.**

`pallets/.github/CONTRIBUTING.md` (quoted in `policy.md`): "AI-generated PRs and issues are closed on sight, without review or discussion. This applies regardless of code quality or correctness." I can't prove authorship from the text. Still, the body's Testing section carries a local harness path (`uv run --project C:/oss-flask pytest C:/oss-flask/tests -q`) and a "What changed / Testing" template with a pass count. The issue and PR also sit on consecutive numbers (#6123, #6124). If a maintainer reads it that way, it's closed regardless of findings 1 to 3. If it's hand-written, drop the harness paths and say what you ran.

## Pre-existing

- The cross-thread failure comes from `AppContext.pop` requiring `ctx` to be the active context in the calling thread's `contextvars` (`src/flask/ctx.py:464-478`), and from `_cv_app.reset(self._cv_token)` at `ctx.py:498` using a token from another context. A generator closed by GC on another thread hits that check. The diff doesn't touch these lines; it routes around them by never holding the push, which causes finding 1.

Would not merge as is.
