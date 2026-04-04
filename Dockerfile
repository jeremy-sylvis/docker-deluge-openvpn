# Can't use ubuntu:24.04 until deluge is updated to not use deprecated python bits like disttools
# and "setup.py" direct invocation
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND="noninteractive"
ARG S6_OVERLAY_VERSION=3.2.0.2

RUN set -ex; \
    apt-get update && \
    apt-get -y install software-properties-common && \
    echo "Set up general prerequisites" && \
    apt -y install git intltool closure-compiler python3-pip dumb-init iputils-ping dnsutils bash jq net-tools openvpn curl ufw p7zip-full unrar unzip wget python3-venv && \
    echo "Download, build, and install natpmpc from source" && \
    mkdir /tmp/libnatpmp && cd /tmp/libnatpmp && \
    git clone https://github.com/jeremy-sylvis/libnatpmp.git && cd libnatpmp && \
    make all && make install && cd / && rm -rf /tmp/libnatpmp && \
    echo "Set up Deluge prerequisites" && \
    mkdir -p /app/deluge-venv && python3 -m venv /app/deluge-venv && . /app/deluge-venv/bin/activate && \
    apt -y install gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1 libnotify4 librsvg2-common xdg-utils && \
    DELUGE_VERSION=2.2.0 && \
    echo "Download and install Deluge ${DELUGE_VERSION} from source" && \
    # Actually grab Deluge
    mkdir /tmp/deluge && cd /tmp/deluge && wget http://download.deluge-torrent.org/source/2.2/deluge-${DELUGE_VERSION}.tar.xz && \
        tar -xf deluge-${DELUGE_VERSION}.tar.xz && cd deluge-${DELUGE_VERSION} && cat RELEASE-VERSION && \
    # Build & install
    pip3 install deluge[all]==${DELUGE_VERSION} && \
    python3 setup.py build && python3 setup.py install --install-layout=deb && cp /tmp/deluge/deluge-2.2.0/packaging/systemd/deluge*.service /etc/systemd/system/ && \
    echo "Cleanup Deluge ${DELUGE_VERSION} source" && \
    # Cleanup Deluge itself
    cd / && rm -rf /tmp/deluge/deluge-${DELUGE_VERSION} && \
    echo "Cleanup image temp and apt lists" && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/* && \
    echo "Adding user" && \
    useradd -u 911 -U -d /config -s /bin/false abc && \
    usermod -G 1000 abc && \
    usermod -G users abc

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp/
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp/
# tar needs the archive path to follow -f; another flag cannot follow -f e.g. -Jxpfv
RUN tar -C / -Jxpvf /tmp/s6-overlay-noarch.tar.xz; tar -C / -Jxpvf /tmp/s6-overlay-x86_64.tar.xz; rm -rf /tmp/*

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
    DELUGE_OUTGOING_PORT_HIGH=63404 \
    SSL_CERT_DIR=/etc/ssl/certs

HEALTHCHECK --interval=1m CMD /etc/scripts/healthcheck.sh

# Deluge Deamon and web 
EXPOSE 8112 58846

# Set the s6 overlay init
ENTRYPOINT ["/init"]
# Start up the container
CMD ["/etc/orchestration/start.sh"]