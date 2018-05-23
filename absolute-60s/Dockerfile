
# base image
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# update and install
RUN apk add --update bash ca-certificates coreutils sed wget

# fix root user permissions
ENV PGID=1000 PUID=1000
RUN addgroup -g ${PGID} -S absolute
RUN adduser -u ${PUID} -S absolute -G absolute

# copy script and make executable
RUN mkdir /app
COPY absolute.sh /app
RUN chmod a+x /app/absolute.sh

# run scipt
USER absolute
CMD /app/absolute.sh
