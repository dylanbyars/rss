# Miniflux RSS Reader Setup

A self-hosted RSS reader setup using Miniflux behind an Nginx reverse proxy with HTTPS encryption.

## Components

- **Miniflux**: RSS aggregator and reader
- **Nginx**: Reverse proxy handling HTTPS
- **PostgreSQL**: Database for Miniflux

## Architecture

The setup uses Docker Compose with three main services:
1. Nginx reverse proxy (ports 80, 443)
2. Miniflux RSS reader (internal port 8080)
3. PostgreSQL database (internal)

All inter-service communication happens on an internal Docker network.

## SSL/HTTPS Setup

The system uses Let's Encrypt for SSL certificates. Here's how to set it up:

1. Configure DNS:
   - Add A records in your domain registrar pointing to your server IP
   - One for `example.com` → `YOUR_SERVER_IP`
   - One for `www.example.com` → `YOUR_SERVER_IP`

2. Configure firewalls:
   - In cloud provider's firewall (e.g., Linode, DigitalOcean):
     ```
     Allow TCP 80  from 0.0.0.0/0
     Allow TCP 443 from 0.0.0.0/0
     ```
   - Disable UFW if it's running: `sudo ufw disable` because it was interfering with Let's Encrypt domain verification
   - Why? Docker bypasses UFW anyway, so we manage access through cloud provider's firewall

3. Get SSL certificate:
   ```bash
   # Stop nginx to free port 80
   docker compose stop nginx
   
   # Get certificate
   sudo certbot certonly --standalone \
     -d example.com -d www.example.com \
     --email your-email@example.com --agree-tos
   
   # Copy certificates
   sudo cp /etc/letsencrypt/live/example.com/fullchain.pem docker/nginx/certs/nginx.crt
   sudo cp /etc/letsencrypt/live/example.com/privkey.pem docker/nginx/certs/nginx.key
   
   # Set permissions
   sudo chmod 644 docker/nginx/certs/nginx.crt docker/nginx/certs/nginx.key
   ```

4. Start nginx with SSL config:
   ```bash
   docker compose start nginx
   ```

### Important Notes

- **Port 80 Gotcha**: The most common issue is port 80 being in use. Check:
  1. Docker containers: `docker compose ps`
  2. System nginx: `sudo systemctl status nginx`
  3. Other services: `sudo lsof -i :80`
  
- Let's Encrypt certificates expire after 90 days
- Certbot sets up automatic renewal
- Certificates are stored in `/etc/letsencrypt/live/example.com/`
- Nginx expects them in `docker/nginx/certs/` as `nginx.crt` and `nginx.key`

## Deployment

1. Generate SSL certificates as shown above
2. Start the services:

```bash
docker compose up -d
```

3. Access Miniflux:
   - Visit https://your-ip-address
   - Accept the browser security warning (due to self-signed certificate)

## Security Notes

- Traffic is encrypted between browser and server
- Database is only accessible within the Docker internal network
- Self-signed certificate provides encryption but not domain validation
- Default credentials should be changed after first login

## File Structure

```
.
├── docker-compose.yml      # Service definitions
├── docker/
│   └── nginx/
│       ├── nginx.conf     # Nginx configuration
│       └── certs/         # SSL certificates
└── README.md
```

# TODO

- [ ] document what an A record is
