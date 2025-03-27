# pgnc-certbot

Automated Certificate Management with Certbot and Google Cloud DNS.

## Description

This container automates the process of obtaining SSL/TLS certificates using Certbot for specified domains. It integrates with Google Cloud DNS to manage DNS challenges required for certificate issuance.

## Requirements

- Docker: To build and run the container.
- gcp-key.json: You need a JSON key file of a Google Cloud Platform service account which has access to the Cloud DNS.

## Setup

### 1. Install Docker

Ensure Docker is installed on your system. For installation instructions, refer to Docker's documentation.

### 2. Build the Container Image

Clone this repository and build the container using:

```BASH
docker build -t pgnc-certbot .
```

### 3. Run the Container

Start the container with:

```BASH
docker run -d --name pgnc-certbot \
    certbot certonly \
        --manual \
        --preferred-challenges=dns \
        -manual-auth-hook=/auth-hook.sh \
        --manual-cleanup-hook=/cleanup-hook.sh \
        --email=MY_EMAIL \
        --agree-tos \
        --non-interactive \
        -d plant.genenames.org \
        -d pgnc.genenames.org
```

The --env-file flag uses gcp-key.json to configure Google Cloud DNS integration.
Replace the domains in the command with your own.

## Configuration

### 1. Google Cloud Key File

Create a gcp-key.json file at the root of your project. This file should contain your Google Cloud service account key for managing DNS zones and TXT records.

### 2. Domains Configuration

Specify the domains you want to manage in the container run command. Ensure each domain has DNS records configured in Google Cloud DNS with the A type pointing to your IP of your server. Replace plant.genenames.org and/or pgnc.genenames.org to your own domain names.

### 3. Email address

Replace the MY_EMAIL in the docker run command with your own email address which is used for the Certbot registration.

## Usage

### 1. Obtain Certificates

When the container starts, Certbot will automatically initiate the certificate process using the provided hooks and Google Cloud DNS configuration. Certificates will be stored in /etc/letsencrypt/.

### 2. Certificate Management

- Auth Hook (auth-hook.sh): Creates TXT records in Google Cloud DNS upon certificate issuance.
- Cleanup Hook (cleanup-hook.sh): Removes unused TXT records after certificate renewal.

## Troubleshooting

### Common Issues

1. DNS Propagation Delay: Allow up to 24 hours for TXT record propagation.
2. API Errors: Ensure the Google Cloud service account has the necessary permissions for DNS zones and TXT records.
3. Permissions Issues: Verify that the service account has the roles/iam.serviceAccountManager role if you're managing multiple domains.

### Logs

Check container logs for any errors:

```BASH
docker logs -f pgnc-certbot
```

## Note on Hook errors

If you see the error below, please ignore.

```TEXT
Hook '--manual-cleanup-hook' for plant.genenames.org ran with error output:
 Transaction started [transaction.yaml].
 Record removal appended to transaction at [transaction.yaml].
 Executed transaction [transaction.yaml] for managed-zone [genenames-org].
 Created [https://dns.googleapis.com/dns/v1/projects/......
```

## Domain Configuration in Google Cloud DNS

- [Google Cloud DNS Documentation](https://cloud.google.com/dns/docs)
- Ensure each domain has a TXT record pointing to a Google-managed domain.
- Configure the zone with DNSSEC if required.

## Contributing

Contributions and questions are welcome at [GitHub Issues](https://github.com/HGNC/pgnc-certbot/issues).

## License

This project is licensed under Creative Commons Zero v1.0 Universal. For more details, see the [LICENSE](https://github.com/HGNC/pgnc-certbot/blob/main/LICENSE) file.
