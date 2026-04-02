FROM alpine:3.20

# ── Install packages ────────────────────────────────────────────────
RUN apk add --no-cache \
      vsftpd \
      openssl \
      openssh-client \
      certbot \
      inotify-tools \
      tini \
      bash \
      dcron \
      shadow \
      netcat-openbsd     # used by healthcheck in DEV_MODE

# ── Create FTP user (nologin shell, chrooted later by vsftpd) ──────
RUN addgroup -S ftpusers && \
    adduser -S -G ftpusers -h /home/ftpuser -s /sbin/nologin ftpuser && \
    mkdir -p /home/ftpuser/ftp/uploads && \
    chown ftpuser:ftpusers /home/ftpuser/ftp/uploads && \
    chmod 755 /home/ftpuser/ftp && \
    chmod 775 /home/ftpuser/ftp/uploads

# ── Certificate directory (separate keypair – NOT the host SSH key) ─
RUN mkdir -p /etc/vsftpd/certs && \
    chmod 700 /etc/vsftpd/certs

# ── SFTP forwarder directories ─────────────────────────────────────
RUN mkdir -p /var/lib/sftp-forward/pending \
             /var/lib/sftp-forward/forwarded \
             /var/lib/sftp-forward/failed \
             /var/lib/sftp-forward/ssh \
             /var/log/sftp-forward

# ── Logging ─────────────────────────────────────────────────────────
RUN mkdir -p /var/log/vsftpd

# ── Copy configuration files ───────────────────────────────────────
COPY vsftpd.conf         /etc/vsftpd/vsftpd.conf
COPY entrypoint.sh       /entrypoint.sh
COPY sftp-forwarder.sh   /usr/local/bin/sftp-forwarder.sh
COPY cleanup-cron        /etc/crontabs/root

RUN chmod +x /entrypoint.sh /usr/local/bin/sftp-forwarder.sh

# ── Ports ───────────────────────────────────────────────────────────
EXPOSE 990 10242-11034

# ── Volumes ─────────────────────────────────────────────────────────
VOLUME ["/home/ftpuser/ftp/uploads", \
        "/etc/vsftpd/certs", \
        "/etc/letsencrypt", \
        "/var/lib/sftp-forward", \
        "/var/log/sftp-forward"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]