#!/usr/bin/env bash
# ==============================================================================
# Generate Self-Signed SSL Certificate for Local & Staging HTTPS Testing
# ==============================================================================
set -euo pipefail

SSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SSL_DIR"

echo "Generating self-signed SSL certificate in $SSL_DIR..."

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SSL_DIR/privkey.pem" \
  -out "$SSL_DIR/fullchain.pem" \
  -subj "/C=US/ST=State/L=City/O=CloudDeploy/OU=DevOps/CN=localhost"

echo "Generated: fullchain.pem and privkey.pem"

