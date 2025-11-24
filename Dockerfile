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
RUN apk add --no-cache git ca-certificates tzdata

# Version of dnscrypt-proxy to build (default: latest as of 2025-01-24)
ARG DNSCRYPT_PROXY_VERSION=2.1.14

# Set up build arguments for cross-compilation
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

WORKDIR /src

# Download and extract source from GitHub
ADD https://github.com/DNSCrypt/dnscrypt-proxy/archive/${DNSCRYPT_PROXY_VERSION}.tar.gz /tmp/dnscrypt-proxy.tar.gz
RUN tar -xzf /tmp/dnscrypt-proxy.tar.gz -C /src --strip-components=1 && \
    rm /tmp/dnscrypt-proxy.tar.gz

# Build the binary for the target platform
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    CGO_ENABLED=0 \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    GOARM=${TARGETVARIANT#v} \
    go build -mod vendor -ldflags="-s -w" -o /dnscrypt-proxy ./dnscrypt-proxy

# Final stage - minimal runtime image
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata

# Create non-root user for security
RUN addgroup -S dnscrypt && adduser -S dnscrypt -G dnscrypt

# Copy binary from builder
COPY --from=builder /dnscrypt-proxy /usr/local/bin/dnscrypt-proxy

# Create configuration directory
RUN mkdir -p /etc/dnscrypt-proxy && chown dnscrypt:dnscrypt /etc/dnscrypt-proxy

# Copy example configuration (users should mount their own config)
COPY --from=builder /src/dnscrypt-proxy/example-dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml
RUN chown dnscrypt:dnscrypt /etc/dnscrypt-proxy/dnscrypt-proxy.toml

# Switch to non-root user
USER dnscrypt

# Expose DNS ports (UDP and TCP)
EXPOSE 53/udp 53/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD dnscrypt-proxy -resolve cloudflare.com || exit 1

# Set working directory
WORKDIR /etc/dnscrypt-proxy

# Default command
ENTRYPOINT ["dnscrypt-proxy"]
CMD ["-config", "/etc/dnscrypt-proxy/dnscrypt-proxy.toml"]
