#!/bin/bash

EVALS=$(cat <<'_EOF_'
WORDPRESS_SITENAME=${WORDPRESS_SITENAME:-mywordpress}
WORDPRESS_ADMIN=${WORDPRESS_ADMIN:-admin}
WORDPRESS_ADMIN_PASSWORD=${WORDPRESS_ADMIN_PASSWORD:-password}
WORDPRESS_ADMIN_EMAIL=${WORDPRESS_ADMIN_EMAIL:-admin@example.com}
MYSQL_HOST=${MYSQL_HOST:-mysql}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-password}
MYSQL_WORDPRESS_PASSWORD=${MYSQL_WORDPRESS_PASSWORD:-password}
_WORDPRESS_ROOT='/var/www-nginx/wordpress'
_DIR_PHP_FPM_RUN='/var/run/php-fpm'
_DIR_PHP_SESSION='/var/lib/php/session'
_NO_LOGIN_SHELL='/usr/sbin/nologin'
_EOF_
)
eval "$EVALS"

addgroup \
    -g "${GID_NGINX-}" \
    nginx
adduser \
    -u "${UID_NGINX-}" \
    -G nginx \
    -s ${_NO_LOGIN_SHELL-} \
    -D -H \
    nginx

apk update

# Setup OpenRC
apk add openrc
sed -i \
    -e 's/#\(rc_sys=\).*$/\1"docker"/g' \
    -e 's/^#\(rc_logger="YES"\)$/\1/' \
        /etc/rc.conf
cat >> /etc/rc.conf <<'_EOF_'
rc_logger="YES"
rc_env_allow="*"
rc_crashed_stop=NO
rc_crashed_start=YES
rc_provide="loopback net"
_EOF_
sed -i \
    -e '/^tty[0-9]/d' \
        /etc/inittab 
# sed -i \
#     -e 's/^\(\s*hostname $opts\)/#\1/g' \
#         /etc/init.d/hostname
sed -i \
    -e 's/^\(\s*mount -t tmpfs\)/#\1/g' \
    -e 's/VSERVER/DOCKER/Ig' \
        /lib/rc/sh/init.sh 
sed -i \
    -e 's/^\(\s*cgroup_add_service \)/#\1/g' \
        /lib/rc/sh/openrc-run.sh
rm -f \
    /etc/init.d/hwdrivers \
    /etc/init.d/hwclock \
    /etc/init.d/hwdrivers \
    /etc/init.d/modules \
    /etc/init.d/modules-load \
    /etc/init.d/modloop

# Install Packages
apk add \
    musl
apk add \
    logrotate
apk add \
    tar curl sudo sed perl bash-completion less
apk add \
    mariadb-common mariadb-client mysql-client

# PHP7
# PHP7 : Prerequisities
apk add \
    curl curl-dev
# PHP7 : Extensions
apk add \
    php7 php7-fpm php7-pear php7-phar \
    php7-openssl php7-zlib \
    php7-mysqli php7-pdo_mysql php7-gd \
    php7-xml php7-xmlreader php7-xmlrpc php7-xmlwriter \
    php7-ctype php7-dom php7-curl php7-zip \
    php7-json php7-mbstring
# PHP7 Tuning Up
apk add \
    php7-apcu php7-opcache

sed -i \
    -e 's|^\(memory_limit\s\{0,\}=\)\s\{0,\}.*$|\1 256M|' \
    -e 's|^\(post_max_size\)[[:blank:]].*$|\1 = 1024M|' \
    -e 's|^\(upload_max_filesize\)[[:blank:]].*$|\1 = 1024M|' \
        /etc/php7/php.ini

# PHP7-FPM
mv /etc/php7/php-fpm.d/www.conf{,.orig}
grep -v '^;' /etc/php7/php-fpm.d/www.conf.orig \
    | grep -v '^$' \
    | sed \
        -e 's/^\(user\|group\)\(\s*=\s\)*.*$/\1\2nginx/' \
        -e 's/^\(listen\s*=\).*$/\1 9000/' \
    > /etc/php7/php-fpm.d/www.conf

