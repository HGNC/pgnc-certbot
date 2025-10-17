#!/bin/sh

# Exit on any error
set -e

echo "Certbot GCP Authentication Entrypoint"
echo "====================================="

# Environment Variable Validation
echo "Validating environment..."

if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo "Error: GOOGLE_APPLICATION_CREDENTIALS environment variable is not set" >&2
    echo "Please set GOOGLE_APPLICATION_CREDENTIALS to the path of your service account key file" >&2
    echo "Example: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json" >&2
    exit 1
fi

echo "GOOGLE_APPLICATION_CREDENTIALS: $GOOGLE_APPLICATION_CREDENTIALS"

# Service Account Key File Validation
echo "Validating service account key file..."

if [ ! -e "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo "Error: Service account key file not found: $GOOGLE_APPLICATION_CREDENTIALS" >&2
    echo "Please ensure the file exists and the path is correct" >&2
    echo "Check your volume mount and file path configuration" >&2
    exit 1
fi

if [ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo "Error: $GOOGLE_APPLICATION_CREDENTIALS is not a regular file" >&2
    echo "Please ensure you're pointing to a file, not a directory" >&2
    exit 1
fi

if [ ! -r "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo "Error: Service account key file is not readable: $GOOGLE_APPLICATION_CREDENTIALS" >&2
    echo "Please check file permissions" >&2
    echo "Current permissions: $(ls -la "$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null || echo 'unable to read permissions')" >&2
    exit 1
fi

# Basic JSON structure validation
echo "Validating service account key format..."
if ! head -1 "$GOOGLE_APPLICATION_CREDENTIALS" | grep -q '^{'; then
    echo "Error: Service account key file does not appear to be valid JSON" >&2
    echo "The file should start with '{' and contain valid service account credentials" >&2
    exit 1
fi

# Check for required JSON fields
if ! grep -q '"type".*"service_account"' "$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null; then
    echo "Error: Service account key file does not contain required 'type': 'service_account' field" >&2
    echo "Please ensure you're using a valid service account key file from Google Cloud Console" >&2
    exit 1
fi

echo "✓ Service account key file validation passed"
echo "File size: $(wc -c < "$GOOGLE_APPLICATION_CREDENTIALS") bytes"
echo ""

# Google Cloud Service Account Authentication
echo "Authenticating with Google Cloud..."
echo "Using service account key: $GOOGLE_APPLICATION_CREDENTIALS"

# Attempt authentication with detailed error handling
AUTH_OUTPUT=$(gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" 2>&1)
AUTH_EXIT_CODE=$?

if [ $AUTH_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to authenticate with Google Cloud" >&2
    echo "Authentication output:" >&2
    echo "$AUTH_OUTPUT" >&2
    echo "" >&2
    
    # Provide helpful hints based on error type
    if echo "$AUTH_OUTPUT" | grep -q "invalid.*key\|malformed\|parse"; then
        echo "Hint: The service account key file appears to be invalid or malformed" >&2
        echo "Please download a new key file from Google Cloud Console" >&2
    elif echo "$AUTH_OUTPUT" | grep -q "disabled\|inactive"; then
        echo "Hint: The service account may be disabled" >&2
        echo "Please check the service account status in Google Cloud Console" >&2
    elif echo "$AUTH_OUTPUT" | grep -q "permission\|access"; then
        echo "Hint: The service account may lack required permissions" >&2
        echo "Please ensure the service account has DNS admin permissions" >&2
    fi
    
    exit 1
fi

echo "✓ Successfully authenticated with Google Cloud"

# Verify authentication by checking active account
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
if [ -n "$ACTIVE_ACCOUNT" ]; then
    echo "Active service account: $ACTIVE_ACCOUNT"
else
    echo "Warning: Unable to verify active account, but authentication appeared successful" >&2
fi

echo ""

# Command Execution
echo "Executing Certbot command..."

# Log the command being executed (without sensitive information)
if [ $# -eq 0 ]; then
    echo "Command: certbot (no arguments provided)"
    echo "Warning: No arguments provided to certbot" >&2
    echo "Usage examples:" >&2
    echo "  - Request certificate: certbot certonly --dns-google --dns-google-credentials /path/to/creds --agree-tos -d example.com" >&2
    echo "  - Renew certificates: certbot renew" >&2
else
    echo "Command: certbot $*"
fi

echo "Starting certbot execution..."
echo "============================"

# Execute certbot with all provided arguments
# Using exec to replace the shell process and ensure proper signal handling
exec certbot "$@"
