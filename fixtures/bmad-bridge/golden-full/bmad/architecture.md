# Architecture — TaskFlow API

## 1. Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | TypeScript | Type safety for API contracts |
| Framework | NestJS | Enterprise patterns, WebSocket support |
| Database | PostgreSQL | Relational data, JSONB for metadata |
| Cache | Redis | WebSocket pub/sub, rate limiting |
| Testing | Jest + Supertest | Integration test coverage |

## 2. Component Structure

```
src/
├── tasks/
│   ├── tasks.controller.ts       # REST endpoints
│   ├── tasks.service.ts          # Business logic
│   ├── tasks.repository.ts       # Database queries
│   ├── tasks.gateway.ts          # WebSocket gateway
│   └── dto/
│       ├── create-task.dto.ts    # Input validation
│       └── update-task.dto.ts
├── auth/
│   ├── auth.guard.ts             # JWT guard
│   ├── auth.module.ts
│   └── auth.service.ts           # Token validation
├── common/
│   ├── filters/
│   │   └── http-exception.filter.ts
│   └── interceptors/
│       └── rate-limit.interceptor.ts
└── config/
    └── database.config.ts

test/
├── tasks.e2e.test.ts             # End-to-end REST tests
├── tasks.ws.test.ts              # WebSocket integration tests
└── auth.e2e.test.ts              # Auth flow tests
```

## 3. API Contracts

### `POST /tasks`
**Request:**
```json
{ "title": "string", "description": "string", "assignee": "string" }
```
**Response (201):**
```json
{ "id": "uuid", "title": "string", "status": "pending", "createdAt": "ISO8601" }
```

### `GET /tasks?page=1&limit=20`
**Response (200):**
```json
{ "data": [...], "total": 42, "page": 1, "limit": 20 }
```

## 4. Key Design Decisions

1. **Decision**: Soft-delete over hard-delete
   - **Rationale**: Audit trail preservation, undo capability
2. **Decision**: Redis pub/sub for WebSocket fan-out
   - **Rationale**: Horizontal scaling — multiple API instances share events
