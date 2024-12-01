#!/bin/bash

# Variables
DOMAIN="byars.xyz"
CERT_DIR="docker/nginx/certs"
NGINX_CONF="docker/nginx/nginx.conf"
EMAIL="admin@byars.xyz"

# Backup existing certificates if they exist
# Why? In case something goes wrong, we can restore the previous working state
if [ -f "${CERT_DIR}/nginx.crt" ]; then
    echo "Backing up existing certificates..."
    mv "${CERT_DIR}/nginx.crt" "${CERT_DIR}/nginx.crt.backup"
    mv "${CERT_DIR}/nginx.key" "${CERT_DIR}/nginx.key.backup"
fi

# Backup nginx configuration
# Why? We need to temporarily modify nginx config for domain verification
echo "Backing up nginx configuration..."
cp "${NGINX_CONF}" "${NGINX_CONF}.backup"

# Create temporary nginx configuration
# Why? Let's Encrypt needs direct access to port 80 for domain ownership verification
echo "Creating temporary nginx configuration..."
cat > "${NGINX_CONF}" << EOF
map \$host \$domain_name {
    default "${DOMAIN}";
}

server {
    listen 80;
    listen [::]:80;
    server_name \$domain_name www.\$domain_name;

    location = / {
        add_header Content-Type text/html;
        return 200 'baz';
    }
}
EOF

# Stop nginx container to free up port 80
# Why? Certbot needs port 80 available for the domain verification challenge
echo "Stopping nginx container..."
docker compose stop nginx

# Install certbot if not already installed
# Why? Certbot is the tool that communicates with Let's Encrypt to get our certificate
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-nginx
fi

# Get the certificate using standalone mode
# Why? Standalone mode runs its own web server for domain verification
echo "Obtaining Let's Encrypt certificate..."
sudo certbot certonly --standalone \
    -d ${DOMAIN} \
    -d www.${DOMAIN} \
    --email ${EMAIL} \
    --agree-tos \
    --non-interactive

# Create certificates directory if it doesn't exist
# Why? Ensure we have a place to store the certificates that nginx can access
mkdir -p ${CERT_DIR}

# Copy certificates to nginx directory
# Why? Nginx needs access to the certificates, but Let's Encrypt stores them elsewhere
echo "Copying certificates to nginx directory..."
sudo cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ${CERT_DIR}/nginx.crt
sudo cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem ${CERT_DIR}/nginx.key

# Set proper permissions
# Why? Certificates need to be readable by nginx but secure from other users
sudo chmod 644 ${CERT_DIR}/nginx.crt
sudo chmod 644 ${CERT_DIR}/nginx.key

# Restore original nginx configuration
# Why? Return to the full configuration now that we have our certificates
echo "Restoring nginx configuration..."
mv "${NGINX_CONF}.backup" "${NGINX_CONF}"

# Setup auto-renewal script
# Why? Let's Encrypt certificates expire after 90 days
echo "Setting up auto-renewal..."
sudo cp "$(dirname "$0")/renew-ssl.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/renew-ssl.sh

# Add cron job for renewal
# Why? Automatically attempt renewal monthly (certificates can be renewed 30 days before expiry)
(crontab -l 2>/dev/null; echo "0 0 1 * * /usr/local/bin/renew-ssl.sh") | crontab -

# Start nginx container with new certificates
# Why? Resume serving traffic with our new SSL configuration
echo "Starting nginx container..."
docker compose start nginx

echo "SSL setup complete! Nginx has been restarted with the new certificates."

