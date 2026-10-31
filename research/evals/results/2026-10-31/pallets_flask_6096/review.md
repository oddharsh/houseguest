Important: 1, Nit: 3, Pre-existing: 0

The fix itself is right. Both `partition(":")` calls on a host are gone (I grepped `src/`, and no third one is left). The `testing.py` line now derives the cookie server name the way the Werkzeug client does, with `urlsplit(...).hostname or "localhost"`. Both new tests would fail on base: `"[::1]:8080"` gave host `"["` and hit `int(":1]:8080")`, and the session cookie got stored under domain `"["`, so the follow-up `get` came back `"None"`. The `sn_port is not None` change is needed too, since `.port` returns the int `0` for `"localhost:0"`, which `elif sn_port:` would have dropped.

## Important

**1. The bug fix branches from `main`, and CONTRIBUTING says bug fixes target `stable`.**
The rule, from `pallets/.github/CONTRIBUTING.md` (the org default Flask uses), under "Create a Pull Request": "The "stable" branch is the target for bug and documentation fixes, otherwise the target is "main"." The same file's "Set Up the Repository" section says: "To work on a bug or documentation fix, switch to the "stable" branch".
This PR's base is `514fc6b Merge branch 'stable'`, which is a commit on `main`. `CHANGES.rst` at that commit opens with `Version 3.2.0 / Unreleased`, so the branch can't land on `stable` as-is. Nothing in the diff depends on 3.2-only code (`urlsplit` was already imported in `testing.py` on base), so rebasing the one commit onto `stable` and retargeting should be clean. If you're doing it anyway, add a `CHANGES.rst` line under the next 3.1.x section (optional per the same file, but it's a user-visible fix).

## Nits

**2. `src/flask/app.py:727` now validates `SERVER_NAME`'s port even when the caller passes `port` explicitly.**
`urlsplit(...).port` raises `ValueError` for a non-numeric or out-of-range port. With `SERVER_NAME = "example.com:99999"` and `app.run(port=5000)`, base ran on 5000 (it only called `int(sn_port)` when no port was passed). This PR raises `ValueError: Port out of range 0-65535` before the explicit port is looked at. That only bites a broken config, so I'd merge without it. If you want to keep the old behavior, keep the `SplitResult` and read `.port` inside the `elif` branch instead of up front.

**3. `src/flask/app.py:751` drops `t.cast(str, host)`, which the IPv6 fix doesn't need.**
The cast is a separate typing cleanup. It's probably fine, since mypy should narrow `host` to `str` after the `if not host` block, but I can't run mypy here and it's a second concern in a bug-fix PR. Either revert it or say in the body that `mypy` and `pyright` pass without it.

**4. `tests/test_testing.py:176` builds its own client when the `client` fixture (`tests/conftest.py:50`, `return app.test_client()`) already gives the same object.**
Take `client` as a parameter beside `app`, the way `test_session_transactions` above it does, and delete the line.

Lean: -1 line possible
