Important: 7, Nit: 1, Pre-existing: 1

I'd close this one. The AI policy alone does it, and the code has real problems on top.

## Important

**1. The PR reads as AI-generated, which the org policy closes on sight.**
`pallets/.github/CONTRIBUTING.md`, "AI-Generated Contributions": "AI-generated PRs and issues are closed on sight, without review or discussion. This applies regardless of code quality or correctness." The signs here:
- The title uses a conventional-commit prefix (`fix(json): ...`) that this repo doesn't use; recent commits are plain lowercase ("explain seek", "support query in methodview").
- The body is a bold-numbered, Title Case summary ("**`os.PathLike` Serialization Support**", "**Dataclass Class Type Guard**") with a generic claim nobody checked: "matching standard library behavior and common web framework patterns" (see 7).
- "All 495 pytest unit tests pass cleanly" comes with no output, and the diff would fail the repo's own pre-commit and typing jobs (see 5).

**2. `os.PathLike` objects are serialized with `str()`, which is wrong for any PathLike whose `__str__` isn't its path.**
`src/flask/json/provider.py:113` adds `os.PathLike` to the `str(o)` branch. The protocol is `__fspath__`; `str()` only happens to agree for `pathlib`. Case: `os.DirEntry` is `os.PathLike` and has no `__str__`, so `app.json.dumps(next(os.scandir(".")))` returns `"\"<DirEntry 'src'>\""` instead of the path. Same for any user class that implements only `__fspath__`. The repo already converts PathLike with `os.fspath()`: `src/flask/sansio/scaffold.py:236`. Use that in its own branch. The test at `tests/test_json.py:349` only uses `PurePosixPath`, so it can't catch this; a class defining only `__fspath__` would.

**3. Two unrelated concerns in one PR, and they belong on different branches.**
The diff adds a feature (a new serialized type, `provider.py:113`) and a bug fix (the dataclass-class guard, `provider.py:116`). `pallets/.github/CONTRIBUTING.md`: "The "stable" branch is the target for bug and documentation fixes, otherwise the target is "main"." A new JSON type goes to `main`; the guard, if it's wanted at all (see 4), goes to `stable`. Split them.

**4. The dataclass guard fixes nothing a caller can observe except the error message, and the new message is worse.**
`provider.py:116`. Before this change, `app.json.dumps(SomeDataclass)` (the class) already raised `TypeError`, as the body itself says. That's exactly what `json.dumps`'s `default` contract asks for, and what the `default` attribute's docstring (`provider.py:141-144`) promises: "return a valid JSON type or raise a ``TypeError``." After the change it still raises `TypeError`, but the message goes from "asdict() should be called on dataclass instances, not on classes" to "Object of type type is not JSON serializable", because `type(o).__name__` of a class is `"type"`. The old message named the mistake; the new one doesn't. The test at `tests/test_json.py:356` pins only the message text, which is past the contract. I'd drop this half.

**5. The guard leaves `# type: ignore[arg-type]` unused, which I expect fails the typing CI job.**
`provider.py:117`. The ignore exists because `is_dataclass(o)` narrows `o` to `DataclassInstance | type[DataclassInstance]`, and `asdict()` rejects the `type[...]` arm. `and not isinstance(o, type)` removes that arm, so `o` is `DataclassInstance` and the ignore has nothing to suppress. `pyproject.toml` sets `[tool.mypy] strict = true`, which turns on `warn_unused_ignores`, and `.github/workflows/tests.yaml` runs `tox run -e typing` (mypy) on every PR. I couldn't run it offline; `tox run -e typing` settles it. If you keep the guard (see 4), delete the ignore. The body's "all tests pass" covers pytest only.

**6. PR template steps skipped: no ticket, no docs.**
`.github/pull_request_template.md`:
- "Before opening a PR, open a ticket describing the issue or feature the PR will address." The body links no issue, and a new default-serialized type is a feature the maintainers should agree to first.
- "Add or update relevant docs, in the docs folder and in code." and "Add `.. versionchanged::` entries in any relevant code docs." The `DefaultJSONProvider` docstring (`provider.py:126-138`) lists every extra type the provider serializes; PathLike isn't added there, and there's no `versionchanged`.

**7. The body's claims don't hold against the code.**
- "matching standard library behavior": the standard library doesn't serialize paths. `json.dumps(pathlib.Path("x"))` raises `TypeError: Object of type PosixPath is not JSON serializable`. Nothing in the body says which "common web framework patterns" it means.
- "Added `and not isinstance(o, type)` to properly allow it to fall through to the standard JSON serializability `TypeError`": it was already a `TypeError` (see 4), so "properly" is changing a message.
- "e.g. `pathlib.Path`, `pathlib.PurePosixPath`, `pathlib.PureWindowsPath`": only `PurePosixPath` is tested.
- "All 495 pytest unit tests pass cleanly": no output, and it isn't the check that would fail (see 5).

## Nit

**N1. Imports inside test functions.** `tests/test_json.py:350` (`import pathlib`) and `:357` (`import dataclasses`). The file imports its stdlib modules at the top (`tests/test_json.py:1-4`); put them there.

## Pre-existing

**P1. `decimal.Decimal` missing from the `DefaultJSONProvider` docstring.** `provider.py:126-138` lists datetime, UUID, dataclass, and `__html__`, but `_default` has serialized `Decimal` to `str` since the change in `CHANGES.rst:523`. Not this PR's to fix.

Lean: -11 lines possible (drop the dataclass guard and its test, `provider.py:116` and `tests/test_json.py:356-364`)
