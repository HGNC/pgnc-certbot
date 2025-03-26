FROM certbot/certbot

# Install dependencies
RUN apk add --no-cache \
    curl \
    python3 \
    py3-pip \
    bash \
    git

# Install Google Cloud SDK
RUN curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts
ENV PATH $PATH:/root/google-cloud-sdk/bin

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# Authenticate using the mounted service account key
ENTRYPOINT ["/entrypoint.sh"]
