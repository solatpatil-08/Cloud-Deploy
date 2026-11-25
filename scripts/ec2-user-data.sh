#!/usr/bin/env bash
exec > >(tee /var/log/user-data.log) 2>&1
# ==============================================================================
# CloudDeploy EC2 User Data Bootstrap Script
# Operating System: Amazon Linux 2023 (AL2023)
# Target Instance:  CloudDeploy-Server (t3.large / t3.medium)
#
# This script executes automatically as root during the initial EC2 instance launch.
# It installs Docker, pins Docker Compose with SHA256 verification, enables SSM Agent,
# configures the application workspace, and sets up permissions.
# ==============================================================================

set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
COMPOSE_VERSION="v2.32.4"
COMPOSE_SHA256="ed1917fb54db184192ea9d0717bcd59e3662ea79db48bff36d3475516c480a6b"

echo "================================================================================"
echo "Starting CloudDeploy EC2 Bootstrap: $(date -u) (Region: ${AWS_REGION})"
echo "================================================================================"

# 1. Update OS packages
echo "--> Updating system packages..."
dnf update -y

# 2. Install Docker, Git, and prerequisite utilities
echo "--> Installing Docker and core dependencies..."
dnf install -y docker git libxcrypt-compat jq

# 3. Enable and Start Docker Service
echo "--> Configuring Docker daemon..."
systemctl enable --now docker
usermod -aG docker ec2-user

# 4. Install Docker Compose CLI plugin (Pinned version with SHA256 verification)
echo "--> Installing Docker Compose ${COMPOSE_VERSION}..."
DOCKER_PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"
mkdir -p "$DOCKER_PLUGIN_DIR"
COMPOSE_BIN="${DOCKER_PLUGIN_DIR}/docker-compose"
COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"

curl -sSL "$COMPOSE_URL" -o "$COMPOSE_BIN"
echo "${COMPOSE_SHA256}  ${COMPOSE_BIN}" | sha256sum -c -
chmod +x "$COMPOSE_BIN"
ln -sf "$COMPOSE_BIN" /usr/local/bin/docker-compose

# 5. Ensure AWS Systems Manager (SSM) Agent is active
echo "--> Enabling and starting amazon-ssm-agent..."
systemctl enable --now amazon-ssm-agent

# 6. Create deployment workspace directory
echo "--> Preparing application workspace at /opt/clouddeploy..."
mkdir -p /opt/clouddeploy
mkdir -p /opt/clouddeploy/scripts
mkdir -p /opt/clouddeploy/docker/nginx/conf.d
mkdir -p /opt/clouddeploy/docker/nginx/snippets
mkdir -p /opt/clouddeploy/docker/nginx/ssl
mkdir -p /opt/clouddeploy/docker/prometheus
mkdir -p /opt/clouddeploy/docker/grafana/provisioning/datasources
mkdir -p /opt/clouddeploy/docker/grafana/provisioning/dashboards
mkdir -p /opt/clouddeploy/docker/grafana/dashboards

chown -R ec2-user:ec2-user /opt/clouddeploy
chmod 755 /opt/clouddeploy

# 7. Add health check / readiness file
cat <<EOF > /opt/clouddeploy/BOOTSTRAP_COMPLETE
CloudDeploy EC2 Instance Bootstrap Finished Successfully.
Date: $(date -u)
Region: ${AWS_REGION}
Instance AMI: Amazon Linux 2023
Docker Version: $(docker --version)
Docker Compose Version: $(docker-compose --version)
SSM Agent Status: $(systemctl is-active amazon-ssm-agent)
EOF

echo "================================================================================"
echo "CloudDeploy EC2 Bootstrap Complete: $(date -u)"
echo "================================================================================"
