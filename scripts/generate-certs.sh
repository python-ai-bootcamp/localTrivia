#!/bin/bash
# Get script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SSL_DIR="$DIR/../nginx/ssl"
mkdir -p "$SSL_DIR"

echo "Generating self-signed certificate..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SSL_DIR/privkey.pem" \
  -out "$SSL_DIR/fullchain.pem" \
  -subj "/CN=localhost/O=Local Trivia/C=US" \
  -addext "subjectAltName=DNS:localhost,DNS:trivia.local,IP:127.0.0.1"

if [ $? -eq 0 ]; then
    echo "Certificates generated successfully in $SSL_DIR"
else
    echo "Certificate generation failed."
    exit 1
fi
