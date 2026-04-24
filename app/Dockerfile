FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    gettext-base \
    lftp \
    openssh-client \
    openssl \
    procps \
    proftpd-core \
    proftpd-mod-crypto \
    socat \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ftps-storage-forward.sh /usr/local/bin/ftps-storage-forward.sh
COPY proftpd-ftps.conf.template /etc/proftpd/proftpd-ftps.conf.template

RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/ftps-storage-forward.sh

EXPOSE 990 1024 1025 1026 1027 1028 1029 1030 1031 1032 1033 1034

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]