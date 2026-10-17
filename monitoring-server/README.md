# Monitoring server

The central ICT Monitoring stack includes metrics collection, alert evaluation, and web interfaces for Docker and Proxmox environments. Datasources, dashboards, notification receivers, and Proxmox access require additional configuration. Nginx serves the web interfaces over HTTPS and forwards requests to the services over HTTP inside the Docker network.

[Project overview](../README.md) · [Monitored host guide](../monitoring-host/README.md)

## Contents

- [Services](#services)
- [Current setup requirements](#current-setup-requirements)
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

| Service | Purpose | Service port | Access |
| --- | --- | ---: | --- |
| Homer | Landing page for the monitoring tools | 8080 | `https://homer.<BASE_DOMAIN>` and `https://<BASE_DOMAIN>` |
| Grafana | Dashboards and visualization | 3000 | `https://grafana.<BASE_DOMAIN>` |
| Prometheus | Metrics collection and alert rules | 9090 | `https://prometheus.<BASE_DOMAIN>` |
| Alertmanager | Alert routing and notifications | 9093 | `https://alertmanager.<BASE_DOMAIN>` |
| Portainer | Docker management UI | 9000 | `https://portainer.<BASE_DOMAIN>` |
| Pulse | Lightweight status/monitoring UI | 7655 | `https://pulse.<BASE_DOMAIN>` |
| cAdvisor | Container metrics for the monitoring server | 8080 | Not exposed directly |
| Node Exporter | Host metrics for the monitoring server | 9100 | Direct host listener; outside nginx |
| PVE Exporter | Proxmox metrics exporter | 9221 | Not exposed directly |
| Nginx | Reverse proxy for public service hostnames | 443 | Public HTTPS entry point |

## Current setup requirements

The server can run independently of `monitoring-host`, but a fresh checkout requires `make prepare` and the following configuration:

- Correct the local Node Exporter scrape address: its host networking does not provide the Docker service DNS name currently used by Prometheus. See [Node Exporter troubleshooting](#prometheus-cannot-scrape-node-exporter).
- Configure or remove the Proxmox exporter. It is enabled unconditionally, but its credential file and scrape job are not supplied.
- Configure Grafana's Prometheus datasource and dashboards, and an Alertmanager receiver if notifications are needed.
- Add remote hosts explicitly; the stack does not discover or register them automatically.

Preparation checks required runtime files. It does not establish that all services are healthy or that these integrations are configured.

## Prerequisites

- Linux host with Docker installed
- Docker Compose, either as `docker-compose` or as the modern `docker compose` plugin
- GNU Make and Bash
- `rsync`
- `envsubst`, usually provided by the `gettext` or `gettext-base` package
- A user that can run Docker commands, and a local `docker` group (used by `make prepare-dir`)
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

Nginx accepts HTTPS only on port `443` and terminates TLS. Port `80` is not published and there is no HTTP redirect. Traffic from Nginx to the services stays on HTTP within the Docker network. This HTTPS policy applies to nginx: Node Exporter uses host networking and listens separately on port `9100`. Restrict access to that port through host networking/firewall configuration.

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

5. Configure the Proxmox exporter or remove its service from Compose as described in [Proxmox monitoring](#proxmox-monitoring). If enabled, create `pve/pve.yml`; preparation copies this directory into the runtime deployment.

6. **Prepare the deployment before running Compose.** From the working copy:

   ```bash
   make prepare
   # If the deployment directory requires elevated permissions:
   make SUDO=sudo prepare
   ```

   This creates `/opt/monitoring-server`, copies runtime files, renders Homer and nginx configuration, installs `.env` with mode `0600`, and checks that all rendered files and both TLS files exist and are nonempty. It requires `BASE_DOMAIN` in the source `.env` and does not generate certificates or start containers. The checks cover `docker-compose.yml`, `.env`, the rendered Homer and nginx files, and both TLS files. They do not validate contents, certificate expiry or key matching, the presence of `pve/pve.yml`, service health, or metrics connectivity.

7. Start the prepared deployment:

   ```bash
   cd /opt/monitoring-server
   docker compose up -d
   ```

   Alternatively, from the working copy:

   ```bash
   make COMPOSE="docker compose" up
   ```

   Use `docker-compose` on legacy installations, or omit the `COMPOSE` override for Make targets.

**A fresh checkout cannot be started directly with `docker compose up -d`.** Compose does not render templates or create certificates. Always run `make prepare` first, and run Compose from the prepared runtime directory. Use the same `DST_DIR` override for `certs`, `prepare`, and `up` when choosing another deployment location; keep it separate from the working copy.

For subsequent deployments, `make COMPOSE="docker compose" deploy` runs preparation before starting the stack and showing status. Add `SUDO=sudo` when required. Preparation replaces the runtime `.env` from `ENV_FILE` (default `.env` in the working copy), so edit the source environment rather than the deployed copy. Application configuration changes may still require a service reload or restart. `make up` runs only the file checks before Compose; direct `docker compose up -d` bypasses those checks. Neither command performs preparation.

## Configuration

### Environment variables

`.env` supplies template rendering and is installed into the runtime directory for Compose interpolation by `make prepare`. `BASE_DOMAIN` must be nonempty for preparation and rendering. Keep `ENV_FILE` compatible with both Bash assignments and Compose environment-file syntax; the Makefile sources it as shell code and copies its contents to the runtime `.env`, then appends `COMPOSE_PROJECT_NAME=monitoring-server`.

| Variable | Description | Example |
| --- | --- | --- |
| `BASE_DOMAIN` | Domain used for nginx/Homer rendering and Grafana/Pulse public URLs | `monitoring.example.com` |

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

Compose mounts only that generated file, read-only, into `/www/assets/config.yml`. Homer’s bundled assets (including its favicon and application icons) remain available. `INIT_ASSETS=0` disables installation of the example configuration. Initial preparation renders this file before starting Homer; the template itself is not a configuration file that Homer can load.

The header and service cards use bundled Font Awesome icons, so they do not need downloaded service logos. If adding custom images later, mount them into a separate path under `/www/assets` and reference that path in the template; avoid replacing the entire bundled assets directory.

After changing the template, run `make render` and refresh the dashboard. When applying a Compose mount change, run `make sync` followed by `make COMPOSE="docker compose" up` to recreate the affected container.

### Grafana

Default credentials in `docker-compose.yml` are:

```text
Username: admin
Password: admin
```

These environment values initialize a new Grafana installation; changing them does not reset an existing administrator password in the persistent volume. Change the default credentials before exposing Grafana beyond a trusted network.

No datasource or dashboards are provisioned by this repository. Configure a Prometheus datasource with the internal URL `http://prometheus:9090`, then create or import dashboards.

### Prometheus

Prometheus configuration lives in:

```text
prometheus/prometheus.yml
```

Alert rules live in:

```text
prometheus/rules/alerts.yml
```

The configured scrape jobs target Prometheus, Alertmanager, cAdvisor, and Node Exporter. The Node Exporter address needs correction as described in [troubleshooting](#prometheus-cannot-scrape-node-exporter). No remote-host or Proxmox jobs are enabled in this file.

The included rules cover:

- Down scrape targets
- High host CPU usage
- Low host filesystem free space

CPU and filesystem rules require successfully scraped Node Exporter metrics. Notifications also require an Alertmanager receiver.

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
| `make prepare` | Required preparation: copy runtime files, render templates, install `.env`, and check required files |
| `make check-prepared` | Check required runtime files without starting services |
| `make deploy` | Run preparation, start services, and show status |
| `make sync` | Copy allowed runtime files; does not render templates or install `.env` |
| `make sync-prune` | Sync and prune included paths; preserve destination PEM files under `nginx/certs` |
| `make certs` | Generate self-signed TLS certificate/key in the deployment directory (requires OpenSSL) |
| `make render` | Render `.template` files using environment variables |
| `make up` | Check required runtime files, then run Compose `up -d` |
| `make down` | Stop the Compose stack |
| `make restart` | Restart all services |
| `make restart SERVICE=prometheus` | Restart one service |
| `make status` | Show Compose service status |
| `make logs` | Follow logs for all services |
| `make logs SERVICE=grafana` | Follow logs for one service |

`make sync-prune` can delete generated `.conf` and `config.yml` files because they do not exist in the source tree. Run `make prepare` afterward before starting or recreating services. Ordinary `make sync` preserves those generated files. Neither sync command reloads running services.

After nginx changes, render configuration and reload nginx (or restart it). After Prometheus or Alertmanager configuration changes, sync and restart the corresponding service. `make deploy` does not force those applications to reload unchanged containers.

When using Docker Compose v2, add `COMPOSE="docker compose"` to the Make command, for example:

```bash
make COMPOSE="docker compose" status
```

## Alerting

Alertmanager configuration is stored in:

```text
alertmanager/alertmanager.yml
```

The default receiver has no notification integrations enabled, so it sends no notifications. Prometheus is configured to forward alerts to Alertmanager. Configure one or more receiver integrations to deliver them:

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

The service is already enabled in Compose; it has no optional profile. The repository does not supply `pve/pve.yml`. Create it with your Proxmox credentials before deployment, or remove/comment out the `pve-exporter` service if it is not needed. `make prepare` copies `pve/` when present but does not check for its credential file.

No Proxmox scrape job is configured in Prometheus. Add a job to the existing `scrape_configs` list, adapting the following example to your Proxmox host and credential module:

```yaml
  - job_name: pve
    metrics_path: /pve
    params:
      module: [default]
      cluster: ['1']
      node: ['1']
    static_configs:
      - targets: ["pve.example.com"]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: pve-exporter:9221
```

The target is the Proxmox API host; the exporter receives it as a query parameter. Scraping the exporter at its default metrics path does not request these Proxmox metrics. See the [exporter's configuration documentation](https://github.com/prometheus-pve/prometheus-pve-exporter#prometheus-configuration) for credential modules and scrape parameters. Sync the configuration and restart Prometheus after editing it.

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

The server stack runs Node Exporter with `network_mode: host`, so it is not attached to the Compose `monitoring` network. The supplied `node-exporter:9100` target therefore does not resolve through Docker service DNS. Replace it in `prometheus/prometheus.yml` with a host address reachable from the Prometheus container, then sync and restart Prometheus. `localhost:9100` inside Prometheus refers to the Prometheus container, not the host. The host exporter listener is not protected by nginx TLS.

### Portainer console or startup problems

Nginx lists Portainer in `depends_on` and forwards WebSocket upgrade headers over HTTP/1.1 for interactive consoles. The proxy read timeout is 24 hours to accommodate idle console sessions. Compose orders container startup but does not wait for Portainer to become ready. If the UI or console fails, check Portainer and nginx logs, confirm that Portainer is listening internally on port `9000`, and ensure the current nginx template has been rendered and reloaded.

### PVE Exporter fails to start

Create `pve/pve.yml` or remove the `pve-exporter` service if Proxmox monitoring is not needed.
