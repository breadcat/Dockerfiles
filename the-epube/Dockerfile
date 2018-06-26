
# base image
FROM php:apache
MAINTAINER Peter <peter@minskio.co.uk>

# update repo and install some dependencies
RUN apt-get update
RUN apt-get install -y git-core sqlite3

# clone application
RUN git clone "https://git.tt-rss.org/fox/the-epube.git" "/var/www/html/"

# configure application
RUN mv "/var/www/html/config.php-dist" "/var/www/html/config.php"

# set up database
RUN sqlite3 "/var/www/html/db/scratch.db" < "/var/www/html/schema.sql"

# set up permissions
RUN chown www-data "/var/www/html" -R
RUN chmod 755 "/var/www/html/sessions" -R

# expose ports
EXPOSE 80/tcp

# run apache
# RUN a2enmod rewrite
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
