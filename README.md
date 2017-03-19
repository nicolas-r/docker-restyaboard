# Docker Restyaboard

Build Restyaboard in Docker.

* Restyaboard  
  http://restya.com/board/

* Docker  
  https://www.docker.com/

# Warning

With the new version 0.3.0 pushed recently, I have tried to deal with an automatic upgrade from 0.2.1 to 0.3.0. Even if I have done a lot of test, take a full backup before !

# Initial work

This is a fork of the work of Namikingsoft (https://github.com/namikingsoft/docker-restyaboard) with some modifications:

1. Dockerfile
  * Use Jessie instead of wheezy-backports
  * The configuration of Postfix is now made in the docker-entrypoint.sh script
  * The configuration of nginx is now made in the docker-entrypoint.sh script
  * The extraction of the Restyaboard zip archive is now made in the docker-entrypoint.sh script
  * The permanent volume is now /usr/share/nginx/html instead of /usr/share/nginx/html/media

2. docker-compose.yml
  * postgresql
     * Specified the version to use : 9.4
  * restyaboard
     * Add several variables
        * POSTGRES_APP_DB_HOST: hostname of the database server
        * POSTGRES_APP_DB_PORT: TCP port to reach the database server
        * POSTGRES_APP_DB_NAME: name of the database to create/use for Restyaboard
        * POSTGRES_APP_DB_USER: name of the database user to create/use to connect to the database
        * POSTGRES_APP_DB_PASSWORD: password of the database user
        * TIMEZONE: timezone to configure on the server and in php-fpm
        * WEB_SERVER_NAME: server name for nginx configuration
        * MAIL_DOMAIN: domain for sending mail
        * MAIL_RELAYHOST: hostname of the relay host if needed (optional)
        
     Attention : Since version 0.3.0, the variables have been renamed, you have to review them

3. docker-entrypoint.sh
  * The extracted files/directories from the Restyaboard zip archive now belong to root:www-data and other's permissions have been removed
  * Restyaboard is now using a dedicated user to acess the Postgresql database
  * Add test to avoid duplicate entries/tasks when the container is restarting

# Quick Start

* Edit the docker-compose.yaml file to reflect your environment
* Build image and Run container using docker-compose.

``` bash
git clone https://github.com/nicolas-r/docker-restyaboard.git
cd docker-restyaboard
vim docker-compose.yml
docker-compose up -d
```

Please wait a few minutes to complete initialize.

# Check URL

```
http://(ServerIP):1234

Username: admin
Password: restya

Username: user
Password: restya
```

License
------------------------------

[OSL 3.0](LICENSE.txt) fits in Restyaboard.
