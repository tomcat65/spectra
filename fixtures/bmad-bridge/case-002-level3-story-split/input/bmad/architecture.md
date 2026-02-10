# Architecture

## Services
1. `services/payments` publishes payment lifecycle events.
2. `packages/contracts` defines event schemas.
3. `services/audit-consumer` consumes and archives events.

## Ownership Hints
1. Story ST-001 owns `packages/contracts/src/payment-audit.ts`.
2. Story ST-002 owns `services/payments/src/audit/publisher.ts` and `services/payments/src/audit/retry.ts`.
3. Story ST-003 owns `services/payments/test/audit.integration.test.ts`.
4. Story ST-004 touches runbook docs in `docs/runbooks/payments-audit.md`.
