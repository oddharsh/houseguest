I'd close this. The PR adds one line to `README.md`: a commercial vendor's badge, linking to a service the author runs. On top of that, the line is misplaced and breaks the markdown it sits in.

**Reasons to close or request changes, most likely first:**

1. **It's a vendor placement.** The body says so: "I run the service behind this (Demoshell)". Both the badge text ("Live demo by Demoshell") and the hosted SVG advertise the vendor. The link carries `utm_source=badge`, so the vendor gets referral analytics from black's README. The body also pitches the maintainers ("allows the maintainer to claim that VM if you'd like to support it"). No issue asked for this and nothing in the repo points at it. The maintainer comments in the policy sweep call this kind of PR "frivolous... do not file slop PRs using automated tooling" (#5088, #5089, ichard26).

2. **It would ship to PyPI on every release.** `pyproject.toml:123-125` builds the PyPI long description from `README.md` (`fragments = [{ path = "README.md" }, ...]`). The vendor badge and tracking link would land on black's PyPI page, and a description can't be edited after upload. The project would also be relying on a third party's host to serve `build.demoshell.com/v1/embed/badge.svg`. If that host goes down or gets repurposed, a broken or swapped image shows up on PyPI and GitHub.

3. **It turns the horizontal rule into an H2 heading.** The badge sits on `README.md:35`, directly above `---` at line 36, with no blank line between them. That's a setext heading. I rendered lines 33-38 with markdown-it-py: the badge comes out as `<h2><a ...><img alt="Live demo by Demoshell" ...></a></h2>`, and the separator before "Installation and usage" is gone. On GitHub and PyPI the badge would show up as a section heading in the table of contents.

4. **The lint check should fail.** The repo runs prettier through pre-commit (`.pre-commit-config.yaml:49-53`) with `proseWrap: always` (`.prettierrc.yaml`). Running a local prettier 3.3.3 on the snippet (the repo pins v3.9.8) rewrites the line to `## [![Live demo by Demoshell](...)](...)`. So the hook would rewrite the file, and the author evidently never ran it.

5. **The changelog check will fail.** `.github/workflows/changelog.yml` requires a `CHANGES.md` line with the PR number, or the `ci: skip news` label. The diff has no `CHANGES.md` entry. Every checklist box is unticked, although the template comment says to tick boxes that don't apply. That suggests the template went unread.

6. **The body makes claims the repo can't back.** "The image rebuilds automatically when a new release is published": nothing in `.github/workflows/` (13 workflows, `cut_release.yml` and `pypi_upload.yml` included) notifies Demoshell, so this depends entirely on the vendor's own polling. "It's the actual binary": black ships as a Python package, so "binary" here means whatever image Demoshell built. The snapshot id `demoshell%2Ftui%3Ablack` looks like a generic template (`demoshell/tui:black`), and the reviewer can't verify any of it from the PR.

7. **The pitch reads as boilerplate.** "free for open-source projects (the badge carries a small attribution)" plus the "claim that VM" upsell is pasted outreach copy. The badge it describes is the attribution, and there's no black-specific reasoning anywhere in the body.

**Lean (contributor lines only):**
- `README.md:35`: the line needn't exist. The README already links the docs (line 33) and standalone executables (the Installation section) for people who want to try black without a setup. Delete it, which also clears findings 3 and 4.

Lean: -1 line possible (the whole diff).

Not mergeable in any form.

Files: `/private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/psf_black_5557/repo/README.md`, `/private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/psf_black_5557/repo/pyproject.toml`, `/private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/psf_black_5557/repo/.prettierrc.yaml`, `/private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/run1/psf_black_5557/repo/.github/workflows/changelog.yml`. The markdown snippet I rendered is at `/private/tmp/claude-501/-Users-aadharsh-noodling-houseguest--claude-worktrees-funny-zhukovsky-5c734d/16a36d2f-03b5-4d1b-a46a-86c3f0347f31/scratchpad/mdtest/snip.md`.

Network: none
