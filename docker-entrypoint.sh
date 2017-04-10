#!/bin/bash

RESTYABOARD_VERSION=v0.3

function setup_timezone {
    if ! egrep -q "^${RESTYA_TIMEZONE}" /etc/timezone; then
        ln -sf /usr/share/zoneinfo/${RESTYA_TIMEZONE} /etc/localtime
        DEBIAN_FRONTEND=noninteractive dpkg-reconfigure tzdata
    fi
    if ! egrep -q "^date.timezone = ${RESTYA_TIMEZONE}" /etc/php/7.0/fpm/php.ini; then
        sed -i -e 's/^date.timezone.*/date.timezone = ${RESTYA_TIMEZONE}/g' /etc/php/7.0/fpm/php.ini
    fi
}

function setup_postfix {
    echo "postfix postfix/mailname string ${RESTYA_MAIL_DOMAIN}" | debconf-set-selections
    if [[ -z ${RESTYA_MAIL_RELAYHOST} ]]; then
        echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
    else
        echo "postfix postfix/main_mailer_type string 'Satellite system'" | debconf-set-selections
        echo "postfix postfix/relayhost string ${RESTYA_MAIL_RELAYHOST}" | debconf-set-selections
    fi
    rm -f /etc/postfix/main.cf
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure postfix
}

