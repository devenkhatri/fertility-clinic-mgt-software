# ==============================================================================
# Stage 1: Build Frontend Assets (Vite & Tailwind CSS)
# ==============================================================================
FROM node:20-alpine AS frontend
WORKDIR /app

COPY package*.json ./
RUN npm ci || npm install

COPY vite.config.js ./
COPY resources/ resources/
COPY public/ public/

RUN npm run build

# ==============================================================================
# Stage 2: Install PHP Composer Dependencies
# ==============================================================================
FROM composer:2 AS composer
WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts \
    --ignore-platform-reqs

COPY . .
RUN composer dump-autoload --optimize --no-scripts

# ==============================================================================
# Stage 3: Production PHP-FPM Application Runtime
# ==============================================================================
FROM php:8.2-fpm-alpine AS runner

# Install necessary runtime OS packages and tools
RUN apk add --no-cache \
    curl \
    git \
    unzip \
    libzip \
    libpng \
    libjpeg-turbo \
    freetype \
    icu \
    oniguruma \
    netcat-openbsd \
    shadow

# Use official extension installer for clean, minimal layers
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install PHP extensions required by Laravel 11, MySQL, and Redis
RUN install-php-extensions \
    pdo_mysql \
    mbstring \
    bcmath \
    xml \
    curl \
    zip \
    intl \
    gd \
    opcache \
    pcntl \
    redis

# Configure PHP runtime settings
COPY docker/php/custom.ini /usr/local/etc/php/conf.d/custom.ini

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . .

# Copy built vendor dependencies from composer stage
COPY --from=composer /app/vendor /var/www/html/vendor
# Save image cache copy to restore if host directory volume is mounted in development
COPY --from=composer /app/vendor /var/www/vendor-cache

# Copy built assets from frontend stage
COPY --from=frontend /app/public/build /var/www/html/public/build

# Copy entrypoint script
COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Ensure storage and bootstrap directories exist with proper permissions
RUN mkdir -p /var/www/html/storage/framework/cache/data \
             /var/www/html/storage/framework/sessions \
             /var/www/html/storage/framework/views \
             /var/www/html/storage/app/consents \
             /var/www/html/storage/logs \
             /var/www/html/bootstrap/cache \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Expose PHP-FPM fastcgi port
EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm"]
