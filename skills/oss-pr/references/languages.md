# House rules by language

Where each language keeps its house rules, and which conventions to read off neighboring files when nothing enforces them. `house.sh` finds the configured tools; this file covers what tools don't decide. Repo config and neighbors always win over anything here.

For every language, read these off the 2 or 3 files nearest your change: naming per kind, error style, comment density and placement, import order, how tests are named and what they assert with.

## TypeScript and JavaScript

- **Enforced by:** Prettier, oxfmt, Biome, or dprint for formatting; ESLint, oxlint, or Biome for linting; `tsc` for types. Check `package.json` devDependencies, not just config files, since some tools run with defaults.
- **Read off neighbors:** semicolons and quote style (when no formatter owns them); `type` vs `interface`; whether option shapes are exported or written inline in the signature; `import type` usage; named vs default exports; ESM vs CommonJS; `node:` prefixes on built-ins; whether files use `function` declarations or arrow constants.
- **Tests:** Vitest, Jest, uvu, node:test, or Mocha. Match the assertion style of tests that exercise the same function, including snapshot use. Match test naming ("should ..." vs plain).
- **Changelog:** a `.changeset/` directory means a changeset per user-facing change, kept as short as recent ones.

## Rust

- **Enforced by:** `cargo fmt` (with `rustfmt.toml` if present) and `cargo clippy`, often with `-D warnings` in CI. Check `[lints]` in `Cargo.toml` and `#![deny(...)]` at crate roots.
- **Read off neighbors:** error handling (`thiserror` enums, `anyhow`, or a crate error type); `unwrap`/`expect` policy outside tests; `// SAFETY:` comments on every `unsafe`; doc comments (`///`) on public items and whether they include examples; `pub(crate)` vs `pub`; module layout (`mod.rs` or `name.rs`).
- **Tests:** inline `#[cfg(test)] mod tests` vs `tests/` directory; `assert_eq!` vs custom helpers; snapshot crates (`insta`, `expect_test`). Prove inline-test fixes with `prove.sh --red-ref`.

## Go

- **Enforced by:** `gofmt` (always), often `goimports` and `golangci-lint` (`.golangci.yml`). `go vet` in CI.
- **Read off neighbors:** error wrapping (`fmt.Errorf("...: %w", err)` vs `errors.Wrap`); doc comments that start with the identifier's name; receiver names; table-driven tests; whether context is the first parameter.
- **Tests:** `_test.go` beside the code; `t.Run` subtests; `testify` vs plain `t.Errorf`. Match whichever the package uses.

## Python

- **Enforced by:** Ruff, Black, isort, Flake8, or Pylint; mypy or Pyright for types. Look in `pyproject.toml`, `setup.cfg`, `tox.ini`, and pre-commit config.
- **Read off neighbors:** docstring style (Google, NumPy, reST, or none); type hints on new code; f-strings vs `%` or `.format`; `pathlib` vs `os.path`; logging setup; comment placement in long literals (next to the item, not above the block).
- **Tests:** pytest vs unittest; fixtures vs setUp; parametrize style; where tests live.

## Zig

- **Enforced by:** `zig fmt`; CI usually runs `zig build test`.
- **Read off neighbors:** error set style, allocator passing, `test "..."` naming, doc comments (`///`).
- **Tests:** inline `test` blocks; prove fixes with `prove.sh --red-ref`.

## C and C++

- **Enforced by:** `.clang-format`, `.clang-tidy`, sometimes `checkpatch` or a project script.
- **Read off neighbors:** include order and guards vs `#pragma once`; brace style; naming (snake vs camel); error returns vs exceptions; license header on every file.
- **Tests:** the project's own harness; mirror the nearest test file.

## Swift

- **Enforced by:** `swift-format` or SwiftLint (`.swiftlint.yml`).
- **Read off neighbors:** access control defaults; `guard` early exits; extension layout; doc comments.
- **Tests:** XCTest vs Swift Testing (`@Test`); match the target's style.

## Ruby, Java, Kotlin

- **Ruby:** RuboCop (`.rubocop.yml`); match string quote and hash syntax of neighbors.
- **Java:** Spotless, Checkstyle, or google-java-format in the build file.
- **Kotlin:** ktlint or detekt; `.editorconfig` often carries ktlint rules.

## Docs repos (MDN, docs sites)

- **Enforced by:** markdownlint, Prettier, and repo-specific linters in `package.json` scripts.
- **Read off neighbors:** the page-type template (where notes, examples, and specs go), macro usage (`{{cssxref(...)}}`), heading levels, and the writing guide the repo links. Reviewers here often rewrite wording; match the voice of the page.
