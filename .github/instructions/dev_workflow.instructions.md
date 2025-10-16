````instructions
---
description: Development workflow guidelines for the certbot service
applyTo: "**/*"
---

# Certbot Service Development Workflow

This document provides development workflow guidelines specific to the certbot service. The image bundles Certbot plus helper scripts and Google Cloud SDK for DNS-01 with Cloud DNS.

## Service Overview

- Base image: `certbot/certbot`
- Tools added: curl, python3, pip, bash, git, Google Cloud SDK
- Entrypoint: `/entrypoint.sh` (executes certbot commands; hooks are mounted at runtime)
- Used by docker-compose profile `ssl`

## Development Process

### 1. Making Changes

- Update `entrypoint.sh`, `auth-hook.sh`, `cleanup-hook.sh` as needed
- Keep Dockerfile minimal and reproducible (pin versions if you add tools)
- Use non-interactive certbot flags for automation
- Never commit actual service account keys; mount as secrets at runtime

### 2. Building Locally

```bash
# From repo root
docker build -t pgnc-certbot:local certbot/
```

### 3. Release Process

The certbot service uses automated semantic versioning and releases:

- Commits to the `release` branch trigger automatic releases
- Manual releases can be triggered via GitHub Actions workflow dispatch
- Each release creates:
  - A GitHub Release with auto-generated notes
  - Docker images pushed to `ghcr.io/hgnc/pgnc-certbot` with tags:
    - Semantic version (e.g., `v1.0.0`)
    - `latest`
    - `release`

### 4. Version Management

- Patch: minor script fixes, base image patch bumps
- Minor: new hooks or capabilities
- Major: breaking changes to entrypoint behavior or flags

Use the workflow dispatch inputs to control release type and notes.

## Runtime Notes

- Required mounts: auth and cleanup hooks, service account key (JSON), letsencrypt volume
- Ensure `gcloud auth activate-service-account --key-file=/gcp-key.json` occurs before DNS operations in hooks
- Use `--manual-auth-hook` and `--manual-cleanup-hook` with certbot

## Best Practices

- Keep image small; avoid installing unnecessary packages
- Document hook behavior clearly in repo
- Use pinned base images for reproducibility when possible
- Validate certbot dry-runs before production issuance
````
