# Stories

## Story ST-001: Create onboarding endpoint
- AC:
  - POST /onboarding persists a valid profile.
  - Response includes generated onboarding_id.

## Story ST-002: Validate onboarding payload
- AC:
  - Missing required fields return HTTP 400.
  - Validation errors include field-level messages.

## Story ST-003: Emit onboarding audit event
- AC:
  - Successful onboarding publishes event with onboarding_id.
  - Event payload includes partner_id and timestamp.
