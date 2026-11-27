# PR #9 · Add a nonce Content-Security-Policy guard test

## Findings fixed during review

- **Medium — Inline tag exemptions.** The original scan accepted any opening tag containing `src=`, `ColocatedHook`, or `CSP.nonce(`. The guard now inspects attribute names and values, limits the source and hook exemptions to scripts, and checks the nonce attribute on inline tags. Regression cases cover misleading attribute values and mixed-case tags.
- **Medium — Event attributes.** Scanning one source line at a time missed handlers with mixed-case names or a newline before the value. The guard now checks attributes across the opening tag, including unquoted values, and ignores handler-like text inside a quoted title.
- **Low — JavaScript coverage.** The bundle tests iterated an empty list and relied on a manually maintained list for future coverage. The guard now checks the module’s bundle declaration and files under `lib` and `priv`, including JavaScript module extensions. The contributor guide calls for extending coverage when the first bundle is added.

This is a static regression test for source markup. Browser rendering and dynamically assembled markup are outside its coverage.

## Verification

All 71 tests passed with PostgreSQL integration enabled. An isolated template containing an unnonced style and a multiline event handler produced both expected file and line diagnostics. The full `mix precommit` gate passed, including the dependency audit, strict Credo and Dialyzer.
