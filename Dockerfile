FROM ubuntu:16.04

ARG TERM=linux
ARG DEBIAN_FRONTEND=noninteractive

# restyaboard version
ENV RESTYABOARD_VERSION=v0.3

# Some tuning
RUN echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/02apt-speedup \
    && echo "Acquire::http {No-Cache=True;};" > /etc/apt/apt.conf.d/no-cache

# Configure backports
#RUN echo deb http://ftp.debian.org/debian jessie-backports main contrib non-free > /etc/apt/sources.list.d/jessie-backports.list

# update & install package
RUN apt-get update --yes \
    && apt-get install --yes --no-install-recommends \
    apt-utils \
    cron \
    curl \
    ejabberd \
    erlang-p1-pgsql \
    geoip-database-extra \
    imagemagick \
    less \
    nginx \
    php \
    php-cli \
    php-common \
    php-curl \
    php-fpm \
    php-geoip \
    php-imagick \
    php-imap \
    php-ldap \
    php-mbstring \
    php-pgsql \
    php-xml \
    postgresql-client \
    postfix \
    syslog-ng-core \
    vim-nox \
    unzip \
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
RUN curl -L -o /tmp/restyaboard.zip https://github.com/RestyaPlatform/board/releases/download/${RESTYABOARD_VERSION}/board-${RESTYABOARD_VERSION}.zip

COPY ejabberd.yml /root
COPY upgrade-0.3-0.3.1.sql /root
COPY upgrade-0.2.1-0.3.sql /root

# entry point
COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["start"]

# expose port
EXPOSE 80
