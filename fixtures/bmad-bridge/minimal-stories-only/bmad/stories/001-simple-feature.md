# Story 001: Add health check endpoint

## Summary
Add a /health endpoint that returns service status.

## Acceptance Criteria
- GET /health returns 200 with JSON body {"status": "ok"}
- Endpoint does not require authentication
- Response includes uptime in seconds

## Technical Notes
- Simple controller, no database dependency
