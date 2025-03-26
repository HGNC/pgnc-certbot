#!/bin/sh

# Variables from Certbot
DOMAIN="_acme-challenge.$CERTBOT_DOMAIN."
TOKEN="$CERTBOT_VALIDATION"

# Google Cloud Project and Zone
PROJECT="your-gcp-project-id"
ZONE="your-dns-zone-name" # e.g., "plant-genes-zone"

# Create TXT record
gcloud dns record-sets transaction start --zone=$ZONE --project=$PROJECT
gcloud dns record-sets transaction add "$TOKEN" \
  --name="$DOMAIN" \
  --ttl=300 \
  --type=TXT \
  --zone=$ZONE \
  --project=$PROJECT
gcloud dns record-sets transaction execute --zone=$ZONE --project=$PROJECT

# Wait for DNS propagation (adjust sleep time as needed)
sleep 60
