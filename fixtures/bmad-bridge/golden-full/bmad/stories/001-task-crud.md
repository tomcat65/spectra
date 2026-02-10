# Story 001: Task CRUD API

## Summary
Implement REST endpoints for creating, reading, updating, and deleting tasks.

## Acceptance Criteria
- POST /tasks validates input and persists to PostgreSQL
- GET /tasks returns paginated results with total count
- PATCH /tasks/:id updates only provided fields
- DELETE /tasks/:id sets deleted_at timestamp (soft delete)
- All endpoints require JWT authentication
- Invalid input returns 400 with validation errors

## Technical Notes
- Use NestJS validation pipes with class-validator
- Repository pattern for database access
- Integration tests with Supertest
