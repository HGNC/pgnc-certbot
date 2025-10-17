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

echo "Removing DNS TXT record for domain: $DOMAIN"
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

# Start DNS transaction with enhanced error handling
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

echo "DNS transaction started successfully for cleanup"

# Check if record exists before attempting removal
echo "Checking if DNS record exists..."
RECORD_EXISTS=false
if gcloud dns record-sets list --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" --name="$DOMAIN" --type=TXT >/dev/null 2>&1; then
    # Get existing record details
    EXISTING_RECORD=$(gcloud dns record-sets list --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" --name="$DOMAIN" --type=TXT --format="value(rrdatas)")
    if [ -n "$EXISTING_RECORD" ]; then
        RECORD_EXISTS=true
        echo "Found existing DNS record: $DOMAIN TXT $EXISTING_RECORD"
        
        # Check if our token matches the existing record
        if echo "$EXISTING_RECORD" | grep -q "$TOKEN"; then
            echo "Record contains our validation token, proceeding with removal"
        else
            echo "Warning: Existing record does not contain our validation token" >&2
            echo "Expected: $TOKEN, Found: $EXISTING_RECORD" >&2
            echo "Will attempt removal anyway" >&2
        fi
    fi
fi

if [ "$RECORD_EXISTS" = "false" ]; then
    echo "No existing DNS record found for $DOMAIN"
    echo "This is normal if the record was already cleaned up or never created"
    echo "Skipping removal and completing cleanup successfully"
    
    # Clear trap and abort transaction since no work is needed
    trap - EXIT
    gcloud dns record-sets transaction abort --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" 2>/dev/null || true
    echo "Cleanup completed successfully (no record to remove)"
    exit 0
fi

# Attempt to remove the DNS record with graceful error handling
echo "Removing TXT record from transaction..."
REMOVE_OUTPUT=$(gcloud dns record-sets transaction remove "$TOKEN" \
  --name="$DOMAIN" \
  --ttl="$GCP_DNS_TTL" \
  --type=TXT \
  --zone="$GCP_DNS_ZONE" \
  --project="$GCP_PROJECT" 2>&1)
REMOVE_EXIT_CODE=$?

if [ $REMOVE_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to add record removal to transaction" >&2
    echo "Details: $REMOVE_OUTPUT" >&2
    
    # Check for specific error conditions
    if echo "$REMOVE_OUTPUT" | grep -q "does not exist\|not found"; then
        echo "Warning: Record not found during removal - this is normal if already cleaned up" >&2
        # Clear trap and abort transaction gracefully
        trap - EXIT
        gcloud dns record-sets transaction abort --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" 2>/dev/null || true
        echo "Cleanup completed (record already removed)"
        exit 0
    elif echo "$REMOVE_OUTPUT" | grep -q "ttl.*mismatch\|value.*mismatch"; then
        echo "Hint: TTL or value mismatch - trying with existing record values" >&2
        
        # Try to remove with the actual existing record values
        if [ -n "$EXISTING_RECORD" ]; then
            echo "Attempting removal with existing record data..."
            RETRY_OUTPUT=$(gcloud dns record-sets transaction remove "$EXISTING_RECORD" \
              --name="$DOMAIN" \
              --ttl="$GCP_DNS_TTL" \
              --type=TXT \
              --zone="$GCP_DNS_ZONE" \
              --project="$GCP_PROJECT" 2>&1)
            RETRY_EXIT_CODE=$?
            
            if [ $RETRY_EXIT_CODE -ne 0 ]; then
                echo "Error: Retry with existing record data also failed" >&2
                echo "Retry details: $RETRY_OUTPUT" >&2
                exit 1
            else
                echo "Successfully added removal to transaction using existing record data"
            fi
        else
            exit 1
        fi
    else
        echo "Hint: Unexpected error during record removal" >&2
        exit 1
    fi
else
    echo "Record removal added to transaction successfully"
fi

# Execute the transaction with comprehensive error handling
echo "Executing DNS cleanup transaction..."
EXECUTE_OUTPUT=$(gcloud dns record-sets transaction execute --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" 2>&1)
EXECUTE_EXIT_CODE=$?

if [ $EXECUTE_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to execute DNS cleanup transaction" >&2
    echo "Details: $EXECUTE_OUTPUT" >&2
    
    # Provide helpful hints based on error type
    if echo "$EXECUTE_OUTPUT" | grep -q "network\|timeout\|connection"; then
        echo "Hint: Network connectivity issue, check internet connection" >&2
    elif echo "$EXECUTE_OUTPUT" | grep -q "quota\|rate"; then
        echo "Hint: API quota exceeded, wait and try again" >&2
    elif echo "$EXECUTE_OUTPUT" | grep -q "concurrent\|conflict"; then
        echo "Hint: Concurrent DNS operation detected, retry may succeed" >&2
    fi
    exit 1
fi

# Clear trap since transaction completed successfully
trap - EXIT

echo "DNS cleanup transaction executed successfully"
echo "TXT record removed: $DOMAIN (token: $TOKEN)"

# Optional: Verify record was removed
echo "Verifying record removal..."
if ! gcloud dns record-sets list --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" --name="$DOMAIN" --type=TXT >/dev/null 2>&1; then
    echo "✓ DNS record removal verification successful"
else
    # Check if the specific token is still there
    REMAINING_RECORDS=$(gcloud dns record-sets list --zone="$GCP_DNS_ZONE" --project="$GCP_PROJECT" --name="$DOMAIN" --type=TXT --format="value(rrdatas)" 2>/dev/null || echo "")
    if [ -n "$REMAINING_RECORDS" ] && echo "$REMAINING_RECORDS" | grep -q "$TOKEN"; then
        echo "Warning: DNS record still exists after cleanup" >&2
        echo "This may be normal due to propagation delays" >&2
    else
        echo "✓ DNS record cleanup successful (our token removed)"
    fi
fi

echo "DNS cleanup completed successfully"
