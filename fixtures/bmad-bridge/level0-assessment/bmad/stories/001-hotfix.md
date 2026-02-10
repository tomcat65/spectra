# Story 001: Fix null pointer in user lookup

## Summary
Fix crash when looking up a user that doesn't exist.

## Acceptance Criteria
- GET /users/:id returns 404 for non-existent user (not 500)
- Existing user lookup still returns 200 with user data
- Error response includes descriptive message

## Technical Notes
- Add null check in UserService.findById
- Add test case for missing user
