# Docker image for Restyaboard

Build Restyaboard in Docker.

* Restyaboard  
  http://restya.com/board/

* Docker  
  https://www.docker.com/
  
* Initial work by [namikingsoft](https://github.com/namikingsoft/docker-restyaboard)

# Warnings

* With the new versions starting with 0.3.0 pushed recently, I have tried to deal with an automatic upgrade to the next version, for example 0.2.1 to 0.3.0 or 0.3.0 to 0.4.0 but not 0.2.1 to 0.4.0. Even if I have done a lot of test, take a full backup before!
* Starting with version 0.4.0, the Postgresql image used is now 9.6-alpine, so an upgrade step is necessary between 0.3.0 and 0.4.0. A special docker-compose file is included in the 0.4.0 git, that will bring online two containers (don't forget to adapt the paths to your environment) :
  * One with Posgresql 9.4 with the current data
  * A second with Postgresql 9.6

  But doing everything, take a full backup before!  
  When the container are up, attach a shell to the one running Postgresql 9.4 and issue the following command:  
  `pg_dumpall -U postgres | psql -h postgres96 -U postgres`  
  After that, stop the containers, adapt the paths in docker-compose.yml to your environment and you can build and start the containers, everything should work.

# Quick Start

* Check out the git repository
* Edit the docker-compose.yaml file to reflect your environment (see configuration variables below)
* Build image
* Run container using docker-compose.

``` bash
git clone https://github.com/nicolas-r/docker-restyaboard.git
cd docker-restyaboard
vim docker-compose.yml
docker-compose up -d
```
Please wait a few minutes to complete initialize.

# Configuration variables

1. Version 0.2.1
  * restyaboard
    * POSTGRES_APP_DB_HOST: hostname of the database server
    * POSTGRES_APP_DB_PORT: TCP port to reach the database server
    * POSTGRES_APP_DB_NAME: name of the database to create/use for Restyaboard
    * POSTGRES_APP_DB_USER: name of the database user to create/use to connect to the database
    * POSTGRES_APP_DB_PASSWORD: password of the database user
    * TIMEZONE: timezone to configure on the server and in php-fpm
    * WEB_SERVER_NAME: server name for nginx configuration
    * MAIL_DOMAIN: domain for sending mail
    * MAIL_RELAYHOST: hostname of the relay host if needed (optional)

1. Version 0.3.0+
  * restyaboard
    * RESTYA_DB_ADMIN_USER: username of the Postgresql's admin
    * RESTYA_DB_ADMIN_PASSWORD: password of the Postgresql's admin
    * RESTYA_DB_HOST: hostname of the database server for Restyaboard
    * RESTYA_DB_PORT: TCP port to reach the database server for Restyaboard
    * RESTYA_DB_NAME: name of the database for Restyaboard
    * RESTYA_DB_USER: username to connect to the database for Restyaboard
    * RESTYA_DB_PASSWORD: password of the username use to connect to the Restyaboard database
    * RESTYA_TIMEZONE: timezone to configure on the server and in php-fpm
    * RESTYA_SERVER_NAME: server name for nginx configuration
    * RESTYA_MAIL_DOMAIN: domain for sending mail
    * RESTYA_EJABBERD_DB_HOST: hostname of the database server for ejabberd
    * RESTYA_EJABBERD_DB_PORT: TCP port to reach the database server for ejabberd
    * RESTYA_EJABBERD_DB_NAME: name of the database to use for ejabberd
    * RESTYA_EJABBERD_DB_USER: username to connect to the ejabberd database
    * RESTYA_EJABBERD_DB_PASSWORD: password of the username use to connect to the ejabberd database
    * RESTYA_MAIL_RELAYHOST: hostname of the relay host if needed (optional)

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
