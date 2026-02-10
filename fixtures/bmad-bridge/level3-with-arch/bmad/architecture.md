# Architecture — Multi-Service Order System

## 1. Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | TypeScript | Shared types across services |
| Framework | NestJS | Microservice support |
| Database | PostgreSQL | Per-service databases |
| Messaging | RabbitMQ | Event-driven communication |
| Testing | Jest + testcontainers | Integration with real deps |

## 2. Service Boundaries

```
services/
├── orders/
│   ├── src/
│   │   ├── orders.controller.ts     # REST API
│   │   ├── orders.service.ts        # Orchestration + saga
│   │   ├── orders.repository.ts     # Order persistence
│   │   └── events/
│   │       ├── order-placed.event.ts
│   │       └── order-cancelled.event.ts
│   └── test/
│       └── orders.e2e.test.ts
├── inventory/
│   ├── src/
│   │   ├── inventory.controller.ts
│   │   ├── inventory.service.ts     # Stock management
│   │   ├── inventory.repository.ts
│   │   └── events/
│   │       └── stock-reserved.event.ts
│   └── test/
│       └── inventory.e2e.test.ts
├── payments/
│   ├── src/
│   │   ├── payments.controller.ts
│   │   ├── payments.service.ts      # Payment gateway integration
│   │   └── events/
│   │       └── payment-authorized.event.ts
│   └── test/
│       └── payments.e2e.test.ts
└── shared/
    └── contracts/
        ├── order.dto.ts
        └── events.ts                # Shared event schemas
```

## 3. Key Design Decisions

1. **Decision**: Saga pattern for order placement
   - **Rationale**: Distributed transaction across orders + inventory + payments
   - **Compensation**: Cancel payment, release inventory on failure

2. **Decision**: Per-service databases
   - **Rationale**: Service independence, no shared schema coupling