function extract_archive {
    unzip -q -o /tmp/restyaboard.zip -d /usr/share/nginx/html
    chgrp www-data /usr/share/nginx/html
    cd /usr/share/nginx/html
    chown -R root:www-data *
    find /usr/share/nginx/html -type f -exec chmod 640 {} \;
    find /usr/share/nginx/html -type d -exec chmod 750 {} \;
    chmod -R g+w media client/img tmp/cache
    chmod -R 0750 server/php/shell/*.sh
    # Fix #958
    sed -i 's,$total_page = ceil($c_data->count / $page_count);,$total_page = !empty($page_count) ? ceil($c_data->count / $page_count) : 0;,' /usr/share/nginx/html/server/php/R/r.php
    # Fix #768
    sed -i 's/WHERE due_date BETWEEN/WHERE notification_due_date BETWEEN/' /usr/share/nginx/html/server/php/shell/card_due_notification.php
}

function setup_nginx {
    if [[ ! -f /etc/nginx/conf.d/restyaboard.conf ]]; then
        cp /usr/share/nginx/html/restyaboard.conf /etc/nginx/conf.d
    fi

    # PHP-FPM
    sed -i 's/^.*listen.mode = 0660$/listen.mode = 0660/' /etc/php/7.0/fpm/pool.d/www.conf

    # NGINX
    sed -i "s|listen 80.*$|listen 80;|" /etc/nginx/conf.d/restyaboard.conf
    sed -i 's|^.*fastcgi_pass.*$|fastcgi_pass unix:/run/php/php7.0-fpm.sock;|' /etc/nginx/conf.d/restyaboard.conf
    sed -i -e "/fastcgi_pass/a fastcgi_param HTTPS 'off';" /etc/nginx/conf.d/restyaboard.conf
    sed -i "s/server_name.*$/server_name \"${RESTYA_SERVER_NAME}\";/" /etc/nginx/conf.d/restyaboard.conf
}

function create_database {
    # Wait for Postgresql server to be up
    export PGHOST=${RESTYA_DB_HOST}
    export PGPORT=${RESTYA_DB_PORT}
    export PGUSER=${RESTYA_DB_ADMIN_USER}
    export PGPASSWORD=${RESTYA_DB_ADMIN_PASSWORD}

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
    RES=$(psql -t -A -c "SELECT COUNT(*) FROM pg_user WHERE usename = '${RESTYA_DB_USER}';")
    if [[ "${RES}" -eq 0 ]]; then
        echo "Create user"
        psql -c "CREATE USER ${RESTYA_DB_USER} WITH ENCRYPTED PASSWORD '${RESTYA_DB_PASSWORD}'"
    fi

    # Check if the database exists, and create it if needed
    if [[ -z $(psql -Atqc "\list ${RESTYA_DB_NAME}" postgres) ]]; then
        psql -c "CREATE DATABASE ${RESTYA_DB_NAME} OWNER ${RESTYA_DB_USER} ENCODING 'UTF8' TEMPLATE template0"
        psql -c "CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;"
        psql -c "COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';"
        if [ "$?" = 0 ]; then
            # Delete some duplicates entries
            sed -i '3664d' /usr/share/nginx/html/sql/restyaboard_with_empty_data.sql
            sed -i '3664d' /usr/share/nginx/html/sql/restyaboard_with_empty_data.sql
            sed -i '3664d' /usr/share/nginx/html/sql/restyaboard_with_empty_data.sql
            sed -i '3664d' /usr/share/nginx/html/sql/restyaboard_with_empty_data.sql
            sed -i '3673d' /usr/share/nginx/html/sql/restyaboard_with_empty_data.sql

            # Populate database
            export PGUSER=${RESTYA_DB_USER}
            export PGPASSWORD=${RESTYA_DB_PASSWORD}
            psql -P pager=off -d ${RESTYA_DB_NAME} -f /usr/share/nginx/html/sql/restyaboard_with_empty_data.sql
            # Fix #705
            psql -P pager=off -d ${RESTYA_DB_NAME} -c "delete from settings where name in ('TODO', 'DOING', 'DONE') and setting_category_id = 3; delete from settings where id in (select id from settings where name = 'DEFAULT_CARD_VIEW' and setting_category_id = 3 order by id desc limit 1); delete from settings where id in (select id from settings where name in ('XMPP_CLIENT_RESOURCE_NAME', 'JABBER_HOST', 'BOSH_SERVICE_URL') and setting_category_id = 11 order by id desc limit 3); delete from settings where id in (select id from settings where name = 'chat.last_processed_chat_id' and setting_category_id = 0 order by id desc limit 1); delete from setting_categories where id in (select id from setting_categories where name = 'Cards Workflow' order by id desc limit 1);"
            # Fix #768
            psql -P pager=off -d ${RESTYA_DB_NAME} -f /root/upgrade-0.3-0.3.1.sql
        fi
    fi
    set -e
}

function configure_db_access {
    # Configure database access
    sed -i "s/^.*'R_DB_NAME'.*$/define('R_DB_NAME', '${RESTYA_DB_NAME}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
    sed -i "s/^.*'R_DB_USER'.*$/define('R_DB_USER', '${RESTYA_DB_USER}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
    sed -i "s/^.*'R_DB_PASSWORD'.*$/define('R_DB_PASSWORD', '${RESTYA_DB_PASSWORD}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
    sed -i "s/^.*'R_DB_HOST'.*$/define('R_DB_HOST', '${RESTYA_DB_HOST}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
    sed -i "s/^.*'R_DB_PORT'.*$/define('R_DB_PORT', '${RESTYA_DB_PORT}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
}

function setup_ejabberd {
    export PGHOST=${RESTYA_DB_HOST}
    export PGPORT=${RESTYA_DB_PORT}
    export PGUSER=${RESTYA_DB_ADMIN_USER}
    export PGPASSWORD=${RESTYA_DB_ADMIN_PASSWORD}

    echo "Creating database user for ejabberd"
    # Check if the user exist, and create it if needed
    RES=$(psql -t -A -c "SELECT COUNT(*) FROM pg_user WHERE usename = '${RESTYA_EJABBERD_DB_USER}';")
    if [[ "${RES}" -eq 0 ]]; then
        echo "Create user"
        psql -c "CREATE USER ${RESTYA_EJABBERD_DB_USER} WITH ENCRYPTED PASSWORD '${RESTYA_EJABBERD_DB_PASSWORD}'"
    fi

    echo "Creating database user for ejabberd"
    # Check if the database exists, and create it if needed
    if [[ -z $(psql -Atqc "\list ${RESTYA_EJABBERD_DB_NAME}" postgres) ]]; then
        psql -U postgres -c "CREATE DATABASE ${RESTYA_EJABBERD_DB_NAME} OWNER ${RESTYA_EJABBERD_DB_USER} ENCODING 'UTF8' TEMPLATE template0"
        if [ "$?" = 0 ]; then
            # Populate database
            export PGUSER=${RESTYA_EJABBERD_DB_USER}
            export PGPASSWORD=${RESTYA_EJABBERD_DB_PASSWORD}
            cp /usr/share/doc/ejabberd/examples/pg.sql.gz /tmp
            gunzip /tmp/pg.sql.gz
            psql -P pager=off -d ${RESTYA_EJABBERD_DB_NAME} -f /tmp/pg.sql
            rm -f /tmp/pg.sql
        fi
    fi

    ### SERVER ###
    cp /root/ejabberd.yml /etc/ejabberd/ejabberd.yml
    sed -i "s/CHANGE_HOSTNAME/${RESTYA_SERVER_NAME}/g" /etc/ejabberd/ejabberd.yml
    sed -i "s/CHANGE_DB_HOST/${RESTYA_EJABBERD_DB_HOST}/g" /etc/ejabberd/ejabberd.yml
    sed -i "s/CHANGE_DB_PORT/${RESTYA_EJABBERD_DB_PORT}/g" /etc/ejabberd/ejabberd.yml
    sed -i "s/CHANGE_DB_NAME/${RESTYA_EJABBERD_DB_NAME}/g" /etc/ejabberd/ejabberd.yml
    sed -i "s/CHANGE_DB_USER/${RESTYA_EJABBERD_DB_USER}/g" /etc/ejabberd/ejabberd.yml
    sed -i "s/CHANGE_DB_PASSWORD/${RESTYA_EJABBERD_DB_PASSWORD}/g" /etc/ejabberd/ejabberd.yml
    chown ejabberd:ejabberd /etc/ejabberd/ejabberd.yml
    service ejabberd start
    ejabberdctl change_password admin ${RESTYA_SERVER_NAME} restya
    service ejabberd restart

    ### RESTYABOARD ###
    sed -i "s/^.*'CHAT_DB_NAME'.*$/define('CHAT_DB_NAME', '${RESTYA_EJABBERD_DB_NAME}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
    sed -i "s/^.*'CHAT_DB_USER'.*$/define('CHAT_DB_USER', '${RESTYA_EJABBERD_DB_USER}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
    sed -i "s/^.*'CHAT_DB_PASSWORD'.*$/define('CHAT_DB_PASSWORD', '${RESTYA_EJABBERD_DB_PASSWORD}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
    sed -i "s/^.*'CHAT_DB_HOST'.*$/define('CHAT_DB_HOST', '${RESTYA_EJABBERD_DB_HOST}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
    sed -i "s/^.*'CHAT_DB_PORT'.*$/define('CHAT_DB_PORT', '${RESTYA_EJABBERD_DB_PORT}');/g" "/usr/share/nginx/html/server/php/config.inc.php"
}

function add_cron_jobs {
    if [[ ! -f /var/spool/cron/crontabs/root ]]; then
        touch /var/spool/cron/crontabs/root
        chmod 600 /var/spool/cron/crontabs/root
    fi

    if ! grep -q "indexing_to_elasticsearch.sh" /var/spool/cron/crontabs/root; then
        echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/indexing_to_elasticsearch.sh > /dev/null 2>&1" >> /var/spool/cron/crontabs/root
    fi

    if ! grep -q "instant_email_notification.sh" /var/spool/cron/crontabs/root; then
        echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/instant_email_notification.sh > /dev/null 2>&1" >> /var/spool/cron/crontabs/root
    fi

    if ! grep -q "periodic_email_notification.sh" /var/spool/cron/crontabs/root; then
        echo "0 * * * * /usr/share/nginx/html/server/php/shell/periodic_email_notification.sh > /dev/null 2>&1" >> /var/spool/cron/crontabs/root
    fi

    if ! grep -q "imap.sh" /var/spool/cron/crontabs/root; then
        echo "*/30 * * * * /usr/share/nginx/html/server/php/shell/imap.sh > /dev/null 2>&1" >> /var/spool/cron/crontabs/root
    fi

    if ! grep -q "webhook.sh" /var/spool/cron/crontabs/root; then
        echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/webhook.sh > /dev/null 2>&1" >> /var/spool/cron/crontabs/root
    fi

    if ! grep -q "card_due_notification.sh" /var/spool/cron/crontabs/root; then
        echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/card_due_notification.sh > /dev/null 2>&1" >> /var/spool/cron/crontabs/root
    fi

    if ! grep -q "chat_activities.sh" /var/spool/cron/crontabs/root; then
        echo "*/5 * * * * /usr/share/nginx/html/server/php/shell/chat_activities.sh > /dev/null 2>&1" >> /var/spool/cron/crontabs/root
    fi

    if ! grep -q "periodic_chat_email_notification.sh.sh" /var/spool/cron/crontabs/root; then
        echo "0 * * * * /usr/share/nginx/html/server/php/shell/periodic_chat_email_notification.sh > /dev/null 2>&1" >> /var/spool/cron/crontabs/root
    fi
}

