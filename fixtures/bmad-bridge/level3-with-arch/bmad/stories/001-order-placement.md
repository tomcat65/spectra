# Story 001: Order Placement Service

## Summary
Build the order placement endpoint with saga orchestration for payment and inventory.

## Acceptance Criteria
- POST /orders creates order record in pending state
- Saga orchestrator calls payment service for authorization
- Saga orchestrator calls inventory service for stock reservation
- On success: order transitions to confirmed
- On payment failure: order cancelled, no inventory reserved
- On inventory failure: order cancelled, payment voided

## Technical Notes
- NestJS microservice with RabbitMQ transport
- Saga state machine in orders.service.ts
- Event sourcing for audit trail
