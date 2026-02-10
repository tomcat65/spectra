# Story 002: Inventory Stock Management

## Summary
Implement inventory service that reserves and releases stock based on order events.

## Acceptance Criteria
- Stock reservation decrements available count atomically
- Concurrent reservations don't oversell (optimistic locking)
- Stock release on order cancellation restores count
- GET /inventory/:sku returns current stock level

## Technical Notes
- PostgreSQL advisory locks for atomic decrement
- Event listener for order-placed and order-cancelled events
- Separate database from orders service
