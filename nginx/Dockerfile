FROM alpine:3.6

ARG GID_NGINX
ENV GID_NGINX ${GID_NGINX:-101}
ARG UID_NGINX
ENV UID_NGINX ${UID_NGINX:-101}

RUN \
    apk update \
    && apk add openrc bash sed
RUN \
    mkdir -p /var/docker /var/docker/run \
    && touch /var/docker/docker-entrypoint.sh \
    && chmod +x /var/docker/docker-entrypoint.sh
COPY _prep /var/docker/_prep
RUN \
    chmod a+x /var/docker/_prep/*.sh \
    && mkdir -p /var/docker/_prep/log
RUN \
    touch /var/docker/_prep/log/build.log \
    && bash -c '( \
        source /var/docker/_prep/build.sh \
    ) ' 2>&1 \
        | tee -a /var/docker/_prep/log/build.log

WORKDIR /etc/init.d
ENTRYPOINT [ "/sbin/init" ]
