Important: 6, Nit: 1, Pre-existing: 1

## Important

**1. The PR reads as AI-generated, which the org policy closes on sight.**
`pallets/.github/CONTRIBUTING.md`, "AI-Generated Contributions": "AI-generated PRs and issues are closed on sight, without review or discussion. This applies regardless of code quality or correctness."
The signs, all in `pr-body.md` and the commit:
- A conventional-commit title, `fix(json): ...`. Flask's history doesn't use that format (`git log base`: "explain seek", "support query in methodview").
- Title Case bold sub-headings over one-sentence bullets: "**`os.PathLike` Serialization Support**", "**Dataclass Class Type Guard**".
- "matching standard library behavior and common web framework patterns", a claim that's false (see 5) and names no framework.
- "All 495 pytest unit tests pass cleanly." No output, no command, no mention of pre-commit or mypy.
On a busy day this is the reason I'd close it, before reading the code.

**2. A new feature with no issue.**
`.github/pull_request_template.md`: "Before opening a PR, open a ticket describing the issue or feature the PR will address. An issue is not required for fixing typos in documentation, or other simple non-code changes."
Serializing `os.PathLike` changes what `jsonify` accepts for every app, and the body links no issue. Whether Flask should emit filesystem paths into JSON responses at all is a design call for an issue, not something to decide in review.

**3. Two concerns in one PR, aimed at two different branches.**
The diff bundles a feature (`os.PathLike` support, `src/flask/json/provider.py:113`) with a bug-shaped change (the dataclass class guard, `src/flask/json/provider.py:116`). `pallets/.github/CONTRIBUTING.md`: "The "stable" branch is the target for bug and documentation fixes, otherwise the target is "main"." One PR can't target both.
The dataclass half also doesn't earn its place. Before the change, `app.json.dumps(DataClassType)` already raised `TypeError`, which is the contract `default` documents ("It should return a valid JSON type or raise a ``TypeError``", `provider.py:141-143`). The only thing that changes is the message: "asdict() should be called on dataclass instances, not on classes" becomes "Object of type type is not JSON serializable". The old one tells the user what they did wrong; the new one names `type`. I'd drop this half and its test (`tests/test_json.py:356-364`) rather than split it out.

**4. `str(o)` isn't the path for most `os.PathLike` objects.**
`src/flask/json/provider.py:113` serializes anything that passes `isinstance(o, os.PathLike)` with `str(o)`. `os.PathLike` matches any object with `__fspath__`, and only `pathlib` makes `__str__` return the path. Instances where the output is wrong:
- `os.DirEntry` from `os.scandir("/var/log")`: `str(entry)` is `"<DirEntry 'app.log'>"`, so the JSON gets `"<DirEntry 'app.log'>"`.
- A user class that defines only `__fspath__`: `str(o)` is `"<mod.Thing object at 0x...>"`.
- A dataclass that defines `__fspath__`: it used to reach `dataclasses.asdict` at line 116; the new check at 113 runs first, so it now serializes as its repr, `"Thing(path='x')"`. That's a silent change for existing output.
`os.fspath(o)` returns the actual path; it also returns `bytes` for `os.scandir(b"/var/log")` entries, which `json.dumps` can't encode, so that case needs a decision too. The only test (`tests/test_json.py:349-353`) uses `PurePosixPath`, the one type where `str()` and `fspath()` agree, so it wouldn't catch any of the above.

**5. The body's stdlib claim is false.**
`pr-body.md`: "serializing them as strings (`str(o)`), matching standard library behavior". The standard library doesn't serialize paths: `json.dumps(pathlib.Path("a"))` raises `TypeError: Object of type PosixPath is not JSON serializable`. There's no stdlib behavior to match, so the stated justification for the feature is gone.

**6. The docstring that lists supported types isn't updated.**
`.github/pull_request_template.md`: "Add or update relevant docs, in the docs folder and in code." and "Add `.. versionchanged::` entries in any relevant code docs."
`DefaultJSONProvider`'s docstring (`src/flask/json/provider.py:127-138`) is the documented list of extra types this provider serializes. The PR adds `os.PathLike` to the code at line 113 and leaves the list and its `versionchanged` untouched, so the rendered API docs won't mention it.

## Nit

**Tests don't follow the file's conventions.** `tests/test_json.py:350` and `:357` import `pathlib` and `dataclasses` inside the test body, while the file imports at the top (`tests/test_json.py:1-11`). The neighboring type test, `test_json_decimal` (`tests/test_json.py:191-193`), calls `flask.json.dumps` with no fixture; the new tests take the `app` fixture just to call `app.json.dumps`.

## Pre-existing

**The docstring already omits `decimal.Decimal`.** `src/flask/json/provider.py:127-138` lists `uuid.UUID` but not `decimal.Decimal`, which line 112 at `base` already serializes (blame: 211cce0, David Lord, 2025-06-09). Not this PR's to fix, though fixing 6 puts the author next to it.

Lean: -12 lines possible (drop the dataclass guard back to the original line 115 and delete `test_dataclass_class_raises_typeerror`, `tests/test_json.py:354-365`).

I wouldn't merge this. Under the org policy it closes on 1 alone; even setting that aside, 2 through 4 each need a round.
