Important: 1, Nit: 2, Pre-existing: 0

## Important

**1. The PR adds a vendor's promotional link to the project README, and it ships to PyPI too.** `README.md:35`

- The class: third-party promotion in a project-owned surface. Every badge in the README today (`README.md:5-15`) reports on psf/black itself: CI, docs build, coverage, license, PyPI version, Python versions, downloads, conda-forge, code style. The new one advertises a service. Its alt text is "Live demo by Demoshell", the image is served from `build.demoshell.com`, and the link carries `utm_source=badge`, so the vendor gets a tracked referral from every click.
- It doesn't stop at GitHub. `pyproject.toml:123-125` builds the PyPI long description from `README.md` through `hatch-fancy-pypi-readme`, so the next release would put the vendor badge and tracking link on pypi.org/project/black as well.
- The body says why it exists: "I run the service behind this (Demoshell)." The disclosure is honest, but the change is still a commercial author adding their own product to the README. The body also pitches a follow-up: maintainers can "claim that VM if you'd like to support it."
- No issue asked for it. Nothing in the repo or the body backs "the actual binary" or "rebuilds automatically when a new release is published," and maintainers wouldn't control that image. If it lags a release or runs a modified build, users land on it from the official README with the project's implied endorsement.
- I'd close this. If the maintainers ever want a browser demo, that's a decision for an issue first, and it would go in the docs, not the README badge row.

## Nit

**1. The badge line turns into a heading and swallows the horizontal rule.** `README.md:35-36`

The PR puts the badge line directly above the existing `---` with no blank line between them. In Markdown that makes the badge a setext `<h2>`. The rule separating the docs link from "Installation and usage" disappears on GitHub and PyPI. Prettier is in `.pre-commit-config.yaml` for markdown, so the lint job will probably rewrite or flag it too. It's also the only badge written as a Markdown image outside the centered `<p align="center">` HTML block the others share (`README.md:5-15`).

**2. Checklist left unticked.** `.github/PULL_REQUEST_TEMPLATE.md` says: "If any of the following items aren't relevant for your contribution, please still tick them so we know you've gone through the checklist." All 4 boxes in the body are empty.

Lean: -1 lines possible (the whole change; nothing asked for it to exist).
