#!/bin/bash
set -e

# ========== 可选：启用代理以加速下载 ==========
# export http_proxy="http://127.0.0.1:7897" # 根据实际情况决定是否启用，并修改端口号
# export https_proxy="http://127.0.0.1:7897" 

echo "🚀 启动 DCGM + dcgm-exporter + Prometheus + Grafana 全自动部署..."

# ========== 安装 Go ==========
GO_VERSION="1.23.8"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"

# 检测本机是否已安装 go
if command -v go >/dev/null 2>&1; then
  # 取出版本号，例如 "go1.23.8" → "1.23.8"
  CURRENT_VERSION=$(go version | awk '{print $3}' | sed 's/^go//')
  if [[ "$CURRENT_VERSION" == "$GO_VERSION" ]]; then
    echo "✅ 已检测到 Go $GO_VERSION，跳过安装"
  else
    echo "🔄 检测到系统 Go 版本 $CURRENT_VERSION，与目标版本 $GO_VERSION 不符，开始升级..."
    sudo rm -rf /usr/local/go
    wget -q https://go.dev/dl/${GO_TARBALL}
    sudo tar -C /usr/local -xzf ${GO_TARBALL}
    rm -f ${GO_TARBALL}
    echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
    export PATH=/usr/local/go/bin:$PATH
    source ~/.bashrc
    echo "✅ 已升级到 Go $GO_VERSION"
  fi
else
  echo "📦 未检测到 Go，开始安装 Go $GO_VERSION..."
  wget -q https://go.dev/dl/${GO_TARBALL}
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf ${GO_TARBALL}
  rm -f ${GO_TARBALL}
  echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
  export PATH=/usr/local/go/bin:$PATH
  source ~/.bashrc
  echo "✅ 已安装 Go $GO_VERSION"
fi


# ========== 安装 jq（用于解析 JSON） ==========
if ! command -v jq >/dev/null; then
  echo "📦 安装 jq..."
  sudo apt-get update
  sudo apt-get install -y jq
else
  echo "✅ jq 已安装"
fi

export GOPROXY=https://goproxy.cn,direct

# ========== 安装 DCGM ==========
if ! dpkg -l | grep -q datacenter-gpu-manager; then
  echo "📦 添加 NVIDIA APT 源并安装 DCGM..."
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i cuda-keyring_1.1-1_all.deb
  sudo add-apt-repository -y "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /"
  sudo apt update
  sudo apt install -y datacenter-gpu-manager
else
  echo "✅ DCGM 已安装"
fi

sudo systemctl enable --now nvidia-dcgm

# ========== 确保 libdcgm.so.4 存在，否则升级到 DCGM 4.x ==========
if ! ldconfig -p | grep -q libdcgm.so.4; then
  echo "🔄 检测到 libdcgm.so.4 缺失，正在升级至 DCGM 4.x..."
  sudo apt remove -y datacenter-gpu-manager
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/datacenter-gpu-manager_4.0.5-1_amd64.deb
  sudo dpkg -i datacenter-gpu-manager_4.0.5-1_amd64.deb
  rm -f datacenter-gpu-manager_4.0.5-1_amd64.deb
  sudo ldconfig
else
  echo "✅ 已检测到 libdcgm.so.4"
fi

# ========== 安装 dcgm-exporter ==========
if ! command -v dcgm-exporter >/dev/null; then
  echo "📦 克隆并编译 dcgm-exporter..."
  git clone https://github.com/NVIDIA/dcgm-exporter.git
  cd dcgm-exporter
  rm -f cmd/dcgm-exporter/dcgm-exporter
  make binary
  sudo install -m 755 cmd/dcgm-exporter/dcgm-exporter /usr/local/bin/dcgm-exporter
  sudo install -m 644 -D ./etc/default-counters.csv /etc/dcgm-exporter/default-counters.csv
  cd ..
else
  echo "✅ dcgm-exporter 已安装"
fi

# ========== 创建 systemd 服务 dcgm-exporter ==========
if [[ ! -f /etc/systemd/system/dcgm-exporter.service ]]; then
  echo "🛠️ 注册 systemd 服务 dcgm-exporter..."
  sudo tee /etc/systemd/system/dcgm-exporter.service > /dev/null <<EOF
[Unit]
Description=NVIDIA DCGM Exporter
After=network.target nvidia-dcgm.service

[Service]
ExecStart=/usr/local/bin/dcgm-exporter --address 0.0.0.0:9400
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now dcgm-exporter
else
  echo "✅ dcgm-exporter 服务已存在"
fi

