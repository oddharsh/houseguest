Important: 5, Nit: 1, Pre-existing: 1

## Important

**1. The PR reads as AI-generated, and Pallets closes those on sight.**
`pallets/.github/CONTRIBUTING.md`, "AI-Generated Contributions": "AI-generated PRs and issues are closed on sight, without review or discussion. This applies regardless of code quality or correctness." The palletsprojects.com contributing page adds that all contributions "must follow our ... LLM and AI Policy."
The tells, all in `pr-body.md`:
- Bold numbered headers wrapping one-sentence bullets ("**`os.PathLike` Serialization Support**", "**Dataclass Class Type Guard**").
- Filler claims with nothing behind them: "matching standard library behavior and common web framework patterns", "to properly allow it to fall through".
- A test count with no output: "All 495 pytest unit tests pass cleanly."
- A conventional-commit title (`fix(json): ...`); no commit in this repo's history uses that prefix.
On a busy day this is where the review stops.

**2. A new serialized type with no ticket, bundled with an unrelated change.**
`.github/pull_request_template.md`: "Before opening a PR, open a ticket describing the issue or feature the PR will address." No issue is linked, and the body names no user who hit this.
- `src/flask/json/provider.py:113` adds `os.PathLike` to the set `DefaultJSONProvider` serializes. Which types the provider handles is a design call. The class already documents the extension point for anything else: `default` at `provider.py:140-144` ("Apply this function to any object that :meth:`json.dumps` does not know how to serialize"), and `JSONProvider`'s docstring says to subclass it "to customize JSON behavior." An app that wants paths as strings overrides `default` in 4 lines.
- `provider.py:116` is a second, unrelated concern in the same PR. `pallets/.github/CONTRIBUTING.md` sends bug fixes to "stable" and features to "main", so a bug fix plus a feature can't even pick a target branch. They'd need to be two PRs, each with its own ticket.

**3. The dataclass "guard" fixes no bug and makes the error message worse.**
`provider.py:116`. Before the change, `app.json.dumps(DataClassType)` raised `TypeError: asdict() should be called on dataclass instances, not on classes`. After it, the same call raises `TypeError: Object of type type is not JSON serializable` from `provider.py:122`, because `type(o).__name__` of a class is `"type"`.
Both are `TypeError`, which is what `default`'s contract at `provider.py:141-142` asks for ("return a valid JSON type or raise a ``TypeError``"), so nothing was broken. The input is invalid either way and the caller fixes their data, they don't catch it. The old message named the actual mistake; the new one names `type`. The test at `tests/test_json.py:356-364` only matches `"is not JSON serializable"`, so it locks in the vaguer message. Drop the line and the test.

**4. `str(o)` is the wrong conversion for `os.PathLike`.**
`provider.py:113`. `os.PathLike` is the `__fspath__` protocol; it promises nothing about `__str__`. Inputs that serialize to garbage instead of a path:
- `os.DirEntry` from `os.scandir()`: it's `PathLike` with no `__str__`, so `app.json.dumps(next(os.scandir(".")))` emits `"<DirEntry 'name'>"`.
- Any user class that defines only `__fspath__`: emits `"<mod.Cls object at 0x...>"`.
- A bytes path (`os.scandir(b".")`): `__fspath__` returns bytes, and `str()` hides that instead of failing.
`os.fspath(o)` is the protocol's own accessor; it still needs a decision for the bytes case. The one test (`tests/test_json.py:349-353`) uses `PurePosixPath`, whose `__str__` happens to equal its fspath, so it can't catch any of these. This matters only if the type stays in at all (see 2).

**5. The body claims what the code doesn't show, and the touched docstring is out of date.**
- "matching standard library behavior": the standard library raises here. `json.dumps(pathlib.Path("x"))` is `TypeError: Object of type PosixPath is not JSON serializable`. Nothing in the stdlib serializes paths to JSON.
- "All 495 pytest unit tests pass cleanly": no output, no Python version, no mention of `mypy`/`pyright` (both listed under "Run Tests" in CONTRIBUTING).
- `DefaultJSONProvider`'s docstring at `provider.py:126-137` lists exactly what the provider "Serializes"; the PR adds a type and leaves the list alone. The PR template also asks for "an entry in CHANGES.rst" and "`.. versionchanged::` entries in any relevant code docs"; the diff has neither.

## Nit

**Imports inside test functions.** `tests/test_json.py:350` (`import pathlib`) and `:357` (`import dataclasses`). The file imports stdlib modules at the top (`tests/test_json.py:1-4`: `datetime`, `decimal`, `io`, `uuid`).

## Pre-existing

**`DefaultJSONProvider`'s docstring already omits `decimal.Decimal`.** `provider.py:126-137` lists datetime, UUID, dataclass, and `__html__`, but `_default` has serialized `Decimal` since before the base (`CHANGES.rst:523`). Not this PR's to fix.

Not mergeable. I'd close it under the AI policy. Without that, I'd still turn down the new type (2) and the dataclass line (3), which together are the whole diff.

Lean: -23 lines possible (the whole diff: `os.PathLike` belongs in an app's own `default` override, and the dataclass line plus its test fix nothing).