function clean_old_files {
    cd /usr/share/nginx/html
    rm -rf server/php/R/shell server/php/R/libs server/php/R/image.php server/php/R/config.inc.php server/php/R/authorize.php server/php/R/oauth_callback.php server/php/R/download.php server/php/R/ical.php
}

function upgrade_database {
    export PGHOST=${RESTYA_DB_HOST}
    export PGPORT=${RESTYA_DB_PORT}
    export PGUSER=${RESTYA_DB_USER}
    export PGPASSWORD=${RESTYA_DB_PASSWORD}

    # Fix #705
    psql -P pager=off -d ${RESTYA_DB_NAME} -c "delete from settings where name in ('TODO', 'DOING', 'DONE') and setting_category_id = 3; delete from settings where id in (select id from settings where name = 'DEFAULT_CARD_VIEW' and setting_category_id = 3 order by id desc limit 1); delete from settings where id in (select id from settings where name in ('XMPP_CLIENT_RESOURCE_NAME', 'JABBER_HOST', 'BOSH_SERVICE_URL') and setting_category_id = 11 order by id desc limit 3); delete from settings where id in (select id from settings where name = 'chat.last_processed_chat_id' and setting_category_id = 0 order by id desc limit 1); delete from setting_categories where id in (select id from setting_categories where name = 'Cards Workflow' order by id desc limit 1);"

    psql -P pager=off -d ${RESTYA_DB_NAME} -f /usr/share/nginx/html/sql/${RESTYABOARD_VERSION}.sql

    # Fix #768
    psql -P pager=off -d ${RESTYA_DB_NAME} -f /root/upgrade-0.3-0.3.1.sql
}

