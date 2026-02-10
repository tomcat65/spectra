# Story 003: Shared Event Contracts

## Summary
Define shared TypeScript types for inter-service events and DTOs.

## Acceptance Criteria
- OrderPlacedEvent schema with orderId, items, total, timestamp
- PaymentAuthorizedEvent schema with orderId, transactionId, amount
- StockReservedEvent schema with orderId, reservations array
- All events extend BaseEvent with correlationId and version

## Technical Notes
- Lives in shared/contracts/ package
- Published as internal npm package
- Both orders and inventory services consume these types
