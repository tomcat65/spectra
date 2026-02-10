# Story 002: WebSocket Task Notifications

## Summary
Add real-time notifications via WebSocket when tasks are created, updated, or deleted.

## Acceptance Criteria
- WebSocket gateway at /ws/tasks accepts connections
- JWT authentication on WebSocket handshake
- Task create events broadcast to all connected clients
- Task update events broadcast with changed fields
- Task delete events broadcast with task ID
- Unauthorized connections are rejected with 4001 close code

## Technical Notes
- NestJS WebSocketGateway with Socket.IO adapter
- Redis pub/sub for cross-instance event distribution
- Connection pool limit: 500 concurrent
