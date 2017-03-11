FROM debian:jessie

ARG TERM=linux
ARG DEBIAN_FRONTEND=noninteractive

# restyaboard version
ENV restyaboard_version=v0.2.1

# update & install package
RUN apt-get update --yes \
    && apt-get install --yes \
    apt-utils \
    cron \
    curl \
    less \
    nginx \
    php5 \
    php5-common \
    php5-fpm \
    php5-cli \
    php5-curl \
    php5-pgsql \
    php5-ldap \
    php5-imagick \
    php5-imap \
    postgresql-client-9.4 \
    postfix \
    syslog-ng-core \
    vim-nox \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Allow cron to run inside a container
RUN sed -i '/\(^session\s*required\s*pam_loginuid.so\)/ s/^/#/' /etc/pam.d/cron

# Replace the system() source because inside Docker we can't access /proc/kmsg.
# https://groups.google.com/forum/#!topic/docker-user/446yoB0Vx6w
RUN sed -i -E 's/^(\s*)system\(\);/\1unix-stream("\/dev\/log");/' /etc/syslog-ng/syslog-ng.conf

# Uncomment 'SYSLOGNG_OPTS="--no-caps"' to avoid the following warning:
# syslog-ng: Error setting capabilities, capability management disabled; error='Operation not permitted'
# http://serverfault.com/questions/524518/error-setting-capabilities-capability-management-disabled#
RUN sed -i 's/^#\(SYSLOGNG_OPTS="--no-caps"\)/\1/g' /etc/default/syslog-ng

# deploy app
RUN curl -L -o /tmp/restyaboard.zip https://github.com/RestyaPlatform/board/releases/download/${restyaboard_version}/board-${restyaboard_version}.zip

# volume
#VOLUME /usr/share/nginx/html

# entry point
COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["start"]

# expose port
EXPOSE 80
