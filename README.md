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

The system uses a self-signed SSL certificate for HTTPS encryption. While this provides encryption, browsers will show a security warning because the certificate isn't from a trusted Certificate Authority.

### Generate SSL Certificate

I ran this script from inside the prod container. 

```bash
# Create directory for certificates
mkdir -p docker/nginx/certs

# Generate self-signed certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout docker/nginx/certs/nginx.key \
  -out docker/nginx/certs/nginx.crt \
  -subj "/CN=170.187.149.104
```

TODO: what do I need to do for local development? how can I configure the `nginx.conf` to work in both contexts?

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

## Future Improvements

