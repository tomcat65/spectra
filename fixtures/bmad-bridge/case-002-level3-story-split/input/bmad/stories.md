# Stories

## Story ST-001: Define payment audit contract
- AC:
  - Contract includes payment_id, status, amount, currency, and failure_code.
  - Contract versioning strategy is documented.

## Story ST-002: Publish payment audit events with retry guarantees
- AC:
  - Successful payments emit event with status=success.
  - Failed payments emit event with status=failure and failure_code.
  - Retries are idempotent for duplicate callback payloads.

## Story ST-003: Verify end-to-end audit publishing
- AC:
  - Integration test validates schema and publish call for success and failure paths.
  - Retry behavior is verified with duplicated callbacks.

## Story ST-004: Update payments audit runbook
- AC:
  - Runbook includes alert routing and replay procedure.
  - Runbook references dead-letter handling steps.
