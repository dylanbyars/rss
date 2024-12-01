#!/bin/bash

# Variables
DOMAIN="byars.xyz"
CERT_DIR="docker/nginx/certs"

# Renew the certificate
certbot renew --quiet

# Check if renewal was successful
if [ $? -eq 0 ]; then
  # Copy new certificates
  cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ${CERT_DIR}/nginx.crt
  cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem ${CERT_DIR}/nginx.key

  # Set proper permissions
  chmod 644 ${CERT_DIR}/nginx.crt
  chmod 644 ${CERT_DIR}/nginx.key

  # Restart nginx container
  docker compose restart nginx

  echo "Certificate renewed successfully!"
else
  echo "Certificate renewal failed!"
  exit 1
fi

