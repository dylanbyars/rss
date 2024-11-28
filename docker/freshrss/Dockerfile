FROM freshrss/freshrss:latest

# Install git
RUN apt update && apt install -y git

# Remove existing extensions directory if it exists
RUN rm -rf /var/www/FreshRSS/extensions

# Clone the Extensions repository
RUN git clone https://github.com/FreshRSS/Extensions.git /var/www/FreshRSS/extensions

# Ensure correct permissions
RUN chown -R www-data:www-data /var/www/FreshRSS/extensions

