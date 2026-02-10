# Architecture

## Components
1. API Controller (`src/onboarding/controller.ts`)
2. Service Layer (`src/onboarding/service.ts`)
3. Repository Adapter (`src/onboarding/repository.ts`)
4. Audit Publisher (`src/onboarding/audit.ts`)

## Ownership Hints
1. Story ST-001 owns `src/onboarding/controller.ts` and `src/onboarding/service.ts`.
2. Story ST-002 owns `src/onboarding/validator.ts`.
3. Story ST-003 owns `src/onboarding/audit.ts`.
