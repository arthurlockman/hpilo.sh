#!/bin/bash
# Entrypoint: builds hpilo.cfg from ILO_* environment variables, runs the
# initial issuance via hpilo.sh, then stays up so acme.sh's cron can renew.
set -euo pipefail

ACMESH_DIR="${ACMESH_DIR:-/acme.sh}"
SCRIPT_BASEDIR="${SCRIPT_BASEDIR:-/data}"
CRON_SCHEDULE="${CRON_SCHEDULE:-17 0 * * *}"
APP=/app

print_err() { echo -e "\e[1;31m$1\e[0m" >&2; }

for var in ILO_USERNAME ILO_PASSWORD ILO_HOSTNAME ILO_DOMAIN; do
  if [ -z "${!var:-}" ]; then
    print_err "Configuration error: ${var} must be set"
    exit 1
  fi
done

# Bootstrap acme.sh into the persistent volume if this is a fresh one.
if [ ! -x "${ACMESH_DIR}/acme.sh" ]; then
  mkdir -p "${ACMESH_DIR}"
  cp -a /opt/acme-sh-src/. "${ACMESH_DIR}/"
fi

STAGING="${ILO_STAGING:-0}"
case "${STAGING}" in 0|1) ;; *) print_err "ILO_STAGING must be 0 or 1"; exit 1;; esac

cat > "${APP}/hpilo.cfg" <<EOF
USERNAME="${ILO_USERNAME}"
PASSWORD="${ILO_PASSWORD}"
HOSTNAME="${ILO_HOSTNAME}"
DOMAIN="${ILO_DOMAIN}"
STAGING=${STAGING}
DNSAPI="${ILO_DNSAPI:-dns_cf}"
ACMESH_DIR="${ACMESH_DIR}"
SCRIPT_BASEDIR="${SCRIPT_BASEDIR}"
EOF
chmod 600 "${APP}/hpilo.cfg"

mkdir -p "${SCRIPT_BASEDIR}"

FQDN="${ILO_HOSTNAME}.${ILO_DOMAIN}"
if [ -s "${ACMESH_DIR}/${FQDN}/${FQDN}.cer" ] \
   && openssl x509 -in "${ACMESH_DIR}/${FQDN}/${FQDN}.cer" -noout -checkend "$((45 * 86400))" 2>/dev/null; then
  echo "Valid certificate for ${FQDN} already present (renews via acme.sh); skipping initial issuance."
else
  echo "Running initial issuance for ${FQDN}..."
  bash "${APP}/hpilo.sh"
fi
if [ "${ILO_RUN_ONCE:-0}" = "1" ]; then
  echo "ILO_RUN_ONCE=1 set; exiting after issuance."
  exit 0
fi

# Keep the container alive and let acme.sh renew + redeploy on schedule.
# ACMESH_DIR is exported because the generated deploy script references it.
echo "${CRON_SCHEDULE} export ACMESH_DIR='${ACMESH_DIR}'; '${ACMESH_DIR}/acme.sh' --cron --home '${ACMESH_DIR}' >/dev/null 2>&1" \
  > /etc/crontabs/root
echo "Initial issuance complete; renewal cron '${CRON_SCHEDULE}' is running."
exec crond -f -l 8
