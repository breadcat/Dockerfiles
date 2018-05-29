
# base image
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# update and install
RUN apk add --update bash git python3 py-pip sed

# fetch application and install requirements
RUN mkdir /app
RUN git clone "https://github.com/KartikTalwar/Duolingo.git" /app
RUN pip install -r /app/requirements.txt

# copy script and make executable
COPY duo-auto.py /app
RUN chmod a+x /app/duo-auto.py

# setup crond
RUN printf "0 */8 * * * python /app/duo-auto.py\n">/var/spool/cron/crontabs/root

# run crond
CMD crond -f
