ARG PHP_VERSION=8.2
FROM php:${PHP_VERSION}-cli

# Install system packages and PHP extensions
RUN apt-get update && apt-get install -y \
    default-mysql-client git \
    && docker-php-ext-install mysqli pdo pdo_mysql \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --chmod=0555 php-entrypoint.sh /
ENTRYPOINT /php-entrypoint.sh

RUN git clone --single-branch --depth 1 --branch php-$PHP_VERSION https://github.com/php/php-src.git /php-src
WORKDIR /php-src
