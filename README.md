# ICT Monitoring

Docker-based monitoring infrastructure for Docker and Proxmox environments.

This repository provides a central monitoring stack and a lightweight agent stack for additional Docker hosts. It combines Prometheus, Alertmanager, Grafana, cAdvisor, Node Exporter, Portainer, Pulse, Homer, and Nginx reverse proxy configuration into a deployable observability setup.

## Contents

- [Architecture](#architecture)
- [Services](#services)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [DNS and networking](#dns-and-networking)
- [Quick start: monitoring server](#quick-start-monitoring-server)
- [Deploy monitored host agents](#deploy-monitored-host-agents)
- [Configuration](#configuration)
- [Operations](#operations)
- [Alerting](#alerting)
- [Proxmox monitoring](#proxmox-monitoring)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Architecture

```text
+----------------------+       +---------------------------+
| Monitored Docker host |       | Monitoring server         |
|                      |       |                           |
| portainer-agent:9901 +------>+ Portainer                 |
| cadvisor:9902        +------>+ Prometheus                |
| node-exporter:9903   +------>+ Grafana                   |
+----------------------+       | Alertmanager              |
                               | cAdvisor / Node Exporter  |
                               | Pulse                     |
                               | Homer dashboard           |
                               | Nginx reverse proxy       |
                               +---------------------------+
```

The `monitoring-server` directory runs the main observability platform. The `monitoring-host` directory runs exporters and a Portainer agent on additional hosts that should be monitored remotely.

## Services

### Monitoring server

| Service | Purpose | Internal port | Public hostname pattern |
| --- | --- | ---: | --- |
| Homer | Landing page for the monitoring tools | 8080 | `http://homer.<BASE_DOMAIN>` and `http://<BASE_DOMAIN>` |
| Grafana | Dashboards and visualization | 3000 | `http://grafana.<BASE_DOMAIN>` |
| Prometheus | Metrics collection and alert rules | 9090 | `http://prometheus.<BASE_DOMAIN>` |
| Alertmanager | Alert routing and notifications | 9093 | `http://alertmanager.<BASE_DOMAIN>` |
| Portainer | Docker management UI | 9000 | `http://portainer.<BASE_DOMAIN>` |
| Pulse | Lightweight status/monitoring UI | 7655 | `http://pulse.<BASE_DOMAIN>` |
| cAdvisor | Container metrics for the monitoring server | 8080 | Not exposed directly |
| Node Exporter | Host metrics for the monitoring server | 9100 | Not exposed directly |
| PVE Exporter | Proxmox metrics exporter | 9221 | Not exposed directly |
| Nginx | Reverse proxy for public service hostnames | 80 | Public entry point |

### Monitored host

| Service | Purpose | Host port |
| --- | --- | ---: |
| Portainer Agent | Allows the central Portainer instance to manage the host | 9901 |
| cAdvisor | Container metrics endpoint | 9902 |
| Node Exporter | Host metrics endpoint | 9903 |

## Repository layout

```text
.
├── LICENSE
├── README.md
├── monitoring-host/
│   └── docker-compose.yml
└── monitoring-server/
    ├── .env.example
    ├── Makefile
    ├── alertmanager/
    │   └── alertmanager.yml
    ├── docker-compose.yaml
    ├── homer/
    │   └── assets/config.yml.template
    ├── nginx/
    │   └── conf.d/*.conf.template
    └── prometheus/
        ├── prometheus.yml
        └── rules/alerts.yml
```

## Prerequisites

Install the following on the monitoring server:

- Linux host with Docker installed
- Docker Compose, either as `docker-compose` or as the modern `docker compose` plugin
- `make`
- `rsync`
- `envsubst`, usually provided by the `gettext` or `gettext-base` package
- A user that can run Docker commands
- Optional: `sudo`, if `/opt/monitoring-server` requires elevated permissions

On each monitored host, install:

- Docker
- Docker Compose

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

The current Nginx configuration exposes HTTP on port `80`. TLS is not configured in this repository yet.

## Quick start: monitoring server

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

4. Check the Compose file name.

   The repository currently contains `monitoring-server/docker-compose.yaml`, while the Makefile sync filter includes `docker-compose.yml`. Before using `make deploy`, either rename the Compose file:

   ```bash
   mv docker-compose.yaml docker-compose.yml
   ```

   Or update this line in `monitoring-server/Makefile`:

   ```makefile
   INCLUDE_FILES := docker-compose.yaml
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

## Deploy monitored host agents

On each Docker host you want to monitor:

```bash
cd monitoring-host
docker compose up -d
```

This starts:

- Portainer Agent on port `9901`
- cAdvisor on port `9902`
- Node Exporter on port `9903`

After starting the host agents, add the host endpoints to Prometheus in `monitoring-server/prometheus/prometheus.yml`, for example:

```yaml
scrape_configs:
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

Then redeploy or reload Prometheus:

```bash
cd monitoring-server
make COMPOSE="docker compose" deploy
```

## Configuration

### Environment variables

`monitoring-server/.env` is used by the Makefile to render template files.

| Variable | Description | Example |
| --- | --- | --- |
| `BASE_DOMAIN` | Base domain used for Nginx virtual hosts and Homer links | `monitoring.example.com` |

### Template rendering

Files ending in `.template` under these paths are rendered to `/opt/monitoring-server`:

- `homer/assets`
- `nginx/conf.d`

The Makefile uses `envsubst` to replace variables such as `${BASE_DOMAIN}`.

To render using a different environment file:

```bash
make ENV_FILE=.env.example render
```

To restrict rendering to specific variables:

```bash
make VARS='${BASE_DOMAIN}' render
```

### Grafana

Default credentials in `docker-compose.yaml` are:

```text
Username: admin
Password: admin
```

Change these before exposing Grafana beyond a trusted network.

### Prometheus

Prometheus configuration lives in:

```text
monitoring-server/prometheus/prometheus.yml
```

Alert rules live in:

```text
monitoring-server/prometheus/rules/alerts.yml
```

The included rules cover:

- Down scrape targets
- High host CPU usage
- Low host filesystem free space

## Operations

Run the following from `monitoring-server/`.

| Command | Description |
| --- | --- |
| `make help` | Show Makefile targets |
| `make deploy` | Prepare, sync, render, ensure `.env`, start services, and show status |
| `make sync` | Copy runtime files to `/opt/monitoring-server` |
| `make sync-prune` | Sync runtime files and delete removed files from destination |
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
monitoring-server/alertmanager/alertmanager.yml
```

The default receiver is intentionally minimal. Configure one or more notification integrations before relying on alert delivery:

- Email
- Slack
- Webhook

After editing Alertmanager configuration, redeploy or restart Alertmanager:

```bash
make COMPOSE="docker compose" restart SERVICE=alertmanager
```

## Proxmox monitoring

The Compose stack includes `prometheus-pve-exporter`, mounted from:

```text
./pve/pve.yml:/etc/prometheus/pve.yml:ro
```

Create `monitoring-server/pve/pve.yml` with your Proxmox exporter configuration before enabling this service. Also add a Prometheus scrape job if you want Prometheus to collect from it:

```yaml
scrape_configs:
  - job_name: pve-exporter
    static_configs:
      - targets: ["pve-exporter:9221"]
```

If you do not monitor Proxmox, remove or comment out the `pve-exporter` service from the Compose file.

## Security notes

- Replace the default Grafana `admin/admin` credentials.
- Add TLS before exposing services on the public internet.
- Restrict access to Prometheus, Alertmanager, Portainer, and exporters with firewall rules, VPN, authentication, or a private network.
- Avoid exposing monitored host exporter ports directly to the internet.
- Pin container image versions for production deployments instead of using `latest`.
- Treat Portainer and the Docker socket as high-privilege access.
- Configure Alertmanager secrets through protected files or environment management, not public commits.

## Troubleshooting

### `make deploy` does not copy the Compose file

Check the Compose file name mismatch described in the quick start section. Either rename `docker-compose.yaml` to `docker-compose.yml` or update `INCLUDE_FILES` in the Makefile.

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

Create `monitoring-server/pve/pve.yml` or remove the `pve-exporter` service if Proxmox monitoring is not needed.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
