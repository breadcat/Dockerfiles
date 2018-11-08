
# base image
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# variables
ENV VER=3.17

# add dependencies
RUN apk --update add ca-certificates ffmpeg openssl perl-mojolicious perl-lwp-protocol-https perl-xml-simple perl-xml-libxml
RUN mkdir -p /data/output /data/config
WORKDIR /app

# add application and unpack
RUN wget -qO- https://github.com/get-iplayer/get_iplayer/archive/v${VER}.tar.gz | tar -xvz -C /tmp
RUN mv /tmp/get_iplayer-${VER}/get_iplayer .
RUN rm -rf /tmp/*
RUN chmod a+x ./get_iplayer

# run command
ENTRYPOINT ["./get_iplayer", "--ffmpeg", "/usr/bin/ffmpeg", "--profile-dir", "/data/config", "--output", "/data/output"]
CMD ["-h"]
