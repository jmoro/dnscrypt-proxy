# Multi-architecture Dockerfile for dnscrypt-proxy
# Supports: linux/amd64, linux/386, linux/arm64, linux/arm/v7
#
# Build with Docker buildx for multi-arch support:
#   docker buildx build --platform linux/amd64,linux/386,linux/arm64,linux/arm/v7 -t dnscrypt-proxy .
#
# Or build for a single architecture:
#   docker build -t dnscrypt-proxy .
#
# Build with a specific version:
#   docker build --build-arg DNSCRYPT_PROXY_VERSION=2.1.14 -t dnscrypt-proxy .

# Build stage
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder

# Install build dependencies
RUN apk add --no-cache ca-certificates tzdata curl jq

# Version of dnscrypt-proxy to build (empty = fetch latest from GitHub)
ARG DNSCRYPT_PROXY_VERSION

# Set up build arguments for cross-compilation
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

WORKDIR /src

# Download and extract source from GitHub
# If DNSCRYPT_PROXY_VERSION is empty, fetch latest version from GitHub API
RUN set -ex; \
    if [ -z "$DNSCRYPT_PROXY_VERSION" ]; then \
        DNSCRYPT_PROXY_VERSION=$(curl -s https://api.github.com/repos/DNSCrypt/dnscrypt-proxy/releases/latest | jq -r .tag_name); \
        echo "Resolved latest version: $DNSCRYPT_PROXY_VERSION"; \
    fi; \
    curl -fsSL "https://github.com/DNSCrypt/dnscrypt-proxy/archive/${DNSCRYPT_PROXY_VERSION}.tar.gz" -o /tmp/dnscrypt-proxy.tar.gz; \
    tar -xzf /tmp/dnscrypt-proxy.tar.gz -C /src --strip-components=1; \
    rm /tmp/dnscrypt-proxy.tar.gz; \
    echo "$DNSCRYPT_PROXY_VERSION" > /src/.version

# Build the binary for the target platform
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    CGO_ENABLED=0 \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    GOARM=${TARGETVARIANT#v} \
    go build -mod vendor -ldflags="-s -w" -trimpath -o /dnscrypt-proxy ./dnscrypt-proxy

# Prepare files for final stage
RUN mkdir -p /etc/dnscrypt-proxy && \
    cp /src/dnscrypt-proxy/example-dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml

# Final stage - minimal runtime image
# Using distroless for security (no shell, minimal attack surface)
# Alternative: use 'FROM scratch' for absolute minimum size
FROM gcr.io/distroless/static-debian12:nonroot

# OCI labels
LABEL org.opencontainers.image.title="dnscrypt-proxy" \
      org.opencontainers.image.description="A flexible DNS proxy with support for encrypted DNS protocols" \
      org.opencontainers.image.url="https://github.com/DNSCrypt/dnscrypt-proxy" \
      org.opencontainers.image.source="https://github.com/DNSCrypt/dnscrypt-proxy" \
      org.opencontainers.image.licenses="ISC"

# Copy binary from builder
COPY --from=builder /dnscrypt-proxy /usr/local/bin/dnscrypt-proxy

# Copy configuration
COPY --from=builder /etc/dnscrypt-proxy /etc/dnscrypt-proxy

# Copy timezone data and CA certificates from builder
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Expose DNS ports (UDP and TCP)
EXPOSE 53/udp 53/tcp

# Set working directory
WORKDIR /etc/dnscrypt-proxy

# Default command
ENTRYPOINT ["/usr/local/bin/dnscrypt-proxy"]
CMD ["-config", "/etc/dnscrypt-proxy/dnscrypt-proxy.toml"]
