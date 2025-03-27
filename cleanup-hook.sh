#!/bin/sh

DOMAIN="_acme-challenge.$CERTBOT_DOMAIN."
TOKEN="$CERTBOT_VALIDATION"

PROJECT="prj-ext-prod-hgnc-cloud-ls"
ZONE="genenames-org"

gcloud dns record-sets transaction start --zone=$ZONE --project=$PROJECT
gcloud dns record-sets transaction remove "$TOKEN" \
  --name="$DOMAIN" \
  --ttl=300 \
  --type=TXT \
  --zone=$ZONE \
  --project=$PROJECT
gcloud dns record-sets transaction execute --zone=$ZONE --project=$PROJECT
