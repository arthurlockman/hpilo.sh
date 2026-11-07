FROM alpine:3.20

ENV ACMESH_DIR=/acme.sh \
    SCRIPT_BASEDIR=/data \
    PS1="\$ "

# bash: hpilo.sh uses bashisms (shopt, readlink -f)
# curl: hpilo.sh uses it to verify DNS resolution of the iLO FQDN
# socat/openssl: acme.sh runtime deps
RUN apk add --no-cache \
      bash \
      curl \
      git \
      openssl \
      socat \
      tzdata \
      ca-certificates \
      python3 \
      py3-pip \
    && python3 -m venv /opt/venv \
    && ln -s /opt/venv/bin/hpilo_cli /usr/local/bin/hpilo_cli \
    && /opt/venv/bin/pip install --no-cache-dir python-hpilo \
    && git clone --depth 1 https://github.com/acmesh-official/acme.sh.git /opt/acme-sh-src \
    && rm -rf /opt/acme-sh-src/.git

COPY hpilo.sh /app/hpilo.sh
COPY docker-entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh /app/hpilo.sh

VOLUME ["/acme.sh", "/data"]

WORKDIR /data

ENTRYPOINT ["/app/entrypoint.sh"]
