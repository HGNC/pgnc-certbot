````instructions
---
description: Guidelines for continuously improving certbot rules based on emerging patterns and operational best practices.
applyTo: "**/*"
---

# Self-Improvement Guidelines for Certbot Service

## Rule Improvement Triggers

- New certbot flags or behavior changes
- Repeated operational issues with DNS-01 challenges
- Updated Google Cloud SDK authentication patterns
- Emerging best practices for ACME automation

## Analysis Process

- Compare hook scripts against recent certbot docs
- Validate idempotency and error handling in hooks
- Ensure environment variables and secrets are properly used
- Monitor certbot logs from workflow runs

## Rule Updates

- Add rules when:
  - New hook patterns prove reliable
  - Common errors can be prevented
  - Security posture can be improved (e.g., least-privilege keys)

- Modify rules when:
  - Certbot or gcloud CLI changes flags
  - Better retries/backoff patterns emerge

## Example Pattern Recognition

```bash
# Ensure gcloud auth is in place before DNS updates
gcloud auth activate-service-account --key-file=/gcp-key.json
```

## Quality Checks

- Hooks must be idempotent and handle retries
- Secrets must never be logged
- Dry-run support should be documented

## Continuous Improvement

- Track expirations and automate renewals
- Pin base images to avoid unexpected breakage
- Keep release notes updated with operational gotchas
````
