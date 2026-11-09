Important: 2, Nit: 1, Pre-existing: 0

**Important**

1. **Third-party ad in the README, run by the PR author, that also ships to PyPI.** `README.md:35` adds a badge whose image and link both live on `build.demoshell.com`, with `utm_source=badge` tracking on the link. The body says plainly what it is: "I run the service behind this (Demoshell)," "the badge carries a small attribution," and the demo page invites the maintainer to "claim that VM." That's a vendor placement, and nothing in this repo controls it.
   - Concrete case: `pyproject.toml:123-125` builds the PyPI long description from `README.md` (`fragments = [{ path = "README.md" }, { path = "CHANGES.md" }]`). Every release cut after this merges would carry the badge on pypi.org permanently, inside the sdist and wheel metadata. If Demoshell changes the SVG, goes down, or changes hands, those frozen release pages show whatever `build.demoshell.com/v1/embed/badge.svg` serves that day.
   - Every other badge (`README.md:5-15`) points at project status the maintainers own or a neutral index (Actions, ReadTheDocs, Coveralls, PyPI, pepy, conda-forge). None is a commercial service.
   - The body's "the image rebuilds automatically when a new release is published" has nothing behind it in the repo: no workflow in `.github/workflows/` notifies Demoshell, so that's a promise from an outside service, not something the project can check.
   - The need is already covered without a browser VM: `README.md:47-49` points at the standalone executables for running Black without Python, and `docs/getting_started.md:12-19` ("Try it out quickly") gives `black --code "..."`.
   - Fix: drop the line. If the project ever wants a browser playground, that's a maintainer decision for an issue first.

2. **The badge line turns the README's horizontal rule into a heading.** `README.md:35` sits directly above `---` at `README.md:36` with no blank line between them. In CommonMark and GFM, a paragraph line followed by `---` is a setext H2, so GitHub and PyPI (both GFM renderers) render the badge inside an `<h2>` and the thematic break that separated the docs link from "## Installation and usage" disappears. Before this diff, `README.md:34` was blank and `---` rendered as a rule. If anything stays here, it needs a blank line after it.

**Nit**

1. **Changelog check will go red and the body doesn't ask for the skip label.** `.github/workflows/changelog.yml:22-27` greps `CHANGES.md` for `(#<PR number>)` unless the PR carries `ci: skip news`. The contributing docs (`docs/live/.../contributing/the_basics.html.txt:322-324`) say: "If you feel your PR does not require a changelog entry, please state that and a maintainer can add the ci: skip news label." The body leaves all four checklist boxes unticked, and `.github/PULL_REQUEST_TEMPLATE.md` asks: "If any of the following items aren't relevant for your contribution, please still tick them so we know you've gone through the checklist."

Lean: -1 lines possible (the whole diff: `README.md:35` doesn't need to exist, since `README.md:47-49` and `docs/getting_started.md:12-19` already cover trying Black without a setup).

Would not merge; I'd close this one.
