#!/bin/bash
# iLO configuration and setup

print_msg () {
  echo
  echo -e "\e[1;32m"$1"\e[0m"
  echo
}

print_err () {
  echo -e "\e[1;31m"$1"\e[0m"
  echo
}

#####################################################################
print_msg "General configuration..."

# Initialize defaults
HOSTNAME=""
DOMAIN=""
CERT_DOMAIN=""
USERNAME=""
PASSWORD=""
STAGING=0
DNSAPI="dns_cf"
CONFIG_NAME="hpilo.cfg"
ACMESH_DIR="/root/.acme.sh"
SCRIPT_BASEDIR="$(pwd)"

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")

# Check for hpilo.cfg and set configuration
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  print_err "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi

# Make the file user-readable only as it contains passwords
chmod 600 "${SCRIPTPATH}"/"${CONFIG_NAME}"

. "${SCRIPTPATH}"/"${CONFIG_NAME}"

#####################################################################
print_msg "Input/Config Sanity checks..."

# CERT_DOMAIN overrides the domain used for the certificate (CSR, DNS
# validation and file naming) when the iLO's own domain differs — e.g. when
# it is supplied by DHCP and cannot be changed. Defaults to DOMAIN.
CERT_DOMAIN="${CERT_DOMAIN:-${DOMAIN}}"

# Check that necessary variables were set by hpilo.cfg
if [ -z "${HOSTNAME}" ]; then
  print_err 'Configuration error: HOSTNAME must be set'
  exit 1
fi
if [ -z "${DOMAIN}" ]; then
  print_err 'Configuration error: DOMAIN must be set'
  exit 1
fi
if [ -z "${USERNAME}" ]; then
  print_err 'Configuration error: USERNAME must be set'
  exit 1
fi
if [ -z "${PASSWORD}" ]; then
  print_err 'Configuration error: PASSWORD must be set'
  exit 1
fi

#####################################################################
print_msg "DNS resolver check..."

FQDN="${HOSTNAME}.${CERT_DOMAIN}"

# Check for DNS resolution
curl https://${FQDN}
CHK=$?
if [ ${CHK} -ne 60 ] && [ ${CHK} -ne 0 ]; then
  print_err "Problem resolving ${FQDN} to a private IP address. Remedy before continuing."
  exit 1
fi
#####################################################################
print_msg "Writing HPILO config file..."

CFG="${SCRIPT_BASEDIR}/${FQDN}.conf"

# Write config file and make it only root accessible
echo "[ilo]" > ${CFG}
echo "login = ${USERNAME}" >> ${CFG}
echo "password = ${PASSWORD}" >> ${CFG}

# Make the file user-readable only as it contains passwords
chmod 600 ${CFG}

#####################################################################
print_msg "Credentials validation..."

hpilo_cli -c ${CFG} ${FQDN} get_fw_version
if [ $? -ne 0 ]; then
  print_err "Invalid login credentials. Remedy before continuing."
  exit 1
fi

#####################################################################
print_msg "HOSTNAME and DOMAIN validation..."

shopt -s nocasematch

# Check for HOSTNAME mismatch
CHOSTNAME=$(hpilo_cli -c ${CFG} ${FQDN} get_network_settings | grep "dns_name" | cut -d "'" -f 4)
if [ ${CHOSTNAME} != ${HOSTNAME} ]; then
  print_err "HOSTNAME mismatch between ${CONFIG_NAME} (${HOSTNAME}) and iLO (${CHOSTNAME}). Remedy before continuing."
  exit 1
fi

# Check for DOMAIN mismatch
# The iLO's own domain may be DHCP-assigned and differ from the certificate
# domain; only enforce the match when no CERT_DOMAIN override is in play.
CDOMAIN=$(hpilo_cli -c ${CFG} ${FQDN} get_network_settings | grep "'domain_name'" | cut -d "'" -f 4)
if [ "${CERT_DOMAIN}" != "${DOMAIN}" ]; then
  print_msg "Skipping DOMAIN check: CERT_DOMAIN (${CERT_DOMAIN}) intentionally differs from iLO domain (${CDOMAIN})."
elif [ ${CDOMAIN} != ${DOMAIN} ]; then
  print_err "DOMAIN mismatch between ${CONFIG_NAME} (${DOMAIN}) and iLO (${CDOMAIN}). Remedy before continuing."
  exit 1
fi

shopt -u nocasematch

#####################################################################
print_msg "Generating CSR..."

CCSR=$(hpilo_cli -c ${CFG} ${FQDN} certificate_signing_request country= state= locality= organization= organizational_unit= common_name=${FQDN} | grep "BEGIN CERTIFICATE REQUEST")
echo "${CCSR}"
TIMER=30
while [ -z "${CCSR}" ]; do
  echo "Sleeping ${TIMER} seconds..."
  sleep ${TIMER}
  CCSR=$(hpilo_cli -c ${CFG} ${FQDN} certificate_signing_request country= state= locality= organization= organizational_unit= common_name=${FQDN} | grep "BEGIN CERTIFICATE REQUEST")
  echo "${CCSR}"
done

CSR="${SCRIPT_BASEDIR}/${FQDN}.csr"
hpilo_cli -c ${CFG} ${FQDN} certificate_signing_request country= state= locality= organization= organizational_unit= common_name=${FQDN} > ${CSR}

#####################################################################
print_msg "Creating the import script..."

SCRIPT="${SCRIPT_BASEDIR}/${FQDN}.sh"
echo 'CERTFILE="${ACMESH_DIR}/'${FQDN}'/'${FQDN}'.cer"' > ${SCRIPT}
echo 'hpilo_cli -c '${CFG}' '${FQDN}' import_certificate certificate="$(cat $CERTFILE)"' >> ${SCRIPT}
chmod +x ${SCRIPT}

#####################################################################
print_msg "Generating and importing the certificate..."
if [ ${STAGING} -eq 0 ]; then
  ${ACMESH_DIR}/acme.sh --signcsr --csr ${CSR} --dns ${DNSAPI} --reloadcmd ${SCRIPT} --force
else
  ${ACMESH_DIR}/acme.sh --signcsr --csr ${CSR} --dns ${DNSAPI} --days 1 --staging --reloadcmd ${SCRIPT} --force
fi
