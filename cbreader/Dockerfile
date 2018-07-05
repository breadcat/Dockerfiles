
# to resolve broken comic covers, you can grab the firsts issue via:
# for i in /comics/*; do cd "$i" && wget -O cover.jpg "ADDRESS/api.php?get=cover&comic=$(pwd | sed 's#.*/##')&issue=$(ls | head -1)" && cd .. ; done

# base image
FROM php:apache
MAINTAINER Peter <peter@minskio.co.uk>

# update and install packages
RUN apt-get update
RUN apt-get install --no-install-recommends -y git libmagickwand-dev libzip-dev
RUN yes | pecl install imagick zip
RUN docker-php-ext-enable imagick zip

# fetch application from git and configure
RUN git clone "https://github.com/jangrewe/cbreader.git" /var/www/html/
RUN mv "/var/www/html/config.php-dist" "/var/www/html/config.php"
RUN sed -i -e 's/\/path\/to//' "/var/www/html/config.php"

# expose ports
EXPOSE 80

# run apache
CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
