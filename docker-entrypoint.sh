#!/bin/bash

# TODO
#
# Deal with upgrade ?

set -e

# Configure timezone
if ! egrep -q "^${TIMEZONE}" /etc/timezone; then
    echo "${TIMEZONE}" > /etc/timezone
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure tzdata
fi
if ! egrep -q "^date.timezone = ${TIMEZONE}" /etc/php5/fpm/php.ini; then
    sed -i -e 's/^date.timezone.*/date.timezone = ${TIMEZONE}/g' /etc/php5/fpm/php.ini
    #echo "date.timezone = ${TIMEZONE}" >> /etc/php5/fpm/php.ini
fi

# Configure postfix
echo "postfix postfix/mailname string ${MAIL_DOMAIN}" | debconf-set-selections
if [[ -z ${MAIL_RELAYHOST} ]]; then
    echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
else
    echo "postfix postfix/main_mailer_type string 'Satellite system'" | debconf-set-selections
    echo "postfix postfix/relayhost string ${MAIL_RELAYHOST}" | debconf-set-selections
fi
rm -f /etc/postfix/main.cf
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure postfix

# Check if we need to extract the zip archive of not
if [[ ! -f /usr/share/nginx/html/.unpack_done ]]; then
    unzip /tmp/restyaboard.zip -d /usr/share/nginx/html
    chgrp www-data /usr/share/nginx/html
    cd /usr/share/nginx/html
    chown -R root:www-data *
    find /usr/share/nginx/html -type f -exec chmod 640 {} \;
    find /usr/share/nginx/html -type d -exec chmod 750 {} \;
    chmod -R g+w media client/img tmp/cache
    chmod -R 0750 server/php/shell/*.sh
    cp restyaboard.conf /etc/nginx/conf.d
    touch /usr/share/nginx/html/.unpack_done
fi

# Change some configuration files@
sed -i 's/^.*listen.mode = 0660$/listen.mode = 0660/' /etc/php5/fpm/pool.d/www.conf
sed -i "s|listen 80.*$|listen 80;|" /etc/nginx/conf.d/restyaboard.conf
sed -i 's|^.*fastcgi_pass.*$|fastcgi_pass unix:/var/run/php5-fpm.sock;|' /etc/nginx/conf.d/restyaboard.conf
sed -i -e "/fastcgi_pass/a fastcgi_param HTTPS 'off';" /etc/nginx/conf.d/restyaboard.conf
sed -i "s/server_name.*$/server_name \"${WEB_SERVER_NAME}\";/" /etc/nginx/conf.d/restyaboard.conf

# Configure database access
sed -i "s/^.*'R_DB_NAME'.*$/define('R_DB_NAME', '${POSTGRES_APP_DB_NAME}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
sed -i "s/^.*'R_DB_USER'.*$/define('R_DB_USER', '${POSTGRES_APP_DB_USER}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
sed -i "s/^.*'R_DB_PASSWORD'.*$/define('R_DB_PASSWORD', '${POSTGRES_APP_DB_PASSWORD}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
sed -i "s/^.*'R_DB_HOST'.*$/define('R_DB_HOST', '${POSTGRES_APP_DB_HOST}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
sed -i "s/^.*'R_DB_PORT'.*$/define('R_DB_PORT', '${POSTGRES_APP_DB_PORT}');/g" "/usr/share/nginx/html/server/php/config.inc.php"

# Add cron jobs
if [[ ! -f /var/spool/cron/crontabs/root ]]; then
    touch /var/spool/cron/crontabs/root
    chmod 600 /var/spool/cron/crontabs/root
fi
if ! grep -q "indexing_to_elasticsearch.sh" /var/spool/cron/crontabs/root; then
    echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/indexing_to_elasticsearch.sh" >> /var/spool/cron/crontabs/root
fi
if ! grep -q "instant_email_notification.sh" /var/spool/cron/crontabs/root; then
    echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/instant_email_notification.sh" >> /var/spool/cron/crontabs/root
fi
if ! grep -q "periodic_email_notification.sh" /var/spool/cron/crontabs/root; then
    echo "0 * * * * /usr/share/nginx/html/server/php/shell/periodic_email_notification.sh" >> /var/spool/cron/crontabs/root
fi
if ! grep -q "webhook.sh" /var/spool/cron/crontabs/root; then
    echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/webhook.sh" >> /var/spool/cron/crontabs/root
fi
if ! grep -q "card_due_notification.sh" /var/spool/cron/crontabs/root; then
    echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/card_due_notification.sh" >> /var/spool/cron/crontabs/root
fi
if ! grep -q "imap.sh" /var/spool/cron/crontabs/root; then
    echo "*/30 * * * * /usr/share/nginx/html/server/php/shell/imap.sh" >> /var/spool/cron/crontabs/root
fi

export PGHOST=${POSTGRES_APP_DB_HOST}
export PGPORT=${POSTGRES_APP_DB_PORT}
export PGUSER=${POSTGRES_ENV_POSTGRES_USER}
export PGPASSWORD=${POSTGRES_ENV_POSTGRES_PASSWORD}

# Wait for Postgresql server to be up
set +e
while :
do
    psql -c "\q"
    if [ "$?" = 0 ]; then
        break
    fi
    sleep 1
done

# Check if the user exist, and create it if needed
RES=$(psql -t -A -c "SELECT COUNT(*) FROM pg_user WHERE usename = '${POSTGRES_APP_DB_USER}';")
if [[ "${RES}" -eq 0 ]]; then
    echo "Create user"
    psql -c "CREATE USER ${POSTGRES_APP_DB_USER} WITH ENCRYPTED PASSWORD '${POSTGRES_APP_DB_PASSWORD}'"
fi

# Check if the database exists, and create it if needed
if [[ -z $(psql -Atqc "\list ${POSTGRES_APP_DB_NAME}" postgres) ]]; then
    psql -U postgres -c "CREATE DATABASE ${POSTGRES_APP_DB_USER} OWNER ${POSTGRES_APP_DB_PASSWORD} ENCODING 'UTF8' TEMPLATE template0"
    psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;"
    psql -U postgres -c "COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';"
    if [ "$?" = 0 ]; then
        # Populate database
        export PGUSER=${POSTGRES_APP_DB_USER}
        export PGPASSWORD=${POSTGRES_APP_DB_PASSWORD}
        psql -d restyaboard -f /usr/share/nginx/html/sql/restyaboard_with_empty_data.sql
    fi
fi
set -e

# service start
service cron start
service php5-fpm start
service nginx start
service postfix start

# tail log
exec tail -f /var/log/nginx/access.log /var/log/nginx/error.log

exec "$@"
