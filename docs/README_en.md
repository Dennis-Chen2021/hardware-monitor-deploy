<p align="right">
  <a href="../README.md">中文</a>
</p>

---

# System Monitoring Deployment Script (Ubuntu)

This script automates the installation and configuration of:  
- **NVIDIA DCGM** (Data Center GPU Manager)  
- **dcgm-exporter** (Prometheus exporter for GPU metrics)  
- **Prometheus** (metrics collection and storage)  
- **Grafana** (dashboard visualization)  
- **node_exporter** (exporter for CPU, memory, disk, network, and load metrics)

## Table of Contents

- [System Monitoring Deployment Script (Ubuntu)](#system-monitoring-deployment-script-ubuntu)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Usage](#usage)
  - [Features](#features)
  - [Script Workflow](#script-workflow)
  - [Default Dashboards](#default-dashboards)
  - [Configuration](#configuration)
  - [Troubleshooting](#troubleshooting)

## Prerequisites

- Ubuntu 22.04 LTS (tested)  
- **sudo** privileges  
- Internet access (or configure proxy via environment variables)  
- `bash` shell

## Usage

1. **Download or clone this script**:
   ```bash
   git clone https://github.com/Dennis-Chen2021/hardware-monitor-deploy.git
   cd hardware-monitor-deploy
   chmod +x hardware-monitor-deploy.sh
   ```

2. **(Optional) Configure Proxy**: edit the `http_proxy` and `https_proxy` variables at the top if needed.

3. **Run the script**:
   ```bash
   sudo ./hardware-monitor-deploy.sh
   ```
   The script will prompt for Grafana credentials or an existing API token.

## Features

- Go installation (v1.23.8)  
- jq installation for JSON parsing  
- DCGM installation and service enablement  
- dcgm-exporter build, install, and service registration  
- Prometheus installation, configuration, and service registration  
- Grafana installation and automatic dashboard import  
- node_exporter installation and service registration (system metrics)  
- Updates Prometheus scrape targets for GPU & system metrics

## Script Workflow

1. Optional: set up proxy  
2. Install or upgrade Go  
3. Install jq  
4. Install NVIDIA DCGM  
5. Build and install dcgm-exporter  
6. Register dcgm-exporter service  
7. Install Prometheus and generate config  
8. Register Prometheus service  
9. Install Grafana  
10. Import Grafana dashboards  
11. Install node_exporter  
12. Register node_exporter service  
13. Update config and restart Prometheus

## Default Dashboards

- GPU metrics: Dashboard ID `12239` (NVIDIA DCGM Dashboard)  
- System metrics: Dashboard ID `1860` (Node Exporter Full)

Access Grafana at `http://<your-server>:3000` with default credentials:
```
Username: admin
Password: admin
```

## Configuration

- Versions: modify `GO_VERSION`, `PROM_VERSION`, and `NODE_EXPORTER_VERSION` at the top.  
- Bind address: dcgm-exporter listens on `0.0.0.0:9400`; change the service file if needed.  
- Prometheus config: `/opt/prometheus/prometheus.yml`.

## Troubleshooting

- Check service status:
  ```bash
  systemctl status dcgm-exporter prometheus grafana-server node_exporter
  ```
- View logs:
  ```bash
  journalctl -u dcgm-exporter -f
  journalctl -u prometheus -f
  journalctl -u grafana-server -f
  journalctl -u node_exporter -f
  ```
- Ensure ports `9400`, `9100`, `9090`, and `3000` are open.
