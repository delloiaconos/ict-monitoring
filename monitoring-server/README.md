# Monitoring server

The central ICT Monitoring stack collects metrics, evaluates alerts, and provides dashboards and management interfaces for Docker hosts and Proxmox environments. Nginx serves the web interfaces over HTTPS and forwards requests to the services over HTTP inside the Docker network.

[Project overview](../README.md) · [Monitored host guide](../monitoring-host/README.md)

## Contents

- [Services](#services)
- [Prerequisites](#prerequisites)
- [DNS and networking](#dns-and-networking)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Connect monitored hosts](#connect-monitored-hosts)
- [Operations](#operations)
- [Alerting](#alerting)
- [Proxmox monitoring](#proxmox-monitoring)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)

## Services

| Service | Purpose | Internal port | Public hostname pattern |
| --- | --- | ---: | --- |
| Homer | Landing page for the monitoring tools | 8080 | `https://homer.<BASE_DOMAIN>` and `https://<BASE_DOMAIN>` |
| Grafana | Dashboards and visualization | 3000 | `https://grafana.<BASE_DOMAIN>` |
| Prometheus | Metrics collection and alert rules | 9090 | `https://prometheus.<BASE_DOMAIN>` |
| Alertmanager | Alert routing and notifications | 9093 | `https://alertmanager.<BASE_DOMAIN>` |
| Portainer | Docker management UI | 9000 | `https://portainer.<BASE_DOMAIN>` |
| Pulse | Lightweight status/monitoring UI | 7655 | `https://pulse.<BASE_DOMAIN>` |
| cAdvisor | Container metrics for the monitoring server | 8080 | Not exposed directly |
| Node Exporter | Host metrics for the monitoring server | 9100 | Not exposed directly |
| PVE Exporter | Proxmox metrics exporter | 9221 | Not exposed directly |
| Nginx | Reverse proxy for public service hostnames | 443 | Public HTTPS entry point |

## Prerequisites

- Linux host with Docker installed
- Docker Compose, either as `docker-compose` or as the modern `docker compose` plugin
- `make`
- `rsync`
- `envsubst`, usually provided by the `gettext` or `gettext-base` package
- A user that can run Docker commands
- Optional: `sudo`, if `/opt/monitoring-server` requires elevated permissions
- OpenSSL, if generating self-signed certificates with `make certs`

## DNS and networking

The Nginx reverse proxy uses subdomains based on `BASE_DOMAIN`.

Create DNS records that point to the monitoring server, for example:

```text
monitoring.example.com
homer.monitoring.example.com
portainer.monitoring.example.com
grafana.monitoring.example.com
prometheus.monitoring.example.com
alertmanager.monitoring.example.com
pulse.monitoring.example.com
```

Then set:

```env
BASE_DOMAIN=monitoring.example.com
```

Nginx accepts HTTPS only on port `443` and terminates TLS. Port `80` is not published and there is no HTTP redirect. Traffic from Nginx to the services stays on HTTP within the Docker network.

## Quick start

1. Clone the repository.

   ```bash
   git clone <repository-url>
   cd ict-monitoring/monitoring-server
   ```

2. Create the environment file.

   ```bash
   cp .env.example .env
   ```

3. Edit `.env` and set your domain.

   ```env
   BASE_DOMAIN=monitoring.example.com
   ```

4. Install your TLS certificate and private key.

   Place the PEM certificate chain in `nginx/certs/fullchain.pem` and its matching private key in `nginx/certs/privkey.pem`. The certificate must cover `BASE_DOMAIN` and every service subdomain listed above (for example, `monitoring.example.com` and `*.monitoring.example.com`). These files are ignored by Git and copied into the runtime directory during deployment; keep the private key readable only by the deployment user and root. Nginx mounts them read-only and requires both files to start.

   Alternatively, generate a self-signed certificate **on the deployment server**, from the `monitoring-server/` working copy:

   ```bash
   make certs
   # If the deployment directory requires elevated permissions:
   make SUDO=sudo certs
   ```

   This requires OpenSSL and reads `BASE_DOMAIN` from `.env`. It uses `nginx/openssl.cnf` to generate a 3072-bit RSA key and a certificate covering the base domain and its wildcard subdomains, valid for 365 days. Override the validity with `CERT_DAYS=90`, the environment file with `ENV_FILE=...`, or the deployment directory with `DST_DIR=...`. Files are written directly to `/opt/monitoring-server/nginx/certs/`; the private key has mode `0600`. Both `make sync` and `make sync-prune` preserve destination-only PEM files. Generation refuses to overwrite either existing file; archive the existing pair before regenerating. Browsers and other clients must explicitly trust this self-signed certificate to avoid certificate warnings. `make deploy` does not generate certificates automatically.

   After renewing a supplied certificate, run `make sync`. For certificates generated with `make certs`, the files are already in the runtime directory. Reload Nginx after either renewal:

   ```bash
   docker exec monitoring-nginx nginx -t
   docker exec monitoring-nginx nginx -s reload
   ```

5. Deploy the stack.

   If your system has the legacy `docker-compose` command:

   ```bash
   make deploy
   ```

   If your system uses the modern Docker Compose plugin:

   ```bash
   make COMPOSE="docker compose" deploy
   ```

   If `/opt/monitoring-server` requires root permissions:

   ```bash
   make SUDO=sudo deploy
   ```

The Makefile deploys runtime files to `/opt/monitoring-server`, renders templates using `.env`, ensures a Compose project name, starts the stack, and prints container status.

Before deployment, configure the Proxmox exporter or disable it as described in [Proxmox monitoring](#proxmox-monitoring).

## Configuration

### Environment variables

`.env` is used by the Makefile to render template files.

| Variable | Description | Example |
| --- | --- | --- |
| `BASE_DOMAIN` | Base domain used for Nginx virtual hosts and Homer links | `monitoring.example.com` |

### Template rendering

Files ending in `.template` under these paths are rendered to `/opt/monitoring-server`:

- `homer/assets`
- `nginx/conf.d`

The Makefile uses `envsubst` to replace only `${BASE_DOMAIN}` by default, preserving Nginx variables such as `$host`, `$scheme`, and `$http_upgrade`.

To render using a different environment file:

```bash
make ENV_FILE=.env.example render
```

To restrict rendering to specific variables:

```bash
make VARS='$${BASE_DOMAIN}' render
```

### Homer

Edit [homer/assets/config.yml.template](homer/assets/config.yml.template) to change the dashboard. `make render` writes `homer/assets/config.yml` into the runtime directory, replacing `${BASE_DOMAIN}` in the HTTPS service links.

Compose mounts only that generated file, read-only, into `/www/assets/config.yml`. Homer’s bundled assets (including its favicon and application icons) remain available. `INIT_ASSETS=0` disables installation of the example configuration. Run `make render` before starting Homer; the template itself is not a configuration file that Homer can load.

The header and service cards use bundled Font Awesome icons, so they do not need downloaded service logos. If adding custom images later, mount them into a separate path under `/www/assets` and reference that path in the template; avoid replacing the entire bundled assets directory.

After changing the template, run `make render` and refresh the dashboard. When applying a Compose mount change, run `make sync` followed by `make COMPOSE="docker compose" up` to recreate the affected container.

### Grafana

Default credentials in `docker-compose.yml` are:

```text
Username: admin
Password: admin
```

Change these before exposing Grafana beyond a trusted network.

### Prometheus

Prometheus configuration lives in:

```text
prometheus/prometheus.yml
```

Alert rules live in:

```text
prometheus/rules/alerts.yml
```

The included rules cover:

- Down scrape targets
- High host CPU usage
- Low host filesystem free space

## Connect monitored hosts

Deploy the agents using the [monitored host guide](../monitoring-host/README.md), then add their reachable endpoints to the existing `scrape_configs` list in [prometheus/prometheus.yml](prometheus/prometheus.yml):

```yaml
  - job_name: docker-hosts-cadvisor
    static_configs:
      - targets:
          - "host-1.example.com:9902"
          - "host-2.example.com:9902"

  - job_name: docker-hosts-node-exporter
    static_configs:
      - targets:
          - "host-1.example.com:9903"
          - "host-2.example.com:9903"
```

From the server working copy, copy the configuration to the runtime directory and restart Prometheus to load it:

```bash
make sync
make COMPOSE="docker compose" restart SERVICE=prometheus
```

In Portainer, add each host as an Agent environment using `host-1.example.com:9901` as its address. The monitoring server must be able to reach the host's agent and metrics ports.

## Operations

Run the following from `monitoring-server/`.

| Command | Description |
| --- | --- |
| `make help` | Show Makefile targets |
| `make deploy` | Prepare, sync, render, ensure `.env`, start services, and show status |
| `make sync` | Copy runtime files to `/opt/monitoring-server` |
| `make sync-prune` | Sync runtime files and delete removed files from destination |
| `make certs` | Generate self-signed TLS certificate/key in the deployment directory (requires OpenSSL) |
| `make render` | Render `.template` files using environment variables |
| `make up` | Start the Compose stack |
| `make down` | Stop the Compose stack |
| `make restart` | Restart all services |
| `make restart SERVICE=prometheus` | Restart one service |
| `make status` | Show Compose service status |
| `make logs` | Follow logs for all services |
| `make logs SERVICE=grafana` | Follow logs for one service |

When using Docker Compose v2, add `COMPOSE="docker compose"` to the Make command, for example:

```bash
make COMPOSE="docker compose" status
```

## Alerting

Alertmanager configuration is stored in:

```text
alertmanager/alertmanager.yml
```

The default receiver is intentionally minimal. Configure one or more notification integrations before relying on alert delivery:

- Email
- Slack
- Webhook

After editing Alertmanager configuration, sync it to the runtime directory and restart Alertmanager:

```bash
make sync
make COMPOSE="docker compose" restart SERVICE=alertmanager
```

## Proxmox monitoring

The Compose stack includes `prometheus-pve-exporter`, mounted from:

```text
./pve/pve.yml:/etc/prometheus/pve.yml:ro
```

Create `pve/pve.yml` with your Proxmox exporter configuration before enabling this service. Also add a Prometheus scrape job if you want Prometheus to collect from it:

```yaml
scrape_configs:
  - job_name: pve-exporter
    static_configs:
      - targets: ["pve-exporter:9221"]
```

If you do not monitor Proxmox, remove or comment out the `pve-exporter` service from the Compose file.

## Security notes

- Replace the default Grafana `admin/admin` credentials.
- Use a trusted TLS certificate covering all public hostnames and renew it before expiry.
- Restrict access to Prometheus, Alertmanager, Portainer, and exporters with firewall rules, VPN, authentication, or a private network.
- Avoid exposing monitored host exporter ports directly to the internet.
- Pin container image versions for production deployments instead of using `latest`.
- Treat Portainer and the Docker socket as high-privilege access.
- Configure Alertmanager secrets through protected files or environment management, not public commits.

## Troubleshooting

### Nginx cannot load the TLS certificate

Verify that `nginx/certs/fullchain.pem` and `nginx/certs/privkey.pem` exist in `/opt/monitoring-server`, contain PEM data, and are readable by the container. The key must match the certificate. Run `docker exec monitoring-nginx nginx -t` to check the configuration when the container is running.

### `envsubst: command not found`

Install gettext utilities.

Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y gettext-base
```

RHEL/CentOS/Fedora:

```bash
sudo dnf install -y gettext
```

### `docker-compose: command not found`

Use Docker Compose v2 by passing the command to Make:

```bash
make COMPOSE="docker compose" deploy
```

### Nginx returns the wrong site or cannot resolve hostnames

Verify that:

- `BASE_DOMAIN` is correct in `.env`
- DNS records point to the monitoring server
- Templates were rendered into `/opt/monitoring-server/nginx/conf.d`
- The Nginx container was restarted after rendering

### Prometheus cannot scrape Node Exporter

The server stack runs Node Exporter with `network_mode: host`. If Prometheus cannot reach `node-exporter:9100`, adjust the target in `prometheus.yml` to a reachable host address or change the networking strategy.

### PVE Exporter fails to start

Create `pve/pve.yml` or remove the `pve-exporter` service if Proxmox monitoring is not needed.
