#!/bin/sh
set -e

# Wait for DB to become available if DB_HOST is configured
if [ -n "$DB_HOST" ]; then
    echo "==> Waiting for database connection at $DB_HOST:${DB_PORT:-3306}..."
    timeout=60
    while ! nc -z "$DB_HOST" "${DB_PORT:-3306}"; do
        timeout=$((timeout - 1))
        if [ "$timeout" -le 0 ]; then
            echo "==> Timed out waiting for database connection at $DB_HOST:${DB_PORT:-3306}"
            break
        fi
        sleep 1
    done
    echo "==> Database connection established."
fi

# Ensure all required storage and cache directories exist
echo "==> Ensuring storage directory structure and permissions..."
mkdir -p /var/www/html/storage/framework/cache/data \
         /var/www/html/storage/framework/sessions \
         /var/www/html/storage/framework/views \
         /var/www/html/storage/app/consents \
         /var/www/html/storage/logs \
         /var/www/html/bootstrap/cache

chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Restore cached vendor files if local volume mount shadowed the vendor directory
if [ ! -d "/var/www/html/vendor" ] || [ -z "$(ls -A /var/www/html/vendor 2>/dev/null)" ]; then
    if [ -d "/var/www/vendor-cache" ]; then
        echo "==> Populating vendor directory from image cache..."
        cp -a /var/www/vendor-cache/. /var/www/html/vendor/
        chown -R www-data:www-data /var/www/html/vendor
    fi
fi

# Generate application key if not set in .env
if [ -f "/var/www/html/.env" ]; then
    if ! grep -q "^APP_KEY=base64:" /var/www/html/.env; then
        echo "==> Generating application key..."
        php artisan key:generate --force
    fi
fi

# Create public storage symlink
if [ ! -L "/var/www/html/public/storage" ]; then
    echo "==> Creating storage symlink..."
    php artisan storage:link --force || true
fi

# Run migrations and seeders automatically if RUN_MIGRATIONS=true
if [ "$RUN_MIGRATIONS" = "true" ]; then
    echo "==> Running database migrations and seeders..."
    php artisan migrate --force --seed || true
fi

echo "==> Starting application process ($@)..."
exec "$@"
