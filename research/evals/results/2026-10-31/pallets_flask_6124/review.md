Important: 4, Nit: 0, Pre-existing: 0

## Important

**1. The PR reads as AI-generated, which the org policy closes on sight.**

`pallets/.github/CONTRIBUTING.md`, "AI-Generated Contributions": "AI-generated PRs and issues are closed on sight, without review or discussion. This applies regardless of code quality or correctness." The Flask contributing page (`docs/contributing.rst`) defers to that guide, and palletsprojects.com/contributing says every contribution "must follow" the LLM and AI Policy.

What makes this one read machine-drafted:
- The body skips `.github/pull_request_template.md` entirely (no CHANGES.rst entry, no `.. versionchanged::`) and uses a generic "What changed / Testing" shape instead.
- The test command is `uv run --project C:/oss-flask pytest C:/oss-flask/tests -q`. Absolute `--project` and test paths are how an agent harness drives a repo from outside its working directory; a person in the checkout types `pytest`.
- The test (finding 3) asserts something that's already true on the base, and the "492 passed" count stands in for evidence the fix works.

If a person wrote this without an AI tool, say so in the PR. Otherwise the policy decides it.

**2. Teardown now runs before the stream starts, then again after every chunk. That breaks the documented guarantee.**

`src/flask/helpers.py:136-150`. The old code held one extra push (`with ctx:` around the whole `yield from gen`). That push kept `_push_count` above 0 when `wsgi_app` called `ctx.pop(error)` (`src/flask/app.py:1616`), so cleanup waited for the stream to finish. Now the sentinel `yield None` sits outside any push. So:

- `wsgi_app`'s pop drops `_push_count` from 1 to 0 and runs `do_teardown_request`, `request.close()`, `do_teardown_appcontext`, and `appcontext_popped` before the first chunk is sent (`src/flask/ctx.py:483-502`).
- Each `with ctx:` around `next(gen)` (`helpers.py:141`) pushes from 0, so `push()` treats it as a fresh push: it resets the contextvar, sends `appcontext_pushed`, and re-runs `match_request()` routing (`ctx.py:430-444`). The pop then runs the full teardown again. A 1,000-chunk stream runs teardown 1,001 times and routing 1,000 more times, plus both signals per chunk, where the base ran each once per request.
- The `with ctx: gen.close()` in `finally` (`helpers.py:149`) adds one more push and teardown cycle on close.

Concrete breakage:
- The tutorial's `close_db` (`docs/tutorial/database.rst:57`, registered with `teardown_appcontext`) pops and closes `g.db`. A generator doing `for row in get_db().execute("SELECT ..."): yield row` gets its connection closed at the end of the first `next()`. The second chunk raises `sqlite3.ProgrammingError: Cannot operate on a closed database`. The `teardown_appcontext` + `session.remove()` pattern in `docs/patterns/sqlalchemy.rst:66` breaks the same way.
- A view that touches `request.files` and streams from an upload has the `FileStorage` closed by `request.close()` before the generator's first read, so the first read raises `ValueError: I/O operation on closed file`.
- `docs/patterns/streaming.rst:72` promises that `stream_with_context` "will keep the request context active during the generator". `stream_template` and `stream_template_string` go through this same function, so template streaming picks up the same per-chunk cost.

The bug in #6123 is real, but this fix trades away the reason the helper exists. A fix has to keep a single push and pop for the whole stream and only change what happens when finalization lands on a foreign thread. I'd settle that approach in the issue before writing more code.

**3. The new test passes on the base for the wrong reason, and it can't catch finding 2.**

`tests/test_helpers.py:295`, `assert "stream-worker" in teardowns`. On the base, the worker's `client.get("/next")` dispatches a second request whose own `teardown_appcontext` appends `"stream-worker"`, so this assertion holds with or without the fix. What probably fails on the base is pytest's unraisable-exception warning from the generator's `pop()` on the main thread, which `filterwarnings = ["error"]` (`pyproject.toml:108-110`) turns into a failure. I didn't run it, so that part is a likely reading of the code, not a measurement.

The assertion also never pins how many teardowns ran or when. With this PR, the `/stream` request alone appends `"stream-worker"` at least twice (once in `wsgi_app`, once after the chunk), and the test still passes. Two tests would catch it:
- Abandoned stream: assert `teardowns == ["stream-worker", "stream-worker"]` for the two requests (or record the request path, not the thread name), so the `/next` teardown can't satisfy it by itself.
- Normal stream: a 3-chunk generator whose teardown callback runs once, after the last chunk, with `flask.request` still readable inside every chunk.

**4. No changelog entry for a behavior change.**

`.github/pull_request_template.md`: "Add an entry in CHANGES.rst summarizing the change and linking to the issue." The diff touches only `src/flask/helpers.py` and `tests/test_helpers.py`. Teardown timing for every streamed response is user-visible, so it needs an entry under the unreleased 3.2.0 section with `:issue:`6123``.
