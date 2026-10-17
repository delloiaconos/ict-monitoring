# Monitored host

Run this stack on each additional Docker host you want to monitor. It exposes host and container metrics for the central Prometheus instance and a Portainer Agent for remote Docker management.

[Project overview](../README.md) · [Monitoring server guide](../monitoring-server/README.md)

## Services

| Service | Purpose | Published host port | Container port |
| --- | --- | ---: | ---: |
| Portainer Agent | Remote Docker management from Portainer | 9901 | 9001 |
| cAdvisor | Container metrics | 9902 | 8080 |
| Node Exporter | Host metrics | 9903 | 9100 |

Metrics are available at `http://<host>:9902/metrics` and `http://<host>:9903/metrics`. These endpoints use HTTP; the monitoring server's HTTPS proxy does not protect ports published on remote hosts.

## Prerequisites

- A Linux Docker host with Docker and Docker Compose installed
- A user that can run Docker commands
- Network access from the monitoring server to ports `9901`, `9902`, and `9903`

## Quick start

1. Clone the repository on the host and enter this directory:

   ```bash
   git clone <repository-url>
   cd ict-monitoring/monitoring-host
   ```

2. Review [docker-compose.yml](docker-compose.yml), including host port mappings and mounted paths.

3. Start the agents:

   ```bash
   docker compose up -d
   docker compose ps
   ```

For legacy installations, replace `docker compose` with `docker-compose`.

## Connect to the monitoring server

On the monitoring server, add this host's cAdvisor and Node Exporter endpoints to Prometheus and register its Portainer Agent. Follow [Connect monitored hosts](../monitoring-server/README.md#connect-monitored-hosts) for the configuration example and commands to apply it.

Use a hostname or IP address reachable from the monitoring server. If you change a published port in Compose, update the corresponding Prometheus target or Portainer environment address.

## Operations

Run these commands from `monitoring-host/`:

| Command | Description |
| --- | --- |
| `docker compose up -d` | Start services or apply Compose changes |
| `docker compose ps` | Show service status |
| `docker compose logs -f` | Follow all service logs |
| `docker compose logs -f cadvisor` | Follow cAdvisor logs |
| `docker compose restart` | Restart the agents |
| `docker compose down` | Stop and remove the agent containers |

## Security notes

- Restrict the published ports to the monitoring server through firewall rules or a private network/VPN; do not expose them directly to the internet.
- Portainer Agent mounts the Docker socket and Docker volumes. Treat access to it as privileged access to the host.
- cAdvisor runs with elevated privileges and mounts host paths; Node Exporter reads the host filesystem and uses the host PID namespace.
- Pin image versions in production instead of relying on `latest`.

## Troubleshooting

### Metrics do not appear in Prometheus

Check that the containers are running with `docker compose ps`. From the monitoring server, verify access to `http://<host>:9902/metrics` and `http://<host>:9903/metrics`, then check the targets in Prometheus. Confirm that DNS, firewall rules, and configured ports match the Compose port mappings.

### Portainer cannot connect

Use the published Agent port `9901`, rather than the container's internal port `9001`. Confirm that the monitoring server can reach it and inspect `docker compose logs portainer-agent`.

### A published port is already in use

Change the left-hand port in the relevant mapping in `docker-compose.yml`, run `docker compose up -d`, and update the monitoring server configuration to match.
