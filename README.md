# Let's Encrypt HPE iLO 
## History
This script is pased on the work of Basil Hendroff at https://github.com/basilhendroff/truenas-iocage-letsencrypt/, but adapted for more general use.  Basil's work created a jail on FreeNAS/TrueNAS CORE, and installed various software in it, including this script and its dependencies.  As a result, his version of this script expected certain files to be in certain locations, and hard-coded those paths into the script.

I no longer use TrueNAS CORE, but I do have two HPE servers with iLO on which I wanted to use Let's Encrypt certs, and I had another Linux VM that was already deploying certs to some other devices on my network.  That required changing some hardcoded paths in the script, and led to a few other changes as well.
## Changes
I've made these changes compared to Basil's version of `hpilo.sh`:
* Remove root privileges check
* Add configurable path for cert
* Add configurable path for acme.sh
* Change mode of created files (except the deployment script) to 600 rather than 700--they don't need to be executable.
* Make hostname/domain checking case-insensitive

## Prerequisites
* This script depends on both [python-hpilo](https://seveas.github.io/python-hpilo/index.html) and [acme.sh](https://github.com/acmesh-official/acme.sh).  Make sure these are installed and available in whatever environment you're using to run this script.
* This script will obtain a certificate from a trusted certificate authority, which means you must use a public domain name you control.
* This script uses DNS validation to obtain the script, so you must be using a [supported DNS provider](https://github.com/acmesh-official/acme.sh/wiki/dnsapi).  Fortunately, acme.sh supports over 150 DNS providers.

## Preparation
Before undertaking a deployment:
1. Ensure the iLO is updated with the latest firmware (iLO UI > Administration > Firmware) and the iLO hostname and domain fields (iLO UI > Network > iLO Dedicated Network Port > General) are configured.
2. Configure your local DNS resolver to resolve the FQDN of the iLO to its IP address. For example, `ilo.mydomain.com` must resolve to the iLO IP on the internal network.

## Deployment
1. Edit the file called `hpilo.cfg` with your favorite text editor. In its minimal form, it would look something like this:
```
USERNAME="Administrator"
PASSWORD="alakazam"
HOSTNAME="ilo"
DOMAIN="mydomain.com"
```
The mandatory options are:
- USERNAME: Username of the iLO administrator.
- PASSWORD: The iLO administrator password.
- HOSTNAME: The iLO hostname.
- DOMAIN:   Your registered domain name.

Other options with defaults include:
- STAGING:  While finding your way around this resource, you're encouraged to set STAGING to 1 to avoid hitting Let's Encrypt rate limits. The default is 0.
- DNSAPI:   A supported DNS provider for automatic DNS API integration https://github.com/acmesh-official/acme.sh/wiki/dnsapi. The default is Cloudflare (`dns_cf`). To use a different provider, for instance, Amazon Route53, set `DNSAPI="dns_aws"` in `hpilo.cfg`.
- ACMESH_DIR:  This is the directory in which the `acme.sh` script lives.  Default is `/root/.acme.sh`.
- SCRIPT_BASEDIR:  This is where the script will place the host-specific CSR, config, and script files.  Defaults to your current working directory when you run the script.

3. If this is your first deployment, set up the API credentials for your DNS provider https://github.com/acmesh-official/acme.sh/wiki/dnsapi, but do not issue a certificate just yet! For example, for Cloudflare:
```
export CF_Token="sdfsdfsdfljlbjkljlkjsdfoiwje"
export CF_Account_ID="xxxxxxxxxxxxx"   # optional; see acme.sh dns_cf docs

Only `CF_Token` is required for a zone-scoped token; `CF_Account_ID` optionally narrows the zone lookup for broad tokens.
When a certificate is first issued, the credentials you set are saved in `$ACMESH_DIR/account.conf` and used for subsequent deployments.

4. Run the helper script `bash hpilo.sh` to issue and deploy a Let's Encrypt certificate to the iLO. 
5. Repeat the above steps for other iLOs on your network.

To list all issued certificates `acme.sh --list`. Acme.sh will manage the renewal and deployment of the certificates.

A Docker image is provided for running the script without installing anything locally. On start the container issues the certificate if one is not already present, then keeps running a daily `acme.sh --cron` job so certificates renew (acme.sh decides when based on each certificate's actual expiry, default 60 days before it) and redeploys automatically.

```bash
docker build -t hpilo-le .
docker compose up -d   # after editing docker-compose.yml
```

All configuration is passed via environment variables:

| Environment variable | Maps to        | Notes                                                        |
| -------------------- | -------------- | ------------------------------------------------------------ |
| `ILO_USERNAME`       | `USERNAME`     | Required. iLO administrator username.                        |
| `ILO_PASSWORD`       | `PASSWORD`     | Required. iLO administrator password.                        |
| `ILO_HOSTNAME`       | `HOSTNAME`     | Required. iLO hostname.                                      |
| `ILO_DOMAIN`         | `DOMAIN`       | Required. Registered domain name.                            |
| `ILO_STAGING`        | `STAGING`      | `0` (default) or `1` for Let's Encrypt staging.              |
| `ILO_DNSAPI`         | `DNSAPI`       | acme.sh DNS provider, default `dns_cf` (Cloudflare).         |
| `ILO_ACME_CA`       | `ACME_CA`      | Certificate authority for acme.sh, default `letsencrypt`.    |
| `CF_Token`           | *(passthrough)*| DNS provider credentials, consumed directly by `acme.sh`.    |
| `TS_AUTHKEY`         | —              | Optional. Tailscale auth key; connects the container to your tailnet (see below). |
| `TS_HOSTNAME`        | —              | Tailscale node name, default `hpilo-cert`.        |

DNS provider credentials (e.g. `CF_Token`, `CF_Account_ID` for Cloudflare) are passed straight through to `acme.sh` and saved in `$ACMESH_DIR/account.conf` on first issuance, so renewals keep working after a restart. Persist `./acme` (acme.sh home) and `./data` (CSRs, per-host configs, deploy scripts) as shown in `docker-compose.yml`.

For a one-shot run instead of a long-lived renewal container:

```bash
docker compose run --rm -e ILO_RUN_ONCE=1 hpilo
```

### Tailscale

If your iLOs are only reachable over your tailnet (e.g. behind Tailscale ACLs), set `TS_AUTHKEY` to a reusable auth key from the Tailscale admin console. The container runs `tailscaled` in userspace-networking mode (no TUN device needed, works in Apple's container runtime) and routes all iLO traffic through it:

* `hpilo_cli` connections are proxied through the local Tailscale SOCKS5 endpoint (`127.0.0.1:1055`), so tailnet ACLs apply to the container's node identity.
* Create the key with a tag such as `tag:hpilo-certs` and grant that tag access to the iLO nodes in your ACL policy.
* Persist `./tailscale:/var/lib/tailscale` (as in `docker-compose.yml`) so the node keeps its identity and ACL grants across restarts.
* The auth key is only used on first login (or after wiping `./tailscale`). Tagged nodes have no node key expiry, so restarts never re-authenticate and an expired auth key can't block a healthy container.
* Name resolution for the iLO FQDN happens through Tailscale's DNS, so add a split-DNS entry or hosts override in the Tailscale admin console pointing your iLO FQDN at the iLO's tailnet IP.
* Do not attach an exit node to this container's node — all HTTP traffic (including Cloudflare API calls) flows through the tailscale SOCKS proxy when enabled.

Multi-architecture images (`linux/amd64` and `linux/arm64`) are built and published to this repository's container registry (`ghcr.io/<owner>/<repo>`) by GitHub Actions on every push to `main`.

## How It Works
`hpilo.sh` ordinarily only needs to be run once per iLO host.  When you run it, it will generate a host-specific config file (`$FQDN.conf`), connect to the host so that it can generate a certificate signing request (`$FQDN.csr`), generate a host-specific deployment script (`$FQDN.sh`), and then have `acme.sh` obtain a certificate based on that CSR, using the generated script to deploy the cert to the iLO host.  Once that's done, `acme.sh` will handle renewing the cert, and deploying the renewed cert, on its own with no further need of `hpilo.sh`.
