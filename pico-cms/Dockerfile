
# base image
FROM php:apache
MAINTAINER Peter <peter@minskio.co.uk>

# variables
ENV VER=1.0.6

# add application and unpack
ADD "https://github.com/picocms/Pico/releases/download/v$VER/pico-release-v$VER.tar.gz" "/var/www/html/pico-release-v${VER}.tar.gz"
RUN tar -xzf "/var/www/html/pico-release-v${VER}.tar.gz"
RUN rm "/var/www/html/pico-release-v${VER}.tar.gz"

# configure application
RUN mkdir -p "/var/www/html/content"
RUN mv "/var/www/html/config/config.php.template" "/var/www/html/config/config.php"

# expose ports
EXPOSE 80/tcp

# run apache
RUN a2enmod rewrite
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
