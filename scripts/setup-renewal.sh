#!/bin/bash

# Copy renewal script to system location
sudo cp "$(dirname "$0")/renew-ssl.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/renew-ssl.sh

# Add cron job for monthly renewal
# Why? Run at midnight on the first of each month
(crontab -l 2>/dev/null; echo "0 0 1 * * /usr/local/bin/renew-ssl.sh") | crontab -

echo "SSL renewal setup complete! Cron job will run monthly." 