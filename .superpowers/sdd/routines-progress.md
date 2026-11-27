# SDD ledger — plan: docs/superpowers/plans/2026-11-26-ios-routines.md
Scope THIS run: Tasks 1-3 only (UX-independent). Tasks 4-6 gated on owner build-13 UX verdict.
BASE: c0252da
Task 1 dispatched (sonnet, agent a4a494f) — suggester + models + tests, source-diff Android constants.
Task 1: complete (commit da2bf9d, review clean). Android constants: threshold 4 / window 7d / ±45min / retain 28d / max 500 / ORDER-INDEPENDENT sorted-key signature. Tests assert Android behavior. 276 tests, app build SUCCEEDED (controller-verified).
Task 2 BASE: da2bf9d
Task 2: complete (commit 8da1b78, review clean). ActionHistoryStore in HearthKit, injectable defaults, production-path tests. 281 tests, app build SUCCEEDED (controller-verified).
Task 3 BASE: 8da1b78