# ========== 安装 Prometheus ==========
if [[ ! -d /opt/prometheus ]]; then
  echo "📦 安装 Prometheus..."
  PROM_VERSION=2.51.2
  wget -q https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz
  tar -xzf prometheus-${PROM_VERSION}.linux-amd64.tar.gz
  sudo mv prometheus-${PROM_VERSION}.linux-amd64 /opt/prometheus
  rm -f prometheus-${PROM_VERSION}.linux-amd64.tar.gz

  echo "⚙️ 生成 Prometheus 配置..."
  cat <<EOF | sudo tee /opt/prometheus/prometheus.yml > /dev/null
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'dcgm-exporter'
    static_configs:
      - targets: ['localhost:9400']
EOF

  echo "✅ Prometheus 已安装"
else
  echo "✅ Prometheus 已安装"
fi

# ========== 创建 systemd 服务 prometheus ==========
if [[ ! -f /etc/systemd/system/prometheus.service ]]; then
  echo "🛠️ 注册 systemd 服务 prometheus..."
  sudo mkdir -p /opt/prometheus/data
  sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/opt/prometheus/prometheus \\
  --config.file=/opt/prometheus/prometheus.yml \\
  --storage.tsdb.path=/opt/prometheus/data
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now prometheus
else
  echo "✅ Prometheus 服务已存在"
fi

# ========== 安装 Grafana ==========
if ! dpkg -l | grep -q grafana; then
  echo "📦 安装 Grafana..."
  sudo apt-get install -y apt-transport-https software-properties-common gnupg2
  wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
  sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
  sudo apt update
  sudo apt install -y grafana
  sudo systemctl enable --now grafana-server
else
  echo "✅ Grafana 已安装"
fi

# ========== 自动导入 Grafana Dashboard ==========
echo "📋 正在导入 Grafana DCGM Dashboard（ID: 12239）"
read -p "是否已有 API Token？[y/N]: " HAS_TOKEN
HAS_TOKEN=${HAS_TOKEN,,}

if [[ "$HAS_TOKEN" == "y" ]]; then
  read -p "请输入你的 Grafana API Token: " GRAFANA_TOKEN
else
  echo "🔐 使用用户名/密码登录 Grafana 并生成 Token"
  read -p "Grafana 用户名（默认 admin）: " GRAFANA_USER
  GRAFANA_USER=${GRAFANA_USER:-admin}
  read -s -p "Grafana 密码: " GRAFANA_PASS
  echo

  GRAFANA_TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/keys \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d '{
      "name":"dcgm-auto-import",
      "role":"Admin",
      "secondsToLive": 3600
    }' | jq -r .key)

  if [[ "$GRAFANA_TOKEN" == "null" || -z "$GRAFANA_TOKEN" ]]; then
    echo "❌ 登录失败或生成 token 失败，请检查用户名密码或 Grafana 是否启动"
    exit 1
  else
    echo "✅ 成功获取临时 token"
  fi
fi

# 使用完整 dashboard import 接口导入
curl -s -X POST http://localhost:3000/api/dashboards/db \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "dashboard": $(curl -s https://grafana.com/api/dashboards/12239/revisions/latest/download),
  "overwrite": true,
  "message": "自动导入 DCGM Dashboard"
}
EOF

# ========== 安装 node_exporter ==========
if ! command -v node_exporter >/dev/null; then
  echo "📦 安装 node_exporter（用于 CPU、内存、磁盘等系统指标监控）..."
  NODE_EXPORTER_VERSION="1.8.0"
  wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
  tar -xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
  sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
  rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*
else
  echo "✅ node_exporter 已安装"
fi

# ========== 创建 systemd 服务 node_exporter ==========
if [[ ! -f /etc/systemd/system/node_exporter.service ]]; then
  echo "🛠️ 注册 systemd 服务 node_exporter..."
  sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user-target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now node_exporter
else
  echo "✅ node_exporter 服务已存在"
fi

# ========== 更新 Prometheus 配置以抓取 node_exporter ==========
if ! grep -q 'node-exporter' /opt/prometheus/prometheus.yml; then
  echo "📦 更新 Prometheus 配置以抓取 node_exporter 数据..."
  cat <<EOF | sudo tee /opt/prometheus/prometheus.yml > /dev/null
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'dcgm-exporter'
    static_configs:
      - targets: ['localhost:9400']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

  echo "🔄 重启 Prometheus 以应用新配置..."
  sudo systemctl restart prometheus
else
  echo "✅ Prometheus 已配置抓取 node_exporter"
fi

# ========== 完成 ==========
echo ""
echo "🎉 所有组件安装与配置完成！你可以访问："
echo "📡 Prometheus:  http://localhost:9090"
echo "📊 Grafana:     http://localhost:3000"
echo "🔑 默认登录:    admin / admin"
echo "📈 导入 Dashboard ID: 12239 查看 GPU 指标"
echo "📈 导入 Dashboard ID: 1860 查看 CPU、内存、磁盘、网络、负载等信息"
