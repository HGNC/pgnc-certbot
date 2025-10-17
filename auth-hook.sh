#!/bin/sh

# Exit on any error
set -e

# Environment Variable Validation
# Required variables
if [ -z "$GCP_PROJECT" ]; then
    echo "Error: GCP_PROJECT environment variable is required" >&2
    exit 1
fi

if [ -z "$GCP_DNS_ZONE" ]; then
    echo "Error: GCP_DNS_ZONE environment variable is required" >&2
    exit 1
fi

# Optional variables with defaults
GCP_DNS_TTL="${GCP_DNS_TTL:-300}"
GCP_DNS_PROPAGATION_WAIT="${GCP_DNS_PROPAGATION_WAIT:-60}"

# Variables from Certbot
DOMAIN="_acme-challenge.$CERTBOT_DOMAIN."
TOKEN="$CERTBOT_VALIDATION"

# Validate Certbot variables
if [ -z "$CERTBOT_DOMAIN" ]; then
    echo "Error: CERTBOT_DOMAIN is not set" >&2
    exit 1
fi

if [ -z "$CERTBOT_VALIDATION" ]; then
    echo "Error: CERTBOT_VALIDATION is not set" >&2
    exit 1
fi

echo "Creating DNS TXT record for domain: $DOMAIN"
echo "Using project: $GCP_PROJECT, zone: $GCP_DNS_ZONE, TTL: $GCP_DNS_TTL"

# Function to cleanup transaction on exit
cleanup_transaction() {
    if [ -f "transaction.yaml" ]; then
        echo "Cleaning up transaction file..." >&2
        gcloud dns record-sets transaction abort --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" 2>/dev/null || true
    fi
}

# Set trap to cleanup on script exit
trap cleanup_transaction EXIT

# Validate gcloud authentication
echo "Validating gcloud authentication..."
AUTH_OUTPUT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>&1)
if [ $? -ne 0 ] || [ -z "$AUTH_OUTPUT" ]; then
    echo "Error: No active gcloud authentication found" >&2
    echo "Please run 'gcloud auth login' or set GOOGLE_APPLICATION_CREDENTIALS" >&2
    exit 1
fi

# Verify zone exists and permissions
echo "Verifying DNS zone access..."
if ! gcloud dns managed-zones describe "$GCP_DNS_ZONE" --project="$GCP_PROJECT" >/dev/null 2>&1; then
    echo "Error: Cannot access DNS zone '$GCP_DNS_ZONE' in project '$GCP_PROJECT'" >&2
    echo "Check that the zone exists and you have DNS admin permissions" >&2
    exit 1
fi

# Check for existing transaction and abort if needed
if [ -f "transaction.yaml" ]; then
    echo "Warning: Found existing transaction file, aborting previous transaction..." >&2
    gcloud dns record-sets transaction abort --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" 2>/dev/null || true
fi

# Create TXT record using gcloud DNS transaction commands with enhanced error handling
echo "Starting DNS transaction..."
START_OUTPUT=$(gcloud dns record-sets transaction start --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" 2>&1)
START_EXIT_CODE=$?
if [ $START_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to start DNS transaction" >&2
    echo "Details: $START_OUTPUT" >&2
    if echo "$START_OUTPUT" | grep -q "already in progress"; then
        echo "Hint: Another transaction may be in progress. Wait and try again." >&2
    elif echo "$START_OUTPUT" | grep -q "permission\|forbidden\|unauthorized"; then
        echo "Hint: Check DNS admin permissions for project '$GCP_PROJECT'" >&2
    fi
    exit 1
fi

# Check if record already exists and remove it first if needed
echo "Checking for existing record..."
if gcloud dns record-sets list --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" --name="$DOMAIN" --type=TXT >/dev/null 2>&1; then
    echo "Warning: TXT record already exists for $DOMAIN, removing existing record first..." >&2
    EXISTING_RECORD=$(gcloud dns record-sets list --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" --name="$DOMAIN" --type=TXT --format="value(rrdatas)")
    if [ -n "$EXISTING_RECORD" ]; then
        gcloud dns record-sets transaction remove "$EXISTING_RECORD" \
          --name="$DOMAIN" \
          --ttl="$GCP_DNS_TTL" \
          --type=TXT \
          --zone="$GCP_DNS_ZONE" \
          --project="$GCP_PROJECT" || true
    fi
fi

echo "Adding TXT record to transaction..."
ADD_OUTPUT=$(gcloud dns record-sets transaction add "$TOKEN" \
  --name="$DOMAIN" \
  --ttl="$GCP_DNS_TTL" \
  --type=TXT \
  --zone="$GCP_DNS_ZONE" \
  --project="$GCP_PROJECT" 2>&1)
ADD_EXIT_CODE=$?
if [ $ADD_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to add TXT record to transaction" >&2
    echo "Details: $ADD_OUTPUT" >&2
    if echo "$ADD_OUTPUT" | grep -q "already exists"; then
        echo "Hint: Record might already exist with different TTL or value" >&2
    fi
    exit 1
fi

echo "Executing DNS transaction..."
EXECUTE_OUTPUT=$(gcloud dns record-sets transaction execute --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" 2>&1)
EXECUTE_EXIT_CODE=$?
if [ $EXECUTE_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to execute DNS transaction" >&2
    echo "Details: $EXECUTE_OUTPUT" >&2
    if echo "$EXECUTE_OUTPUT" | grep -q "network\|timeout\|connection"; then
        echo "Hint: Network connectivity issue, check internet connection" >&2
    elif echo "$EXECUTE_OUTPUT" | grep -q "quota\|rate"; then
        echo "Hint: API quota exceeded, wait and try again" >&2
    fi
    exit 1
fi

# Clear trap since transaction completed successfully
trap - EXIT

echo "DNS record created successfully"
echo "Record details: $DOMAIN TXT \"$TOKEN\" (TTL: $GCP_DNS_TTL)"

# Enhanced propagation wait with validation
echo "Waiting $GCP_DNS_PROPAGATION_WAIT seconds for DNS propagation..."
if [ "$GCP_DNS_PROPAGATION_WAIT" -gt 0 ]; then
    # Show countdown for long waits
    if [ "$GCP_DNS_PROPAGATION_WAIT" -gt 30 ]; then
        echo "Long propagation wait detected, showing countdown..."
        REMAINING="$GCP_DNS_PROPAGATION_WAIT"
        while [ "$REMAINING" -gt 0 ]; do
            echo "Waiting... $REMAINING seconds remaining"
            sleep 10
            REMAINING=$((REMAINING - 10))
            if [ "$REMAINING" -lt 10 ] && [ "$REMAINING" -gt 0 ]; then
                sleep "$REMAINING"
                break
            fi
        done
    else
        sleep "$GCP_DNS_PROPAGATION_WAIT"
    fi
    echo "DNS propagation wait completed"
else
    echo "Skipping DNS propagation wait (GCP_DNS_PROPAGATION_WAIT=0)"
fi

# Optional: Verify record was created
echo "Verifying DNS record creation..."
if gcloud dns record-sets list --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" --name="$DOMAIN" --type=TXT --format="value(rrdatas)" | grep -q "$TOKEN"; then
    echo "✓ DNS record verification successful"
else
    echo "Warning: DNS record verification failed, but transaction completed" >&2
    echo "This may be normal due to propagation delays" >&2
fi
