# Certbot Component Documentation

This directory contains the Certbot SSL certificate management component for the PGNC External Stack, providing automated Let's Encrypt certificate provisioning and renewal using Google Cloud DNS-01 challenges.

## Component Architecture

The Certbot component consists of three main scripts that work together to provide a complete SSL certificate automation solution:

```
certbot/
├── entrypoint.sh       # Container entrypoint with GCP authentication wrapper
├── auth-hook.sh        # DNS challenge authentication (creates TXT records)
├── cleanup-hook.sh     # DNS challenge cleanup (removes TXT records)
├── Dockerfile         # Complete Alpine-based container definition
├── gcp-key.json       # Service account key (local development only)
└── README.md         # This documentation
```

### Script Responsibilities

| Script | Purpose | Key Features |
|--------|---------|--------------|
| **entrypoint.sh** | Container entrypoint and GCP authentication | • Service account key validation<br>• Google Cloud SDK authentication<br>• Argument forwarding to Certbot<br>• Comprehensive error handling |
| **auth-hook.sh** | DNS-01 challenge authentication | • DNS TXT record creation<br>• Environment variable validation<br>• Configurable propagation wait<br>• Transaction-based DNS operations |
| **cleanup-hook.sh** | DNS-01 challenge cleanup | • DNS TXT record removal<br>• Graceful handling of missing records<br>• Automatic transaction cleanup<br>• Error recovery mechanisms |

### Container Image Features

- **Base**: Alpine Linux 3.18 (lightweight and secure)
- **Certbot**: Version 2.6+ with Google Cloud DNS plugin
- **Google Cloud SDK**: Version 458.0.1 (pinned for reproducibility)
- **Baked-in Scripts**: All hooks embedded in the image (no runtime bind-mounts required)
- **Health Checks**: Automatic validation of Certbot and gcloud functionality
- **Production Ready**: Comprehensive error handling, logging, and security features

## Environment Variables Reference

Configure these variables in your `.env` file:

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GOOGLE_APPLICATION_CREDENTIALS` | Container path to service account key | `/app/gcp-key.json` |
| `GCP_PROJECT` | Google Cloud project ID | `my-project-123456` |
| `GCP_DNS_ZONE` | Cloud DNS zone name | `my-domain-zone` |
| `GCP_KEY_FILE` | Host path to service account key | `./gcp-key.json` |

### Optional Variables (with defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `GCP_DNS_TTL` | `300` | DNS record TTL in seconds |
| `GCP_DNS_PROPAGATION_WAIT` | `60` | DNS propagation wait time in seconds |
| `CERTBOT_EMAIL` | - | Email for Let's Encrypt notifications |
| `DOMAIN_NAME` | - | Primary domain for certificate |

## Development Commands

### Building the Image

```bash
# Build the local Certbot image
docker compose build certbot

# Build with verbose output for debugging
docker compose build --progress=plain certbot

# Rebuild without cache
docker compose build --no-cache certbot
```

### Testing and Validation

```bash
# Test entrypoint validation (should fail with missing credentials)
docker run --rm pgnc-certbot-local --version

# Test with proper environment setup
docker compose --profile ssl run --rm certbot --version

# Dry run certificate request
docker compose --profile ssl run --rm certbot certonly --dry-run --dns-google --dns-google-credentials /app/gcp-key.json -d yourdomain.com

# List certificates
docker compose --profile ssl run --rm certbot certificates

# Test renewal (dry run)
docker compose --profile ssl run --rm certbot renew --dry-run

# Force renewal for testing
docker compose --profile ssl run --rm certbot renew --force-renewal
```

### Development Testing

```bash
# Interactive shell for debugging
docker compose --profile ssl run --rm certbot sh

# Test individual components
docker compose --profile ssl run --rm certbot gcloud version
docker compose --profile ssl run --rm certbot python3 -c "import certbot_dns_google; print('DNS plugin available')"

