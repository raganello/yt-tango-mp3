# CODEX_CONTRACT.md

This repository is governed by the following non-negotiable rules
when using Codex or any automated editing tool.

== CRITICAL RULES

1. Do NOT remove, rename, or simplify any existing functionality
   unless explicitly instructed.

2. Batch mode, retry logic, throttling, dry-run semantics, and
   all CLI flags are mandatory and must remain intact.

3. No silent regressions are allowed.
   Any removed or changed behaviour MUST be explicitly documented.

4. Do not refactor for style, brevity, or "cleanup" unless asked.

5. Output MUST be diffs or direct file edits.
   Prose-only summaries are insufficient.

== Test Harness Separation (Non-Negotiable)

Production code MUST NOT embed test harness logic.

- yt_tango_mp3.py is production code only.
- All test logic, assertions, and control flow MUST live in
  run_yt_tango_mp3_tests.sh.
  - Tests must be black-box and invoked externally.
  - Any PR embedding test logic into production code MUST be rejected.

This rule exists to prevent test contamination of runtime behavior.


== INVARIANTS (must hold after every change)

- Batch mode exists and works
- --dry-run is purely observational
- --skip-if-exists / --overwrite semantics preserved
- MP3 encoding is explicit (libmp3lame, 320 kbps CBR)
- ID3 metadata is written and validated
- Script version is single-source and not duplicated
- File size must not shrink unexpectedly

== REQUIRED PRACTICE

For every change, the editor MUST list:
- Features modified
- Features explicitly preserved

If any invariant cannot be met, STOP and explain why.

