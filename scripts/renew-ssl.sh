#!/bin/bash

# Stop nginx so the certbot doesn't have competition for port 80
docker compose stop nginx

# Try to renew
certbot renew --quiet

# Copy new certs to nginx directory (only if renewal was successful)
if [ $? -eq 0 ]; then
    cp /etc/letsencrypt/live/example.com/fullchain.pem docker/nginx/certs/nginx.crt
    cp /etc/letsencrypt/live/example.com/privkey.pem docker/nginx/certs/nginx.key
    chmod 644 docker/nginx/certs/nginx.crt docker/nginx/certs/nginx.key
fi

# Start nginx (whether renewal worked or not)
docker compose start nginx 
