#!/bin/sh

# Authenticate with Google Cloud using the mounted key
gcloud auth activate-service-account --key-file=/gcp-key.json

# Run Certbot with the original command
exec certbot "$@"
