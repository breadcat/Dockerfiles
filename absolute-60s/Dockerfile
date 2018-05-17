
# base image
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# update and install
RUN apk add --update bash ca-certificates coreutils sed wget

# copy script and make executable
RUN mkdir /app
COPY absolute.sh /app
RUN chmod a+x /app/absolute.sh

# run scipt
CMD /app/absolute.sh
