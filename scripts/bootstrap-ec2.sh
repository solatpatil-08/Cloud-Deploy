#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - EC2 Host Bootstrap Automation Script
# Target OS: Amazon Linux 2023 (AL2023)
# Target Instance: CloudDeploy-Server (t3.large / t3.medium)
#
# Tasks:
# 1. Install Docker, Git, jq, and core system utilities
# 2. Pin Docker Compose v2.32.4 with SHA256 checksum verification
# 3. Enable and start Docker daemon at boot
# 4. Add ec2-user to docker group
# 5. Ensure amazon-ssm-agent is active
# 6. Create /opt/clouddeploy and deployment subdirectories
# 7. Configure permissions and ownership
# 8. Prepare application and monitoring configurations
# 9. Verify Docker installation
# ==============================================================================

set -euo pipefail

# Redirect all output to bootstrap log and console
mkdir -p /var/log
exec > >(tee -a /var/log/clouddeploy-bootstrap.log) 2>&1

AWS_REGION="${AWS_REGION:-ap-south-1}"
COMPOSE_VERSION="v2.32.4"
COMPOSE_SHA256="ed1917fb54db184192ea9d0717bcd59e3662ea79db48bff36d3475516c480a6b"
DEPLOY_DIR="/opt/clouddeploy"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}================================================================================${NC}"
echo -e "${CYAN}     CloudDeploy EC2 Host Bootstrap: Amazon Linux 2023 (${AWS_REGION})          ${NC}"
echo -e "${CYAN}     Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')                                ${NC}"
echo -e "${CYAN}================================================================================${NC}"

# Ensure execution as root or sudo
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be executed as root or with sudo.${NC}" >&2
    exit 1
fi

# 1. Update system packages
echo -e "\n${YELLOW}[1/8] Updating system packages...${NC}"
dnf update -y

# 2. Install Docker, Git, jq, and dependencies
echo -e "\n${YELLOW}[2/8] Installing Docker, Git, jq, and dependencies...${NC}"
dnf install -y docker git jq libxcrypt-compat curl

# 3. Pin Docker Compose v2 with SHA256 checksum verification
echo -e "\n${YELLOW}[3/8] Installing Docker Compose ${COMPOSE_VERSION} with SHA256 verification...${NC}"
DOCKER_PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"
mkdir -p "$DOCKER_PLUGIN_DIR"
COMPOSE_BIN="${DOCKER_PLUGIN_DIR}/docker-compose"
COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"

curl -sSL "$COMPOSE_URL" -o "$COMPOSE_BIN"
echo "${COMPOSE_SHA256}  ${COMPOSE_BIN}" | sha256sum -c -
chmod +x "$COMPOSE_BIN"
ln -sf "$COMPOSE_BIN" /usr/local/bin/docker-compose

# 4. Enable and start Docker service
echo -e "\n${YELLOW}[4/8] Configuring and starting Docker service...${NC}"
systemctl daemon-reload
systemctl enable --now docker

# Add ec2-user to docker group
if id -u ec2-user >/dev/null 2>&1; then
    usermod -aG docker ec2-user
    echo -e "  ${GREEN}Added ec2-user to docker group.${NC}"
fi

# 5. Ensure Amazon SSM Agent is active
echo -e "\n${YELLOW}[5/8] Ensuring AWS Systems Manager (amazon-ssm-agent) is running...${NC}"
systemctl enable --now amazon-ssm-agent
SSM_STATUS=$(systemctl is-active amazon-ssm-agent || echo "inactive")
echo -e "  SSM Agent status: ${GREEN}${SSM_STATUS}${NC}"

# 6. Create /opt/clouddeploy and deployment subdirectories
echo -e "\n${YELLOW}[6/8] Preparing deployment directories at ${DEPLOY_DIR}...${NC}"
mkdir -p "${DEPLOY_DIR}/scripts"
mkdir -p "${DEPLOY_DIR}/logs"
mkdir -p "${DEPLOY_DIR}/docker/nginx/conf.d"
mkdir -p "${DEPLOY_DIR}/docker/nginx/snippets"
mkdir -p "${DEPLOY_DIR}/docker/nginx/ssl"
mkdir -p "${DEPLOY_DIR}/docker/prometheus"
mkdir -p "${DEPLOY_DIR}/docker/grafana/provisioning/datasources"
mkdir -p "${DEPLOY_DIR}/docker/grafana/provisioning/dashboards"
mkdir -p "${DEPLOY_DIR}/docker/grafana/dashboards"

# 7. Configure required permissions
echo -e "\n${YELLOW}[7/8] Configuring filesystem permissions...${NC}"
if id -u ec2-user >/dev/null 2>&1; then
    chown -R ec2-user:ec2-user "${DEPLOY_DIR}"
fi
chmod 755 "${DEPLOY_DIR}"
chmod 750 "${DEPLOY_DIR}/logs"

# 8. Verify Docker installation
echo -e "\n${YELLOW}[8/8] Verifying Docker and Docker Compose installation...${NC}"
DOCKER_VER=$(docker --version)
COMPOSE_VER=$(docker compose version)

echo -e "  Docker:         ${GREEN}${DOCKER_VER}${NC}"
echo -e "  Docker Compose: ${GREEN}${COMPOSE_VER}${NC}"

docker info >/dev/null 2>&1
echo -e "  Docker Daemon:  ${GREEN}Active & Responsive${NC}"

# Record bootstrap completion marker
cat <<EOF > "${DEPLOY_DIR}/BOOTSTRAP_COMPLETE"
CloudDeploy Host Bootstrap Completed Successfully.
Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Region: ${AWS_REGION}
Docker Version: ${DOCKER_VER}
Docker Compose Version: ${COMPOSE_VER}
SSM Agent Status: ${SSM_STATUS}
EOF

if id -u ec2-user >/dev/null 2>&1; then
    chown ec2-user:ec2-user "${DEPLOY_DIR}/BOOTSTRAP_COMPLETE"
fi

echo -e "\n${GREEN}================================================================================${NC}"
echo -e "${GREEN}     EC2 Host Bootstrap Complete! Server is ready for deployments.              ${NC}"
echo -e "${GREEN}================================================================================${NC}"
