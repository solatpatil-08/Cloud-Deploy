#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - SSM Parameter Store Secrets Retrieval Script
# Region: ap-south-1 (Mumbai)
#
# Fetches decrypted production secrets from AWS SSM Parameter Store:
#   - /clouddeploy/prod/DB_PASSWORD
#   - /clouddeploy/prod/JWT_SECRET
#   - /clouddeploy/prod/GRAFANA_ADMIN_PASSWORD
#
# Generates or updates /opt/clouddeploy/.env with strict permissions (chmod 600).
# Never echoes secrets to stdout or commits to version control.
# ==============================================================================

set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
ENV_FILE="${ENV_FILE:-/opt/clouddeploy/.env}"
ENV_EXAMPLE="${ENV_EXAMPLE:-/opt/clouddeploy/.env.prod.example}"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}        CloudDeploy Secrets Synchronization (AWS SSM)           ${NC}"
echo -e "${CYAN}        Region: ${AWS_REGION}                                   ${NC}"
echo -e "${CYAN}================================================================${NC}"

# Ensure AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH.${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}--> Fetching SecureString parameters from SSM...${NC}"

# Fetch secrets securely using AWS CLI and parse via jq
FETCHED_JSON=$(aws ssm get-parameters \
    --region "$AWS_REGION" \
    --names \
        "/clouddeploy/prod/DB_PASSWORD" \
        "/clouddeploy/prod/JWT_SECRET" \
        "/clouddeploy/prod/GRAFANA_ADMIN_PASSWORD" \
    --with-decryption \
    --output json)

# Extract secrets into memory variables
SSM_DB_PASSWORD=$(echo "$FETCHED_JSON" | jq -r '.Parameters[] | select(.Name=="/clouddeploy/prod/DB_PASSWORD") | .Value')
SSM_JWT_SECRET=$(echo "$FETCHED_JSON" | jq -r '.Parameters[] | select(.Name=="/clouddeploy/prod/JWT_SECRET") | .Value')
SSM_GRAFANA_PASSWORD=$(echo "$FETCHED_JSON" | jq -r '.Parameters[] | select(.Name=="/clouddeploy/prod/GRAFANA_ADMIN_PASSWORD") | .Value')

if [ -z "$SSM_DB_PASSWORD" ] || [ -z "$SSM_JWT_SECRET" ] || [ -z "$SSM_GRAFANA_PASSWORD" ]; then
    echo -e "${RED}Error: One or more parameters could not be retrieved from SSM Parameter Store.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}--> Successfully retrieved all parameters from SSM.${NC}"

# Detect AWS Account ID for ECR registry URL
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || echo "245908834556")
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Prepare or update .env file
echo -e "${YELLOW}--> Generating secure ${ENV_FILE}...${NC}"

cat <<EOF > "$ENV_FILE"
# ==============================================================================
# CloudDeploy Runtime Environment (Generated: $(date -u))
# Scoped for EC2 Production Instance
# ==============================================================================
AWS_REGION=${AWS_REGION}
INSTANCE_ID=CloudDeploy-Server

# ECR Container Registry
ECR_REGISTRY=${ECR_REGISTRY}
ECR_REPOSITORY=clouddeploy-task-api
IMAGE_TAG=latest

# Database Configuration (PostgreSQL)
DB_NAME=clouddeploy_db
DB_USERNAME=clouddeploy_user
DB_PASSWORD=${SSM_DB_PASSWORD}

# Security & JWT
JWT_SECRET=${SSM_JWT_SECRET}
JWT_EXPIRATION_MS=86400000

# Grafana Observability Dashboard
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${SSM_GRAFANA_PASSWORD}

# Port Bindings
HTTP_PORT=80
HTTPS_PORT=443
EOF

# Restrict file permissions immediately
chmod 600 "$ENV_FILE"

# Wipe secret variables from memory
unset SSM_DB_PASSWORD
unset SSM_JWT_SECRET
unset SSM_GRAFANA_PASSWORD
unset FETCHED_JSON

echo -e "${GREEN}--> ${ENV_FILE} written successfully with strict permissions (chmod 600).${NC}"
echo -e "${CYAN}--> Ready for: docker compose -f compose.prod.yaml up -d${NC}"
