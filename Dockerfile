FROM php:8.4-fpm-alpine

# Install system dependencies
RUN apk add --no-cache \
    icu-dev libzip-dev zlib-dev bash

# Install PHP extensions
RUN docker-php-ext-install intl opcache zip mysqli pdo pdo_mysql
RUN docker-php-ext-enable mysqli

# Get Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
