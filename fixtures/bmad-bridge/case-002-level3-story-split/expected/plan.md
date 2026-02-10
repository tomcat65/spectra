# SPECTRA Execution Plan

## Project: BMAD Bridge Case 002
## Level: 3
## Generated: 2026-02-10
## Source: bmad/

---

## Task 001: Define payment audit contract
- [ ] 001: Define payment audit contract
- AC:
  - Contract includes payment_id, status, amount, currency, and failure_code.
  - Contract versioning strategy is documented.
- Files: packages/contracts/src/payment-audit.ts
- Verify: `pnpm --filter contracts test payment-audit`
- Risk: high
- Max-iterations: 7
- Scope: code
- File-ownership:
  - owns: [packages/contracts/src/payment-audit.ts]
  - touches: []
  - reads: [services/payments/src/domain/payment.ts]
- Wiring-proof:
  - CLI: pnpm --filter contracts test payment-audit
  - Integration: contract is imported by payments publisher and integration tests.

## Task 002: Emit success audit events
- [ ] 002: Emit success audit events
- AC:
  - Successful payments emit event with status=success.
  - Event includes required contract fields.
- Files: services/payments/src/audit/publisher.ts
- Verify: `pnpm --filter payments test audit.success`
- Risk: high
- Max-iterations: 8
- Scope: code
- File-ownership:
  - owns: [services/payments/src/audit/publisher.ts]
  - touches: [packages/contracts/src/payment-audit.ts]
  - reads: [services/payments/src/application/handler.ts]
- Wiring-proof:
  - CLI: pnpm --filter payments test audit.success
  - Integration: payment handler -> publisher -> contract serializer.

## Task 003: Implement idempotent failure retry path
- [ ] 003: Implement idempotent failure retry path
- AC:
  - Failed payments emit event with status=failure and failure_code.
  - Retries are idempotent for duplicate callback payloads.
- Files: services/payments/src/audit/retry.ts, services/payments/src/audit/publisher.ts
- Verify: `pnpm --filter payments test audit.retry`
- Risk: high
- Max-iterations: 9
- Scope: code
- File-ownership:
  - owns: [services/payments/src/audit/retry.ts]
  - touches: [services/payments/src/audit/publisher.ts]
  - reads: [services/payments/src/infrastructure/idempotency-store.ts]
- Wiring-proof:
  - CLI: pnpm --filter payments test audit.retry
  - Integration: callback processor -> retry manager -> publisher path validated.

## Task 004: Add audit integration coverage
- [ ] 004: Add audit integration coverage
- AC:
  - Integration test validates schema and publish call for success and failure paths.
  - Retry behavior is verified with duplicated callbacks.
- Files: services/payments/test/audit.integration.test.ts
- Verify: `pnpm --filter payments test audit.integration`
- Risk: high
- Max-iterations: 7
- Scope: code
- File-ownership:
  - owns: [services/payments/test/audit.integration.test.ts]
  - touches: []
  - reads: [services/payments/src/audit/publisher.ts, services/payments/src/audit/retry.ts]
- Wiring-proof:
  - CLI: pnpm --filter payments test audit.integration
  - Integration: tests execute publisher + retry flow with contract assertions.

## Task 005: Update payments audit runbook
- [ ] 005: Update payments audit runbook
- AC:
  - Runbook includes alert routing and replay procedure.
  - Runbook references dead-letter handling steps.
- Files: docs/runbooks/payments-audit.md
- Verify: `markdownlint docs/runbooks/payments-audit.md`
- Risk: medium
- Max-iterations: 4
- Scope: docs
- File-ownership:
  - owns: [docs/runbooks/payments-audit.md]
  - touches: []
  - reads: [docs/architecture/payments-audit.md]
- Wiring-proof:
  - CLI: markdownlint docs/runbooks/payments-audit.md
  - Integration: runbook references live service names and queue topology.

---

## Parallelism Assessment
- Independent tasks: [001, 005]
- Sequential dependencies: [001 -> 002 -> 003 -> 004]
- Recommendation: TEAM_ELIGIBLE
