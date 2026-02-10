# Product Requirements Document — TaskFlow API

## 1. Overview

**Problem Statement**: Teams need a lightweight task management API with real-time updates.

**Target Users**: Development teams using REST clients or frontend dashboards.

**Success Metric**: API handles 500 concurrent connections with <200ms p95 latency.

## 2. User Stories

### US-1: Create and manage tasks
**As a** team member, **I want to** create, read, update, and delete tasks via REST API, **so that** I can manage my work programmatically.

**Acceptance Criteria:**
- [x] POST /tasks creates a task with title, description, assignee
- [x] GET /tasks returns paginated task list
- [x] PATCH /tasks/:id updates task fields
- [x] DELETE /tasks/:id soft-deletes a task

### US-2: Real-time task notifications
**As a** team lead, **I want to** receive WebSocket notifications when tasks change, **so that** I can monitor progress without polling.

**Acceptance Criteria:**
- [ ] WebSocket endpoint at /ws/tasks
- [ ] Task create/update/delete events broadcast to connected clients
- [ ] Connection authentication via JWT token

## 3. Non-Functional Requirements

- **Performance**: p95 latency < 200ms for REST endpoints
- **Security**: JWT authentication, input validation, rate limiting
- **Scalability**: Support 500 concurrent WebSocket connections

## 4. Scope Boundaries

### In Scope
- REST CRUD for tasks
- WebSocket notifications
- JWT authentication

### Out of Scope
- Frontend UI
- Email notifications
- Task attachments

## 5. Dependencies

- PostgreSQL 15+
- Redis for WebSocket pub/sub
