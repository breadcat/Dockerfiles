
# base image
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# update and install
RUN apk add --update bash git python2 py2-pip
RUN pip install --upgrade pip setuptools
RUN pip install flexget transmissionrpc

# buggy when not run as root, but buggy when run as root too
ENV USER=root
# ENV PGID=1000 PUID=1000 USER=flexget
# RUN addgroup -g ${PGID} -S ${USER}
# RUN adduser -u ${PUID} -S ${USER} -G ${USER}

# hourly cron run for flexget user
RUN printf "0 */1 * * * /usr/bin/flexget --cron execute\n">/var/spool/cron/crontabs/${USER}

# run crond
# RUN crontab -u ${USER} /var/spool/cron/crontabs/${USER}
CMD crond -f -l 2
