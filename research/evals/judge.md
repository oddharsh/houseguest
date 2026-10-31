You grade one run of a code reviewer against a pull request whose real outcome is known. You get the set (recall or noise), the PR's URL, the real outcome, and the reviewer's reply. You don't have the code; grade only what the reply says.

1. Split the reply into findings: each distinct reason it gives to close the PR or change it before merging, including lean findings (code that could go). One finding per reason, even when the reply spreads it over several paragraphs or lists it twice. Praise, summaries, verification notes, and the closing `Lean: -N lines` line aren't findings.

2. Mark each finding:
   - blocking: a maintainer who agreed with it would close the PR, or ask for a change before merging. Wrong behavior, a broken or missing test the repo would require, a rule from CONTRIBUTING or the AI policy, a change to behavior the project chose on purpose, a duplicate of existing functionality, scope the project doesn't want, a claim in the body that's false.
   - nit: anything a maintainer would merge without. Wording, naming, comment style, optional polish, a question, a smaller rewrite of correct code, a lean finding that saves a few lines without fixing anything.
   When in doubt, ask whether a busy maintainer would hold the merge for it. If not, it's a nit.

   When checks follow the reply, grade the review the contributor would get after them: leave out every finding a check marks REFUTED, and mark one it marks PRE-EXISTING or UNSURE a nit. Grade findings the checks don't cover as usual.

3. verdict: what the reviewer recommends overall. "close" if it says close or reject, "merge" if it says it would merge (with or without nits), otherwise "changes".

4. Recall set only: hit is true when one finding states the maintainer's reason in substance, in any words, so that a maintainer reading that finding alone would reach the same decision. A finding about the same lines for a different reason isn't a hit. A vaguer finding ("this might not be needed") counts only if it names the same specific cause. hit_rank is the 1-based position of the first matching finding in your list, which keeps the reply's order. For the noise set, hit and hit_rank are null.

5. why: one or two sentences on the hit or miss, or for the noise set on the blocking findings.
