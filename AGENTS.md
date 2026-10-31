# Working rules

The user owns the priorities. Carry authorized work through implementation, native verification, and release; a report or plan alone is not the deliverable.

- Choose one concrete user-visible outcome for each work block. State the current result, the remaining blocker, and the next deliverable.
- Timebox a diagnosis to 20 minutes. After two failed attempts, consult authoritative documentation before another attempt. Continue only with a changed hypothesis and a clear stop condition.
- Prefer the smallest correction supported by evidence. Do not build speculative frameworks, caches, instrumentation, or extra variants.
- Run focused tests and one independent review. Repeat only for new code, a failure, or a specific unresolved concern. Do not create repeated evidence/archive/review chains.
- Use specialist subagents for work that needs domain expertise. The root agent coordinates priorities, integration, device testing, and releases rather than substituting for the specialist.
- Delegation is the default for specialized design, implementation, and review. Reuse an available specialist before creating another agent. The root must not silently take over specialist work to bypass a disagreement or a failed check.
- Assign explicit roles as needed: UX/accessibility and information hierarchy; Android backend/performance; iOS/WidgetKit; state-machine/security correctness; independent verification. A role is a working brief, not a claim of human credentials.
- UX decisions belong to the UX specialist. Give that agent the real dimensions, native references, user feedback, readability requirements, and useful-information sizing rule before implementation.
- The UX specialist defines information priority, typography, spacing, icon consistency, supported sizes, and visual acceptance criteria. Platform implementers follow that brief; actual native captures go back to the UX specialist for acceptance or a specific correction.
- Delegate independent implementation or review work with a narrow scope, a clear owner, a timebox, and a concrete deliverable. Respect available concurrency; create additional agents only when their work contributes to the current outcome.
- Every assignment must name its specialist role, intended user outcome, owned files or read-only boundary, necessary evidence, timebox, completion criteria, and handoff. A persona without an owned result is not useful delegation.
- Give each file set one writer. Keep builds, device use, and release ownership coordinated. Close an assignment when its result is accepted; do not grow an unbounded hierarchy of reviews.
- Show useful progress at least every 60 seconds during active work. Publish actual native screenshots when a visual result is ready; label fixtures and incomplete measurements honestly.
- If a work block produces no useful discriminator or deliverable, stop the loop, explain the blocker, reprioritize, and move another authorized outcome forward.
- Preserve unrelated work, user data, credentials, and security protections. Never turn an incomplete or failed check into a pass.
- Finish a verified iteration with a scoped commit and the authorized release. Keep release blockers explicit; do not mark the larger goal complete at a checkpoint.
