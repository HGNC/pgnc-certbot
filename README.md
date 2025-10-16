# PGNC Certbot

Automated DNS-01 certificate issuance for PGNC domains using Certbot and Google Cloud DNS.

## What This Image Provides

- Headless `certbot` execution with `gcloud` already installed
- DNS-01 challenge automation through bundled `auth-hook.sh` and `cleanup-hook.sh`
- Persistent certificate storage in the shared `certbot-etc` Docker volume consumed by `nginx`

Repository layout:
- `Dockerfile` – builds on `certbot/certbot` and installs the Google Cloud SDK
- `entrypoint.sh` – authenticates with Google Cloud using the mounted key file before delegating to Certbot
- `auth-hook.sh` / `cleanup-hook.sh` – manage TXT records in Google Cloud DNS during the validation flow

## Prerequisites

- Docker 24+ (or any modern Docker Engine that supports Compose v2)
- A Google Cloud service account JSON key with DNS record management access
- A public DNS zone in Google Cloud that hosts the target domains

## Quick Start (Docker Compose)

1. Place your service account key at `certbot/gcp-key.json` and keep it out of version control.
2. Update the `PROJECT` and `ZONE` variables near the top of `certbot/auth-hook.sh` and `certbot/cleanup-hook.sh` so they match your Google Cloud DNS setup.
3. Add your registration email to the root `.env` file (used by `docker-compose.yml`):

     ```bash
     MY_EMAIL=you@example.org
     ```

4. Ensure the domains listed in `docker-compose.yml` under the `certbot` service reflect the hostnames you own.
5. Request certificates:

     ```bash
     docker compose --profile ssl run --rm certbot
     ```

     The command executes the pre-configured `certonly` invocation with the DNS hooks. Certificates land in the `certbot-etc` named volume (`./certbot` does not contain the live certificates).

6. Start the full stack (including `nginx`) once the certificates are issued:

     ```bash
     docker compose --profile ssl up -d nginx
     ```

## Configuration

### Service Account Permissions

The service account must be able to read and write TXT records in the target zone. In most cases the `roles/dns.admin` IAM role is sufficient. The key file is mounted read-only at `/gcp-key.json` inside the container.

### Domains and Validation Zone

The DNS hooks assume a single Cloud DNS zone. Edit the `PROJECT` and `ZONE` constants in the hook scripts if you need a different zone per domain or use custom logic. Adjust the `sleep 60` in `auth-hook.sh` if propagation in your environment requires more or less time.

Target domains are configured through the `certbot` service command in `docker-compose.yml`. Add more `-d` arguments as needed; each must resolve to your infrastructure and have the corresponding `_acme-challenge` record managed by Google Cloud DNS.

### Contact Email

`MY_EMAIL` is passed to Certbot for expiry notifications and Terms of Service agreement. Define it in `.env` or override it by setting `MY_EMAIL` when invoking Compose, for example:

```bash
MY_EMAIL=ssl-alerts@example.org docker compose --profile ssl run --rm certbot
```

## Renewal Workflow

- To simulate the flow without issuing real certificates:

    ```bash
    docker compose --profile ssl run --rm certbot renew --dry-run
    ```

- To renew certificates (typically from a cron job on the host):

    ```bash
    docker compose --profile ssl run --rm certbot renew
    ```

The hooks handle TXT record creation and cleanup for each domain during renewal exactly as they do for the initial request.

## Operational Notes

- Live certificates, keys, and renewal configuration reside in the `certbot-etc` Docker volume. `nginx` mounts this volume read-only to serve TLS traffic.
- Inspect logs when debugging DNS propagation or API permission problems:

    ```bash
    docker compose logs -f certbot
    ```

- Warning output similar to the snippet below is safe to ignore; it simply echoes Google Cloud DNS transaction details:

    ```text
    Hook '--manual-cleanup-hook' ran with error output:
     Transaction started [transaction.yaml].
     Record removal appended to transaction at [transaction.yaml].
     Executed transaction [transaction.yaml] for managed-zone [...]
    ```

## Troubleshooting

- **Extended DNS propagation** – Increase the sleep duration in `auth-hook.sh` if TXT records are not visible quickly enough. Use `dig` against Google Cloud DNS name servers to verify propagation.
- **Permission denied errors** – Confirm the service account has `roles/dns.admin` on the Google Cloud project and that the `gcp-key.json` file is readable by Docker.
- **Challenge still pending** – Ensure nothing else manages `_acme-challenge` records for the same hostnames and that no stale TXT records remain.

## Contributing

Issues and pull requests are welcome via the main PGNC stack repository. Please avoid committing credential files or other secrets.

## License

This component inherits the root repository licensing (AGPL-3.0). Review `LICENSE` at the repository root for details.
