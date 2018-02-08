
# base image
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# update, install, clone repo
RUN apk add --update git python
RUN git clone https://github.com/SourceDoctor/py-kms.git

# expose ports
EXPOSE 1688/tcp

# run command
CMD ["python", "py-kms/server.py"]