for i in $_WORDPRESS_ROOT $_DIR_PHP_FPM_RUN $_DIR_PHP_SESSION
do
    mkdir -p $i
    chown nginx.nginx $i
done
chmod -R g+w,g+s $_WORDPRESS_ROOT
chmod 0775 $_DIR_PHP_FPM_RUN
chmod g+s $_DIR_PHP_FPM_RUN
chmod 0770 $_DIR_PHP_SESSION


# wp-cli
curl \
    -o /usr/local/bin/wp \
    https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp
cat <<'_EOF_' > /usr/local/bin/wp-root
#!/bin/bash
/usr/local/bin/wp --allow-root $@
_EOF_
chmod +x /usr/local/bin/wp-root

chmod g+s $_WORDPRESS_ROOT

cat > /var/docker/docker-entrypoint.sh <<_EOF_
#!/bin/bash
exec > /var/docker/_prep/log/container.log 2>&1

$EVALS

_EOF_

cat >> /var/docker/docker-entrypoint.sh <<'_EOF_docker_entrypoint'
do_download_wordpress_core() {
    ls -laR $_WORDPRESS_ROOT
    cd $_WORDPRESS_ROOT
    sudo -u nginx \
        wp core download
    [[ -f "$_WORDPRESS_ROOT/wp-config.php" ]] \
        && mv $_WORDPRESS_ROOT/wp-config.php{,.orig}
    chmod -R g+w $_WORDPRESS_ROOT
    find $_WORDPRESS_ROOT -type d -exec chmod g+s {} \;
    chown -R nginx.nginx $_WORDPRESS_ROOT
}

[[ ! -d "$_WORDPRESS_ROOT" ]] \
    && mkdir -p $_WORDPRESS_ROOT
if [[ -d "$_WORDPRESS_ROOT" ]]; then
    chown -R nginx.nginx $_WORDPRESS_ROOT
    chmod -R g+w,g+s $_WORDPRESS_ROOT
fi
[[ -f "$_WORDPRESS_ROOT/wp-config.php" ]] \
    || do_download_wordpress_core

MYSQL_DATABASE=${WORDPRESS_SITENAME}
MYSQL_USER=${WORDPRESS_SITENAME}

_MYSQL_ROOT="mysql -h${MYSQL_HOST} -uroot -p${MYSQL_ROOT_PASSWORD}"

until $_MYSQL_ROOT -se 'SHOW DATABASES;'
do
    echo \
        '['$(date -D 'YYYY-MM-DD hh:mm:ss')']' \
        'Waiting for getting MySQL up'
    sleep 10
done

