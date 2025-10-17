# Certbot with Google Cloud DNS Support
# =====================================
# Alpine-based Certbot container with Google Cloud SDK and DNS-01 challenge hooks
# Built for PGNC External Stack SSL certificate automation

FROM alpine:3.18

# Metadata
LABEL maintainer="PGNC External Stack" \
      description="Certbot with Google Cloud DNS support and embedded hook scripts" \
      version="1.0.0"

# Install system dependencies and Certbot
# Note: Using specific versions for reproducible builds
RUN apk add --no-cache \
    # Core system utilities
    bash=~5.2 \
    curl=~8.2 \
    ca-certificates \
    tzdata \
    # Python and pip for Certbot
    python3=~3.11 \
    py3-pip=~23.1 \
    # Certbot and Google DNS plugin
    certbot=~2.6 \
    py3-certbot-dns-google=~2.6 \
    # Additional utilities for debugging
    bind-tools \
    && rm -rf /var/cache/apk/*

# Verify Certbot installation
RUN certbot --version && \
    python3 -c "import certbot_dns_google; print('Google DNS plugin installed successfully')" && \
    echo "Alpine base image and Certbot dependencies installed successfully"

# Install Google Cloud SDK
# Using the official Linux tarball for more control over installation
ENV CLOUD_SDK_VERSION=458.0.1
RUN cd /tmp && \
    # Download Google Cloud CLI
    curl -sSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${CLOUD_SDK_VERSION}-linux-x86_64.tar.gz -o google-cloud-cli.tar.gz && \
    # Verify download size (basic sanity check)
    [ $(stat -c%s google-cloud-cli.tar.gz) -gt 50000000 ] || { echo "Download appears incomplete"; exit 1; } && \
    # Extract the archive
    tar -xzf google-cloud-cli.tar.gz && \
    # Install Google Cloud SDK
    ./google-cloud-sdk/install.sh \
        --quiet \
        --usage-reporting=false \
        --command-completion=false \
        --path-update=false \
        --install-python=false && \
    # Move to final location
    mv google-cloud-sdk /opt/ && \
    # Clean up
    rm -rf /tmp/google-cloud-cli.tar.gz /tmp/google-cloud-sdk && \
    echo "Google Cloud SDK installed successfully"

# Set up Google Cloud SDK environment
ENV PATH="/opt/google-cloud-sdk/bin:${PATH}"
ENV CLOUDSDK_PYTHON=python3

# Verify Google Cloud SDK installation
RUN gcloud version && \
    gcloud components list --quiet && \
    echo "Google Cloud SDK verification completed"

# Set up application directory
WORKDIR /app

# Copy hook scripts and entrypoint
# These scripts are baked into the image for reproducible behavior
COPY auth-hook.sh cleanup-hook.sh entrypoint.sh ./

# Set executable permissions on all scripts
RUN chmod +x *.sh && \
    # Verify scripts are executable and have proper content
    [ -x auth-hook.sh ] && echo "✓ auth-hook.sh is executable" || exit 1 && \
    [ -x cleanup-hook.sh ] && echo "✓ cleanup-hook.sh is executable" || exit 1 && \
    [ -x entrypoint.sh ] && echo "✓ entrypoint.sh is executable" || exit 1 && \
    # Basic syntax check for shell scripts
    sh -n auth-hook.sh && echo "✓ auth-hook.sh syntax OK" && \
    sh -n cleanup-hook.sh && echo "✓ cleanup-hook.sh syntax OK" && \
    sh -n entrypoint.sh && echo "✓ entrypoint.sh syntax OK" && \
    echo "All hook scripts integrated successfully"

# Create directories for certificates and logs
RUN mkdir -p /etc/letsencrypt /var/log/letsencrypt /var/lib/letsencrypt && \
    # Ensure proper permissions for Certbot directories
    chmod 700 /etc/letsencrypt && \
    echo "Certbot directories created"

# Set up health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD gcloud version > /dev/null && certbot --version > /dev/null || exit 1

# Configure container metadata
EXPOSE 80 443
VOLUME ["/etc/letsencrypt", "/var/log/letsencrypt"]

# Set entrypoint to our authentication wrapper
ENTRYPOINT ["/app/entrypoint.sh"]

# Default command shows help
CMD ["--help"]
