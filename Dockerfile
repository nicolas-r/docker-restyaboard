FROM debian:jessie

ARG TERM=linux
ARG DEBIAN_FRONTEND=noninteractive

# restyaboard version
ENV restyaboard_version=v0.2.1

# update & install package
RUN apt-get update --yes
RUN apt-get install --yes apt-utils
RUN apt-get install --yes zip curl cron postgresql-client-9.4 nginx apt-utils
RUN apt-get install --yes php5 php5-common php5-fpm php5-cli php5-curl php5-pgsql php5-ldap php5-imagick php5-imap
RUN apt-get install --yes postfix

# deploy app
RUN curl -L -o /tmp/restyaboard.zip https://github.com/RestyaPlatform/board/releases/download/${restyaboard_version}/board-${restyaboard_version}.zip

# volume
VOLUME /usr/share/nginx/html

# entry point
COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["start"]

# expose port
EXPOSE 80
