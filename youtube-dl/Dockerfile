
# alpine base
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# update, install, clone repo and pull latest pr
RUN apk add --update curl ffmpeg python
RUN curl -L https://yt-dl.org/downloads/latest/youtube-dl -o /usr/local/bin/youtube-dl
RUN chmod a+rx /usr/local/bin/youtube-dl
RUN youtube-dl -U

# working directory
WORKDIR /data

# run command
ENTRYPOINT ["youtube-dl"]