# ICT Monitoring

A central monitoring platform for Docker hosts and Proxmox environments, with a lightweight agent stack for the machines it monitors.

ICT Monitoring brings metrics, dashboards, alerts, and infrastructure management together using Docker Compose. Deploy the monitoring server once, then add agents to each Docker host as your environment grows.

## What it provides

- **Metrics and alerts:** Prometheus collects host and container metrics; Alertmanager routes notifications.
- **Dashboards:** Grafana visualizes metrics, while Homer provides a landing page for the monitoring tools.
- **Infrastructure management:** Portainer manages Docker environments, and Pulse provides an additional monitoring interface.
- **Proxmox monitoring:** A configurable Proxmox exporter extends metrics collection to your virtualization environment.
- **HTTPS access:** Nginx terminates TLS for the server's web interfaces. Internal proxy traffic uses HTTP, with support for supplied or locally generated self-signed certificates.

## How it fits together

The **monitoring server** runs the central services and collects metrics from both itself and remote hosts. Each **monitored host** runs cAdvisor, Node Exporter, and Portainer Agent. Prometheus scrapes the exporters, while Portainer connects to the agents for Docker management.

Browser access to the central web interfaces goes through Nginx on port `443`. Remote agent connections use separate ports over your private network or VPN.

## Deployment guides

| Component | Where to deploy | Documentation |
| --- | --- | --- |
| Monitoring server | The central monitoring machine | [Setup, certificates, configuration, and operations](monitoring-server/README.md) |
| Monitored host | Each additional Docker host | [Agent setup, server registration, and operations](monitoring-host/README.md) |

Start with the monitoring server guide, configure your domain and certificates, then deploy agents on the hosts you want to monitor. Both stacks require Docker and Docker Compose; each guide lists its additional prerequisites.

## Repository layout

```text
.
├── README.md               # Project overview
├── LICENSE
├── monitoring-server/      # Central services, nginx, and deployment tools
│   └── README.md           # Monitoring server guide
└── monitoring-host/        # Exporters and Portainer Agent for remote hosts
    └── README.md           # Monitored host guide
```

## License

Licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