set -e

if [[ -f /usr/share/nginx/html/.release ]]; then
    CURRENT_VERSION=$(cat /usr/share/nginx/html/.release)
else
    CURRENT_VERSION="v0"
fi
echo "RESTYABOARD version detected : ${CURRENT_VERSION}"

# Check if we have already do the installation or not
if [[ ! -f /usr/share/nginx/html/.install_done ]]; then
    # Configure timezone
    echo "*** Configure timezone ***"
    setup_timezone

    # Configure postfix
    echo "*** Configure Postfix ***"
    setup_postfix

    # Extract the ZIP archive
    echo "*** Extract archive ***"
    extract_archive

    # Configure nginx & php-fpm
    echo "*** Configure NGINX & PHP-FPM ***"
    setup_nginx

    # Create database
    echo "*** Create database ***"
    create_database

    # Configure DB access
    echo "*** Configure database access in Restyaboard ***"
    configure_db_access

    # Add cron jobs
    echo "*** Add cron jobs ***"
    add_cron_jobs

    # Setup ejabberd
    echo "*** Configure Ejabberd ***"
    setup_ejabberd

    /bin/echo "${RESTYABOARD_VERSION}" > /usr/share/nginx/html/.release
    touch /usr/share/nginx/html/.install_done
elif [[ ${CURRENT_VERSION} < ${RESTYABOARD_VERSION} ]]; then
    echo "UPGRADE MODE : ${CURRENT_VERSION} to ${RESTYABOARD_VERSION}"

    # Configure timezone
    echo "*** Configure timezone ***"
    setup_timezone

    # Configure postfix
    echo "*** Configure Postfix ***"
    setup_postfix

    # Extract the ZIP archive
    echo "*** Extract archive ***"
    extract_archive

    # Configure nginx & php-fpm
    echo "*** Configure NGINX & PHP-FPM ***"
    setup_nginx

    # Setup ejabberd
    echo "*** Configure Ejabberd ***"
    setup_ejabberd

    # Configure DB access
    echo "*** Configure database access in Restyaboard ***"
    configure_db_access

    # Add cron jobs
    echo "*** Add cron jobs ***"
    add_cron_jobs

    # Clean old files
    echo "*** Clean old files ***"
    clean_old_files

    # Upgrade database
    echo "*** Upgrade database ***"
    upgrade_database

    echo "*** Launch upgrade php scripts ***"
    php /usr/share/nginx/html/server/php/shell/upgrade_v0.2.1_v0.3.php

    /bin/echo "${RESTYABOARD_VERSION}" > /usr/share/nginx/html/.release
fi

# service start
service syslog-ng start
service cron start
service php7.0-fpm start
service nginx start
service postfix start

# tail log
exec tail -f /var/log/nginx/access.log /var/log/nginx/error.log

exec "$@"
