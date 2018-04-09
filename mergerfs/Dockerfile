
# alpine base
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# update, install
RUN apk add --update mergerfs

# working directory
WORKDIR /mnt

# run command
ENTRYPOINT [mergerfs "-d -o defaults,allow_other,use_ino" "/mnt/disk-*" "/mnt/pool"]