function do_create_database() {
    $_MYSQL_ROOT <<_EOF_
        CREATE DATABASE \`${MYSQL_DATABASE}\`;
        CREATE USER \`${MYSQL_USER}\`@\`localhost\`
            IDENTIFIED BY "${MYSQL_WORDPRESS_PASSWORD}";
        CREATE USER \`${MYSQL_USER}\`@\`%\`
            IDENTIFIED BY "${MYSQL_WORDPRESS_PASSWORD}";
        GRANT ALL ON \`${MYSQL_DATABASE}\`.*
            TO \`${MYSQL_USER}\`@\`localhost\`;
        GRANT ALL ON \`${MYSQL_DATABASE}\`.*
            TO \`${MYSQL_USER}\`@\`%\`;
        FLUSH PRIVILEGES;
_EOF_
    return $?
}

echo "::CHECK DB ${MYSQL_DATABASE} EXIST AND NO TABLE EXIST::"
# has no table?
# then drop database
# has user?
# then drop users
$_MYSQL_ROOT -se "USE \`${MYSQL_DATABASE}\`;" \
    && [[ \
        $( \
            $_MYSQL_ROOT -NB -se \
                'SELECT COUNT(*) FROM \
                    `information_schema`.`tables` \
                    WHERE `table_schema`='"'${MYSQL_DATABASE}'"';\
                ' \
        ) -lt 1 \
        ]] \
    && $_MYSQL_ROOT -se "DROP DATABASE IF EXISTS \`${MYSQL_DATABASE}\`;" \
    && [[ \
        $( \
            $_MYSQL_ROOT -se \
                "SELECT count( User ) FROM mysql.user \
                    WHERE User=\"${MYSQL_USER}\"; \
                " \
        ) -gt 1 \
        ]] \
    && $_MYSQL_ROOT -se \
        "\
            DROP USER \`${MYSQL_USER}\`@\`localhost\`; \
            DROP USER \`${MYSQL_USER}\`@\`%\`; \
        "

echo "::CREATE ${MYSQL_DATABASE} WHEN NOT EXISTS::"
$_MYSQL_ROOT -se "USE \`${MYSQL_DATABASE}\`;" \
    || do_create_database \
        || ( \
            echo "Cannot create database: ${MYSQL_DATABASE}"; \
            exit 1; \
        )

do_init_wordpress() {
    echo "::INITIALIZING WORDPRESS::"
    cd $_WORDPRESS_ROOT
    sudo -u nginx \
        wp core config \
            --locale=ja \
            --dbhost="${MYSQL_HOST}" \
            --dbname="${MYSQL_DATABASE}" \
            --dbuser="${MYSQL_USER}" \
            --dbpass="${MYSQL_WORDPRESS_PASSWORD}"
    sudo -u nginx \
        wp core install \
            --admin_name="${WORDPRESS_ADMIN-}" \
            --admin_password="${WORDPRESS_ADMIN_PASSWORD-}" \
            --admin_email="${WORDPRESS_ADMIN_EMAIL-}" \
            --skip-email \
            --url="http://${WORDPRESS_SITENAME}" \
            --title="${WORDPRESS_SITENAME}" \
        || ( \
            echo "Cannot init WordPress by wp-cli: $?"; \
            exit 255; \
        )
    sudo -u nginx \
        wp language core install ja \
    && sudo -u nginx \
        wp language core activate ja \
    && sudo -u nginx \
        wp plugin install wp-multibyte-patch \
    && sudo -u nginx \
        wp plugin activate wp-multibyte-patch
}

[[ -f "$_WORDPRESS_ROOT/wp-config.php" ]] \
    || do_init_wordpress

[[ -z "${WORDPRESS_NEVER_CHANGE_SITEURL-}" ]] \
    && sed -i \
        -e 's|^\(define([^\)]*WP_SITEURL\)|#\1|' \
        -e 's|^\(define([^\)]*WP_HOME\)|#\1|' \
        -e 's|\(define([^)]*DB_COLLATE[^)]*);\)|\1\ndefine( \x27WP_SITEURL\x27, \x27http://\x27 . (( $_SERVER[\x27HTTP_HOST\x27] ) ? $_SERVER[\x27HTTP_HOST\x27] : $_SERVER[\x27SERVER_NAME\x27] ) . \x27/\x27 );|' \
        -e 's|\(define([^)]*DB_COLLATE[^)]*);\)|\1\ndefine( \x27WP_HOME\x27, \x27http://\x27 . (( $_SERVER[\x27HTTP_HOST\x27] ) ? $_SERVER[\x27HTTP_HOST\x27] : $_SERVER[\x27SERVER_NAME\x27] ) . \x27/\x27 );|' \
            "$_WORDPRESS_ROOT/wp-config.php"

_EOF_docker_entrypoint

rc-update add local default
rc-update add php-fpm7 default

FN=/etc/local.d/kick-docker-entrypoint.start
cat > $FN <<'_EOF_'
#!/bin/bash
/var/docker/docker-entrypoint.sh
_EOF_
chmod +x $FN