# Manual hook testing (within container)
export GCP_PROJECT="test-project"
export GCP_DNS_ZONE="test-zone"  
export CERTBOT_DOMAIN="example.com"
export CERTBOT_VALIDATION="test-token"
/app/auth-hook.sh  # Create TXT record
/app/cleanup-hook.sh  # Remove TXT record
```

## Security Considerations

### Service Account Permissions

The Google Cloud service account requires minimal permissions:

```yaml
# Required IAM roles
roles:
  - roles/dns.admin  # For DNS record management

# Alternative: Custom role with specific permissions
permissions:
  - dns.changes.create
  - dns.changes.get
  - dns.changes.list
  - dns.managedZones.get
  - dns.managedZones.list
  - dns.resourceRecordSets.create
  - dns.resourceRecordSets.delete
  - dns.resourceRecordSets.list
```

### Security Best Practices

1. **Service Account Key Management**:
   ```bash
   # Secure key file permissions
   chmod 600 gcp-key.json
   
   # Never commit keys to version control
   echo "gcp-key.json" >> .gitignore
   ```

2. **Container Security**:
   - Read-only mounts for service account keys
   - Minimal attack surface with Alpine Linux base

3. **Network Security**:
   - Only required outbound connections (Google Cloud APIs, Let's Encrypt)
   - No inbound network requirements

## Performance Optimization

### DNS Propagation Tuning

```bash
# Fast networks (reduce wait time)
GCP_DNS_PROPAGATION_WAIT=30

# Slow networks or distant DNS servers (increase wait time)
GCP_DNS_PROPAGATION_WAIT=120

# Very fast DNS providers (CloudFlare, etc.)
GCP_DNS_TTL=60
GCP_DNS_PROPAGATION_WAIT=30
```

## Troubleshooting Guide

### Common Issues and Solutions

| Issue | Diagnosis | Solution |
|-------|-----------|----------|
| **Authentication failures** | `Error: No active gcloud authentication found` | Verify `GCP_KEY_FILE` path and service account permissions |
| **DNS challenge timeout** | DNS records not propagating in time | Increase `GCP_DNS_PROPAGATION_WAIT` or check DNS provider |
| **Permission denied** | Service account lacks DNS permissions | Add `roles/dns.admin` role to service account |
| **Build failures** | Network issues or package problems | Check internet connectivity and try `--no-cache` build |
| **Container startup fails** | Missing environment variables | Verify all required variables are set in `.env` |

### Debug Commands

```bash
# Check container logs
docker compose logs certbot

# Validate environment variables
docker compose --profile ssl run --rm certbot env | grep -E '^(GCP_|GOOGLE_|CERTBOT_)'

# Test Google Cloud authentication
docker compose --profile ssl run --rm certbot gcloud auth list

# Test DNS zone access
docker compose --profile ssl run --rm certbot gcloud dns managed-zones list

# Manual DNS record testing
docker compose --profile ssl run --rm certbot gcloud dns record-sets list --zone=your-zone-name
```

## Integration with Main Stack

The Certbot component integrates seamlessly with the main PGNC External Stack:

1. **Volume Sharing**: Certificates stored in `certbot-letsencrypt` volume, shared with nginx
2. **Network Isolation**: Uses `ssl` profile for certificate operations
3. **Environment Integration**: Shares `.env` configuration with main stack
4. **Automated Renewal**: `cert-renewal.sh` script provides hands-off operation

### Docker Compose Integration

```yaml
# In docker-compose.yml
certbot:
  build: ./certbot
  image: pgnc-certbot-local
  profiles: ["ssl"]
  environment:
    - GOOGLE_APPLICATION_CREDENTIALS=/app/gcp-key.json
    - GCP_PROJECT=${GCP_PROJECT}
    - GCP_DNS_ZONE=${GCP_DNS_ZONE}
    # ... other variables
  volumes:
    - ${GCP_KEY_FILE}:/app/gcp-key.json:ro
    - certbot-letsencrypt:/etc/letsencrypt
```

For more information, see the main [README.md](../README.md) and [SSL_RENEWAL_SETUP.md](../SSL_RENEWAL_SETUP.md) documentation.
