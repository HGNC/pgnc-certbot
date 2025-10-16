````instructions
---
description: VS Code rules guidance for certbot service repository docs and scripts
applyTo: ".github/instructions/*.instructions.md"
---

# VS Code Rules for Certbot Service

## Rule Structure

```markdown
---
description: Clear, one-line description of what the rule enforces
globs: certbot/**/*.sh, certbot/**/*.md, certbot/Dockerfile
alwaysApply: boolean
---

- **Main Points in Bold**
  - Sub-points with details
  - Examples and explanations
```

## Script Examples

```bash
# ✅ DO: Validate required environment variables
: "${MY_EMAIL:?MY_EMAIL is required}"

# ❌ DON'T: Hardcode secrets
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/secret.json
```

## Best Practices

- Shell scripts must be `set -euo pipefail`
- Use `trap` for cleanup on exit
- Avoid logging secrets
- Support `--dry-run` flows
- Document mounts and environment variables in README or instructions
````
