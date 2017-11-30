#!/bin/bash

EVALS=$(cat <<'_EOF_'
WORDPRESS_CONTAINER=${WORDPRESS_CONTAINER:-wordpress}
WORDPRESS_PHPFPM_PORT=${WORDPRESS_PHPFPM_PORT:-9000}
NGINX_DOCROOT=${NGINX_DOCROOT:-/var/www-nginx/wordpress}
NGINX_SERVER_NAME=${NGINX_SERVER_NAME:-localhost}
_EOF_
)
eval "$EVALS"

addgroup \
    -g ${GID_NGINX-} \
    nginx
adduser \
    -u ${UID_NGINX-} \
    -G nginx \
    -s ${_NO_LOGIN_SHELL-} \
    -D -H \
    nginx \
    || :

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

apk add \
    logrotate
apk add \
    tar curl sudo bash-completion less \
    wget \
    telnet

# nginx
apk add nginx

_PREP=/var/docker/_prep
[[ $_PREP/nginx.conf ]] \
    && mv /etc/nginx/nginx.conf{,.orig} \
    && cp $_PREP/nginx.conf /etc/nginx/nginx.conf
[[ $_PREP/conf.d__default.conf ]] \
    && [[ -d /etc/nginx/conf.d ]] \
    && mv /etc/nginx/conf.d/default.conf{,.orig} \
    && cp $_PREP/conf.d__default.conf.tmpl /etc/nginx/conf.d/default.conf.tmpl

FUNC_EVAL=$(cat <<'_EOF_'
declare -A VALUES
VALUES[WORDPRESS_CONTAINER]=${WORDPRESS_CONTAINER-}
VALUES[WORDPRESS_PHPFPM_PORT]=${WORDPRESS_PHPFPM_PORT-}
VALUES[NGINX_DOCROOT]=${NGINX_DOCROOT-}
VALUES[NGINX_SERVER_NAME]=${NGINX_SERVER_NAME-}
function explode_nginx_conf {
    local FROM_FILE=$1
    local DEST_FILE=$2
    cp $FROM_FILE $DEST_FILE
    local key=''
    for key in ${!VALUES[*]}
    do
        sed -i \
            -e "s|%%${key}%%|${VALUES[$key]}|" \
            ${DEST_FILE}
    done
}
explode_nginx_conf \
    /etc/nginx/conf.d/default.conf.tmpl \
    /etc/nginx/conf.d/default.conf
_EOF_
)
eval "$FUNC_EVAL"

rc-update add local default
rc-update add nginx default

# WordPressの wp-config/HOST を ENV{HTTP_HOST}, HTTP_PORT にする
#    define('WP_HOME','http://example.com');
#    define('WP_SITEURL','http://example.com');

DOCKER_ENTRYPOINT=/var/docker/docker-entrypoint.sh
cat > $DOCKER_ENTRYPOINT <<_EOF_
#!/bin/bash
exec > /var/docker/_prep/log/container.log 2>&1

$EVALS
$FUNC_EVAL
_EOF_
chmod +x $DOCKER_ENTRYPOINT

cat >> $DOCKER_ENTRYPOINT <<'_EOF_'
_TARGET="${WORDPRESS_CONTAINER} ${WORDPRESS_PHPFPM_PORT}"
until \
    (echo -e "\x1d"; sleep 1; echo quit) \
    | telnet $_TARGET
do
    echo \
        '['$(date -D 'YYYY-MM-DD hh:mm:ss')']' \
        'Waiting for getting WordPress up'
    sleep 10
done

echo \
    '['$(date -D 'YYYY-MM-DD hh:mm:ss')']' \
    'WordPress is up!'

rc-service nginx restart
_EOF_

FN=/etc/local.d/kick-docker-entrypoint.start
cat > $FN <<_EOF_
#!/bin/bash
$DOCKER_ENTRYPOINT
_EOF_
chmod +x $FN
