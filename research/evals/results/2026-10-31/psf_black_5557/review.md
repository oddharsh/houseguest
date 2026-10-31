Important: 3, Nit: 1, Pre-existing: 0

## Important

**1. The README would advertise a third-party commercial service the core team doesn't run or maintain.** `README.md:35` adds a "Live demo by Demoshell" badge that links to `build.demoshell.com/launch?...&utm_source=badge`. The body says you run Demoshell, the badge "carries a small attribution," and "Otherwise I'll keep taking care of it." So the project's front page would carry a branded, UTM-tracked link to a vendor, and whether it works depends on one outside person and one company staying up. Concrete case: if Demoshell changes its URL scheme, drops the free tier, or shuts down, Black's README points every visitor at a dead or repurposed page, and nobody on the core team can fix the target. Every other link in the badge row (`README.md:5-15`) points at project infrastructure or package indexes (Actions, ReadTheDocs, Coveralls, PyPI, conda-forge, pepy); none promotes a service. There's no linked issue where a maintainer asked for a hosted demo. This is a scope call for maintainers, and I'd decline it: the README isn't the place for demos the core team doesn't maintain.

**2. The new line turns into a heading and swallows the horizontal rule.** `README.md:35` (the badge) sits directly above `README.md:36` (`---`) with no blank line between them. In CommonMark and GitHub-flavored Markdown, a `---` line right under a paragraph line is a setext H2 underline. The badge renders as a `##` heading, and the `---` separator that used to divide the intro from "Installation and usage" disappears. The repo's pre-commit `prettier` hook (`.pre-commit-config.yaml`, `types_or: [markdown, yaml, json]`) will also rewrite this into an ATX `## [![...]](...)` heading, so `pre-commit run -a` (required by `docs/contributing/the_basics.md`) changes the file and the lint job fails. Fix: a blank line between line 35 and `---`, if the line stays at all.

**3. No changelog entry and no request to skip it.** `docs/contributing/the_basics.md` says: "If you feel your PR does not require a changelog entry, please state that and a maintainer can add the `ci: skip news` label to bypass the check." The diff doesn't touch `CHANGES.md` and the body doesn't ask for the label, so `.github/workflows/changelog.yml` (the `grep` for `(#5557)` in `CHANGES.md`) fails on this PR as opened.

## Nit

**4. The checklist is left unticked.** `.github/PULL_REQUEST_TEMPLATE.md` says: "If any of the following items aren't relevant for your contribution, please still tick them so we know you've gone through the checklist." All 4 boxes in the body are empty.

Lean: -1 lines possible (the whole addition at `README.md:35`; per finding 1 it needn't exist in this repo).
