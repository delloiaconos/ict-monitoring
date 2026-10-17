# ICT Monitoring

A central monitoring platform for Docker hosts and Proxmox environments, with a lightweight agent stack for the machines it monitors.

ICT Monitoring brings metrics, dashboards, alerts, and infrastructure management together using Docker Compose. Deploy the monitoring server once, then add agents to each Docker host as your environment grows.

## What it provides

- **Metrics and alerts:** Prometheus is configured to scrape local services and exporters. Host scraping needs an address correction; Alertmanager notifications require receiver configuration.
- **Dashboards:** Grafana provides the visualization interface; datasources and dashboards must be configured. Homer provides a landing page for the monitoring tools.
- **Infrastructure management:** Portainer manages Docker environments, and Pulse provides an additional monitoring interface.
- **Proxmox monitoring:** A Proxmox exporter is included; its credentials and Prometheus scrape job must be configured, or its service removed.
- **HTTPS access:** Nginx terminates TLS for the server's web interfaces. Internal proxy traffic uses HTTP, with support for supplied or locally generated self-signed certificates.

## How it fits together

The **monitoring server** runs the central services with local scrape targets. Remote hosts must be added to its Prometheus configuration and registered in Portainer. Each **monitored host** runs cAdvisor, Node Exporter, and Portainer Agent. After registration, Prometheus scrapes the exporters and Portainer connects to the agents for Docker management.

Browser access to the central web interfaces goes through Nginx on port `443`. Node Exporter also listens directly on the monitoring host at port `9100`. Remote agents publish separate ports; private networking, VPNs, and firewall restrictions must be provided by the operator.

## Deployment guides

| Component | Where to deploy | Documentation |
| --- | --- | --- |
| Monitoring server | The central monitoring machine | [Setup, certificates, configuration, and operations](monitoring-server/README.md) |
| Monitored host | Each additional Docker host | [Agent setup, server registration, and operations](monitoring-host/README.md) |

Start with the monitoring server guide, configure your domain and certificates, and run `make prepare` before starting Compose from the runtime directory. Then deploy and register agents on the hosts you want to monitor. Both stacks require Docker and Docker Compose; each guide lists its additional prerequisites.

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
