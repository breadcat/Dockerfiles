
# base image
FROM alpine
MAINTAINER Peter <peter@minskio.co.uk>

# expose variables
ENV DUOUSER username
ENV DUOPASS password
ENV DUOINT 8

# update and install
RUN apk add --update git python3 py-pip

# fetch application and install requirements
RUN git clone "https://github.com/KartikTalwar/Duolingo.git" /Duolingo/
RUN pip install -r /Duolingo/requirements.txt

# test echo variables
RUN echo ${DUOUSER} : ${DUOPASS}

# write script and make executable
RUN printf "#!/usr/bin/env python3\n\n">/Duolingo/duolingo-auto.py
RUN printf "import duolingo\n">>/Duolingo/duolingo-auto.py
RUN printf "lingo = duolingo.Duolingo('${DUOUSER}', password='${DUOPASS}')\n">>/Duolingo/duolingo-auto.py
RUN printf "lingo.buy_item('streak_freeze', 'nb')\n">>/Duolingo/duolingo-auto.py
RUN chmod a+x /Duolingo/duolingo-auto.py

# test script, ensure test passes
RUN python /Duolingo/duolingo-auto.py || :

# setup crond
RUN printf "0 */${DUOINT} * * * python /Duolingo/duolingo-auto.py\n">/var/spool/cron/crontabs/root

# run crond
CMD crond -l 2 -f
