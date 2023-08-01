FROM ubuntu:22.04

ARG DEBIAN_FRONTEND="noninteractive"

RUN set -ex; \
    apt-get update && \
    apt-get -y install software-properties-common && \
    echo "Set up prerequisites to build Deluge from source"; \
    apt -y install git intltool closure-compiler python3-pip dumb-init iputils-ping dnsutils bash jq net-tools openvpn curl ufw p7zip-full unrar unzip && \
    pip3 install --user tox && \
    apt -y install python3-libtorrent python3-geoip python3-dbus python3-gi \
        python3-gi-cairo gir1.2-gtk-3.0 gir1.2-appindicator3-0.1 python3-pygame libnotify4 \
        librsvg2-common xdg-utils; \
    echo "Download Deluge 2.1.1 source" && \
        wget http://download.deluge-torrent.org/source/2.1/deluge-2.1.1.tar.xz && tar -xf deluge-2.1.1.tar.xz; \
    echo "Install Deluge 2.1.1 from source" && \
    cd deluge-2.1.1 && cat RELEASE-VERSION && \
        python3 setup.py clean -a && python3 setup.py build && python3 setup.py install --install-layout=deb && \
        cd packaging/systemd && cp deluge*.service /etc/systemd/system/ && cd ../../../; \
    echo "Cleanup" && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*; \
    echo "Adding user" && \
    groupmod -g 1000 users && \
        useradd -u 911 -U -d /config -s /bin/false abc && \
        usermod -G users abc

# Add configuration and scripts
COPY root/ /

ENV OPENVPN_USERNAME=**None** \
    OPENVPN_PASSWORD=**None** \
    OPENVPN_PROVIDER=**None** \
    GLOBAL_APPLY_PERMISSIONS=true \
    TZ=Europe/Berlin \
    DELUGE_WEB_PORT=8112 \
    DELUGE_DEAMON_PORT=58846 \
    DELUGE_DOWNLOAD_DIR=/download/completed \
    DELUGE_INCOMPLETE_DIR=/download/incomplete \
    DELUGE_TORRENT_DIR=/download/torrents \
    DELUGE_WATCH_DIR=/download/watch \
    CREATE_TUN_DEVICE=true \
    ENABLE_UFW=false \
    UFW_ALLOW_GW_NET=false \
    UFW_EXTRA_PORTS= \
    UFW_DISABLE_IPTABLES_REJECT=false \
    PUID= \
    PGID= \
    UMASK=022 \
    PEER_DNS=true \
    PEER_DNS_PIN_ROUTES=true \
    DROP_DEFAULT_ROUTE= \
    HEALTH_CHECK_HOST=google.com \
    LOG_TO_STDOUT=false \
    DELUGE_LISTEN_PORT_LOW=53394 \
    DELUGE_LISTEN_PORT_HIGH=53404 \
    DELUGE_OUTGOING_PORT_LOW=63394 \
    DELUGE_OUTGOING_PORT_HIGH=63404

HEALTHCHECK --interval=1m CMD /etc/scripts/healthcheck.sh

# Deluge Deamon and web
EXPOSE 8112 58846

CMD ["dumb-init", "/etc/openvpn/init.sh"]