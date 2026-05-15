FROM mcr.microsoft.com/mirror/docker/library/ubuntu:22.04

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

# Re-enable ssh-rsa host key type for SFTP targets that present legacy RSA keys.
# Ubuntu 22.04's OpenSSH 8.9 disables ssh-rsa (SHA-1) by default; some older
# SFTP servers only offer this key type.  lftp's native SFTP uses the system
# ssh binary which reads this config.
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh \
    && printf 'Host *\n    HostKeyAlgorithms +ssh-rsa\n    PubkeyAcceptedKeyTypes +ssh-rsa\n' \
       > /root/.ssh/config \
    && chmod 600 /root/.ssh/config

EXPOSE 990 1024 1025 1026 1027 1028 1029 1030 1031 1032 1033 1034

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]