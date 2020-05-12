# docker build . -t janoschdufrene/sshuttle-pod:latest
# docker run --cap-add=NET_ADMIN --name test-sshuttle-pod -it janoschdufrene/sshuttle-pod:latest
FROM alpine:latest
VOLUME [ "/sys/fs/cgroup" ]
# install
RUN echo \
    && apk add --update --allow-untrusted --repository http://dl-4.alpinelinux.org/alpine/edge/testing/ \
    busybox-extras \
    curl \
    git \
    expect \
    openssh \
    openssh-client \
    openssh-server \
    openrc \
    netcat-openbsd \
    socat \
    sshpass \
    iptables \
    net-snmp-tools \
    nano \
    python \
    python-dev \
    py-pip \
    bash \
    build-base
#    rsyslog
# SSH
RUN mkdir /root/.ssh \
    && mkdir /var/run/sshd \
    && chmod 0700 /root/.ssh \
    && ssh-keygen -A \
    && echo 'root:root' | chpasswd \
    && sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && mkdir -p /run/openrc \
    && touch /run/openrc/softlevel \
    && rc-update add sshd
#    && rc-update add rsyslog \
# PyXAPI
RUN cd /root \
    && git clone https://github.com/metricube/PyXAPI.git \
    && cd PyXAPI/ \
    && ./configure \
    && make \
    && make install \
    && make clean
# sshuttle
RUN pip install --upgrade pip && pip install sshuttle
# caches cleanup
RUN apk del git python-dev build-base \
    && rm -rf /var/cache/apk/* \
    /tmp/* \
    /var/tmp/* \
    /root/PyXAPI


EXPOSE 22

COPY ./docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/bin/bash"]