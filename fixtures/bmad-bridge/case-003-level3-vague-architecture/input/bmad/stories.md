# Stories

## Story ST-101: Implement partner delta fetch
- AC:
  - Delta API client fetches paginated changes.
  - Cursor state is persisted between runs.

## Story ST-102: Apply idempotent catalog updates
- AC:
  - Duplicate delta events do not create duplicate writes.
  - Partial failures are retried safely.

## Story ST-103: Add sync observability dashboard notes
- AC:
  - Dashboard sections are documented for success, failure, and retry rate.
  - Alert thresholds are listed.
