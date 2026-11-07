FROM alpine:3.20

ENV ACMESH_DIR=/acme.sh \
    SCRIPT_BASEDIR=/data \
    PS1="\$ "

# bash: hpilo.sh uses bashisms (shopt, readlink -f)
# curl: hpilo.sh uses it to verify DNS resolution of the iLO FQDN
# socat/openssl: acme.sh runtime deps
# tailscale: optional userspace-networking access to ACL-governed iLOs
RUN apk add --no-cache \
      bash \
      curl \
      git \
      openssl \
      socat \
      tailscale \
      tzdata \
      ca-certificates \
      python3 \
      py3-pip \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir python-hpilo PySocks \
    && git clone --depth 1 https://github.com/acmesh-official/acme.sh.git /opt/acme-sh-src \
    && rm -rf /opt/acme-sh-src/.git

COPY hpilo.sh /app/hpilo.sh
COPY hpilo_cli_shim /usr/local/bin/hpilo_cli
COPY docker-entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh /app/hpilo.sh /usr/local/bin/hpilo_cli

VOLUME ["/acme.sh", "/data"]

WORKDIR /data

ENTRYPOINT ["/app/entrypoint.sh"]
