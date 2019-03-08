
FROM nginx
MAINTAINER Peter <peter@minskio.co.uk>

RUN printf "server {listen 80; location / {root /pool; autoindex on;}}">/etc/nginx/conf.d/default.conf

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
