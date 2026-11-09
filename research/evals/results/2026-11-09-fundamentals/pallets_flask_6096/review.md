Important: 1, Nit: 3, Pre-existing: 0

The fix itself is right. `urlsplit(f"//{server_name}")` gives `hostname == "::1"` and `port == 8080` for `"[::1]:8080"`, where the old `.partition(":")` gave host `"["` and then `int(":1]:8080")` raised. The `sn_port is not None` change is needed because `sn_port` is now an int and `0` would otherwise fall through to 5000; the existing `"localhost:0"` case in `test_run_from_config` covers that. Both new tests fail on base for the reason the issue gives (`"["` as the run host / cookie domain) and assert exact values. Reading `.hostname or "localhost"` in `testing.py` matches the `urlsplit` already imported and used at `src/flask/testing.py:75`. What I'd ask for is the target branch.

## Important

**1. A bug fix opened against `main` instead of `stable`.**
`pallets/.github/CONTRIBUTING.md`, "Create a Pull Request": "The "stable" branch is the target for bug and documentation fixes, otherwise the target is "main"." The body says this fixes a bug (`Fixes #6093`). The PR's base is `514fc6b Merge branch 'stable'`, a `main`-only commit whose `CHANGES.rst` top section is `Version 3.2.0 / Unreleased`. A `stable` line exists: `CHANGES.rst:33` has `Version 3.1.3`, and both `.partition(":")` lines date from before 3.2 (`git blame` puts them at 2025-03-29 and 2025-05-11). Please rebase onto `stable` and retarget (`gh pr edit --base stable`). The diff touches nothing 3.2-only, so it should apply cleanly.

## Nit

**2. `src/flask/app.py:751` drops `t.cast(str, host)` as a drive-by, and the body doesn't say so.**
The fix doesn't need it. Before and after, `host` is narrowed to `str` by the `if not host:` block at lines 729-733, so the cast was already redundant on base. It's a harmless one-line deletion, but it's a second change the body never mentions. Either add one line to the body ("also drops a cast mypy and pyright no longer need") or leave the line alone.

**3. `server_url.port` now parses eagerly, so an explicit `port` no longer shields a bad `SERVER_NAME` port.**
`src/flask/app.py:727` reads `.port` whenever `SERVER_NAME` is set. With `SERVER_NAME = "localhost:abc"` and `app.run(port=8000)`, base ran on 8000 (it only called `int(sn_port)` when no port was passed); HEAD raises `ValueError: Port could not be cast to integer value as 'abc'`. `"localhost:70000"` now raises "Port out of range" the same way. Both configs are invalid, so I'd merge with this as is, but it's a behavior change the body should own in one sentence, or the `.port` read can move into the `elif` branch.

**4. Title and body.**
The title has an unclosed backtick (`` Fix `.partition(":") usage ``), so it renders as broken code. "Replace them with alternatives" doesn't name the alternatives; the PR template asks to "Describe how it addresses the linked ticket." One sentence covers it: `urlsplit` handles bracketed IPv6 hosts, so `SERVER_NAME = "[::1]:8080"` runs on `::1:8080` and `session_transaction(base_url="http://[::1]:8000/")` stores the cookie under `::1`.

Would merge once it targets `stable`.
