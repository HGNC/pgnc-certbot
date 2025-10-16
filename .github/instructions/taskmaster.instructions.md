````instructions
---
description: Taskmaster integration guidelines for certbot service development
applyTo: "**/*"
---

# Taskmaster Integration for Certbot Service

Use Taskmaster to plan and track changes to the certbot image and hooks.

## Common Task Areas

- Hook script enhancements (auth/cleanup)
- Entrypoint improvements and error handling
- Base image updates and security patches
- Renewal automation and monitoring

## Example Task Structure

```json
{
  "id": 1,
  "title": "Improve DNS-01 auth hook retries",
  "description": "Add backoff and retry handling around gcloud dns record-set changes.",
  "status": "pending",
  "priority": "high",
  "subtasks": [
    { "id": 1, "title": "Add retry wrapper function" },
    { "id": 2, "title": "Log structured error messages" },
    { "id": 3, "title": "Test dry-run flow" }
  ]
}
```

## Best Practices

- Keep secrets handling isolated and minimal
- Include dry-run and production modes
- Document required volumes and environment variables
- Tie changes to release workflow runs and tags
````
