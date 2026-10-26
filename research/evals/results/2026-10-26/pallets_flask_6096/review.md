Review of pallets/flask PR "Fix `.partition(":")` usage on potential IPv6 addresses" (fixes #6093, author lkk7, 1 commit, +23/-5).

The fix is correct and covers both call sites. A grep of src/ at HEAD finds no remaining `partition(":")`, `split(":")` or `rsplit(":")` on host strings. The testing.py change copies werkzeug's own `Client`. Both `_add_cookies_to_wsgi` and `run_wsgi_app` in werkzeug 3.1.8's test.py already use `urlsplit(...).hostname or "localhost"`. Both new tests fail without the fix, judging from the code (the sandbox wouldn't let me run them):
- Old `"[::1]:8080".partition(":")` gives host `"["` and port `":1]:8080"`, so `int()` raises.
- The old cookie domain `"["` never matches werkzeug's `"::1"`, so the session comes back as `"None"`.

I'd request changes on 1 item and then merge.

## Findings, most likely first

1. **No CHANGES.rst entry.** The PR template the author left in the body says "Add an entry in CHANGES.rst summarizing the change and linking to the issue." The diff doesn't touch /private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/pallets_flask_6096/repo/CHANGES.rst, and its 3.2.0 Unreleased section has nothing about IPv6 or #6093. The fix: add one line, something like "`app.run` and `session_transaction` handle IPv6 hosts in `SERVER_NAME` and `base_url`. :issue:`6093`".

2. **Unrelated edit at src/flask/app.py:751.** Dropping `t.cast(str, host)` from the `run_simple` call has nothing to do with IPv6. `sn_host` is now `str | None` (from `.hostname`) rather than `str`, so the cast is still valid. I couldn't run mypy or pyright offline, so I can't say whether removing it is safe under the repo's type checkers. If neither one needs it, leave the line alone and keep the diff on the bug.

3. **The body doesn't say what changed.** "Replace them with alternatives" leaves out the actual approach: `urlsplit(...).hostname/.port`, the same as werkzeug's `Client`. It also skips the 1 behavior change a reviewer would ask about: `.hostname` lowercases. `SERVER_NAME="MyHost:8080"` now gives `run_simple` the host `myhost` instead of `MyHost`. Hostnames are case-insensitive, so it doesn't matter in practice, but one sentence would settle it. It would also help to note that `sn_port is not None` is needed because `"localhost:0"` now gives the int `0` (falsy) instead of the string `"0"` (truthy). The existing `localhost:0` case covers this.

4. **AI policy check.** pallets/.github CONTRIBUTING.md:22-23 says "AI-generated PRs and issues are closed on sight." Nothing here reads as machine-written: the body is 2 terse lines plus the stock template comment, there's no tool trailer, and the diff is idiomatic. No finding, just noting I checked.

Edge cases I checked with stdlib `urlsplit` that don't change outcomes:
- `localhost:abc` and `::1` unbracketed still raise ValueError, as before.
- `localhost:` still falls back to port 5000.
- `localhost:70000` now raises at parse time instead of inside `run_simple`. It fails either way.

## Lean

- tests/test_testing.py, new `test_session_transaction_ipv6`: it takes `app` and then calls `client = app.test_client()`. The `client` fixture already does exactly that (tests/conftest.py:50-51), and the neighbor `test_session_transactions(app, client)` uses it. Taking `client` as a parameter deletes 1 line.
- src/flask/app.py:751: revert the `t.cast` removal (finding 2). Net 0 lines, but 1 fewer line to review.
- The `or "localhost"` fallback in testing.py:180 stays, because it's the exact pattern werkzeug uses at the matching call sites.

Lean: -1 lines possible

Would merge once the CHANGES.rst line is added (and, ideally, the cast change is reverted).

Network: none
