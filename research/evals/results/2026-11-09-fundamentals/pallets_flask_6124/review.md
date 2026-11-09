Important: 4, Nit: 1, Pre-existing: 1

## Important

**1. Teardown now runs after the view returns and again after every chunk, so the stream loses the context it was wrapped to keep.**

The old code held one extra push for the whole stream, which is exactly what `AppContext` is built for. `src/flask/ctx.py:424-425` says "In some situations, such as streaming or testing, the context may be pushed multiple times", and `:454-456` says it "will only trigger cleanup once it has been popped as many times as it was pushed." `CHANGES.rst:375-377` documents the result: the stream's context "will be cleaned up when `response.get_data()` or `response.close()` is called." `docs/patterns/streaming.rst:72-73` promises it will "keep the request context active during the generator."

With this diff nothing is pushed at the sentinel (`src/flask/helpers.py:136`), so:

- `wsgi_app`'s `ctx.pop(error)` (`src/flask/app.py:1616`) drops the count to 0 before the generator body runs. That fires `do_teardown_request`, `request.close()`, and `do_teardown_appcontext` (`ctx.py:490-496`) right away.
- Each `with ctx:` around `next(gen)` (`helpers.py:140-142`) pushes from 0 and pops back to 0. Each one re-sends `appcontext_pushed`, re-runs `match_request` (`ctx.py:433-444`), and runs every teardown again on the way out.
- The `with ctx: gen.close()` at `helpers.py:149-150` runs them once more.

For a 3-chunk generator that's 6 `teardown_appcontext` calls (1 + 3 items + the `StopIteration` call + close) where base makes 1.

Two cases that break:

- Flask's own tutorial. `close_db` (`examples/tutorial/flaskr/db.py:23-30`, registered at `:55`) does `g.pop("db")` and `db.close()`. A streamed `for row in get_db().execute(...): yield render(row)` gets row 1, then the pop closes the connection. The next chunk resumes the cursor and raises `sqlite3.ProgrammingError: Cannot operate on a closed database.` It works on base.
- A view that touches `request.files` and streams from the upload. The upload is closed by `request.close()` (`ctx.py:493`) during `wsgi_app`'s pop. The generator then hits `ValueError: I/O operation on closed file.`

The cross-thread bug in #6123 looks real: a `ContextVar` token can only be reset in the thread that set it. The fix has to keep a single deferred teardown, though. Trading it for per-chunk teardown changes a documented contract, and the body doesn't mention that cost.

**2. The PR reads as agent output, and the org rule closes those without review.**

`pallets/.github/CONTRIBUTING.md` (lines 22-23 in `policy.md`'s copy): "AI-generated PRs and issues are closed on sight, without review or discussion. This applies regardless of code quality or correctness."

What reads as machine-written:

- The body drops the repo's `.github/pull_request_template.md` for a generic `## What changed` / `## Testing` layout.
- The test line is an agent's absolute-path invocation: `uv run --project C:/oss-flask pytest C:/oss-flask/tests -q (492 passed)`.
- The PR number (#6124) directly follows the issue it fixes (#6123).

None of that proves it, but it's the pattern this rule exists for. If a person wrote it, say so in the body in your own words and drop the tool-shaped testing block.

**3. The new test's only assertion passes on base and on HEAD, so it doesn't pin the bug.**

On base, the stream's context never tears down. The `client.get("/next")` at `tests/test_helpers.py:285` still runs its own `teardown_appcontext` on `stream-worker`, so `assert "stream-worker" in teardowns` at `:295` holds.

On HEAD, it already holds after the first request's `wsgi_app` pop, before any cross-thread close happens. I haven't run it (offline). If the test goes red on base at all, I think it's only because the finalizer's `RuntimeError` on the main thread becomes a `PytestUnraisableExceptionWarning`, which `pyproject.toml:108-110` (`filterwarnings = ["error"]`) turns into a failure. The assertion plays no part.

Assert what #6123 is about instead:

- In the worker, after `continue_worker.wait()`, assert `not flask.has_app_context()`.
- Assert the exact `teardowns` list.

On HEAD I'd expect that list to be `["stream-worker", "stream-worker", "MainThread", "stream-worker"]`. Asserting it would have shown both the per-chunk teardown in finding 1 and a teardown running on whatever thread the GC happened on.

**4. No changelog entry.**

`.github/pull_request_template.md`: "Add an entry in CHANGES.rst summarizing the change and linking to the issue." `CHANGES.rst` is untouched, and a change to when teardown runs during streaming needs one most of all.

## Nit

**Stale comments in an untouched test.** `tests/test_testing.py:373` ("stream_with_context pushes a third context, preserved by response") and `:381` ("releasing the context held by stream_with_context") describe the push this diff removes. The test still passes, but its comments now describe code that no longer exists.

## Pre-existing

**Closing the response before the first chunk never calls the wrapped iterator's `close()`.** The sentinel `yield None` sits outside the `try`/`finally` both on base (`helpers.py:133-141` at `base`) and on HEAD (`:136` vs `:138`). So `client.get().close()` with the `Wrapper` from `test_streaming_with_context_and_custom_close` leaves `called == []`. Same behavior before and after; it's not this PR's to fix.
