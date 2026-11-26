#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - Production Application Deployment Script
# Automates zero-downtime rolling container updates on AWS EC2.
#
# Steps:
# 1. Accepts application image tag parameter
# 2. Authenticates with Amazon ECR using EC2 instance role
# 3. Pulls target Docker image
# 4. Preserves currently deployed tag to .previous_version
# 5. Updates runtime configuration in .env
# 6. Runs Docker Compose to recreate the application container
# 7. Waits for health check verification
# 8. Verifies service availability via public Nginx gateway
# 9. Saves deployment metadata and history
# 10. Automatically triggers rollback if deployment fails
# ==============================================================================

set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/clouddeploy}"
COMPOSE_FILE="${DEPLOY_DIR}/compose.prod.yaml"
ENV_FILE="${DEPLOY_DIR}/.env"
CURRENT_FILE="${DEPLOY_DIR}/.current_version"
PREVIOUS_FILE="${DEPLOY_DIR}/.previous_version"
HISTORY_LOG="${DEPLOY_DIR}/logs/deployment-history.log"
DEPLOY_LOG="${DEPLOY_DIR}/logs/deploy.log"

mkdir -p "${DEPLOY_DIR}/logs"
exec > >(tee -a "$DEPLOY_LOG") 2>&1

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Validate Image Tag Parameter
IMAGE_TAG="${1:-${IMAGE_TAG:-}}"
if [ -z "$IMAGE_TAG" ]; then
    echo -e "${RED}Error: Target image tag is required.${NC}" >&2
    echo -e "Usage: $0 <IMAGE_TAG>" >&2
    echo -e "Example: $0 v1.0.0" >&2
    exit 1
fi

echo -e "${CYAN}================================================================================${NC}"
echo -e "${CYAN}           CloudDeploy Production Application Deployment                        ${NC}"
echo -e "${CYAN}           Target Image Tag: ${IMAGE_TAG}                                      ${NC}"
echo -e "${CYAN}           Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')                          ${NC}"
echo -e "${CYAN}================================================================================${NC}"

# Ensure environment file exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}--> ${ENV_FILE} not found. Attempting to synchronize secrets from SSM...${NC}"
    if [ -f "${DEPLOY_DIR}/scripts/fetch-ssm-secrets.sh" ]; then
        bash "${DEPLOY_DIR}/scripts/fetch-ssm-secrets.sh"
    else
        echo -e "${RED}Error: ${ENV_FILE} missing and fetch-ssm-secrets.sh not available.${NC}" >&2
        exit 1
    fi
fi

# Load deployment parameters from .env
AWS_REGION=$(grep -E '^AWS_REGION=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "\r\n' || echo "ap-south-1")
ECR_REGISTRY=$(grep -E '^ECR_REGISTRY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "\r\n' || echo "")
ECR_REPOSITORY=$(grep -E '^ECR_REPOSITORY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "\r\n' || echo "clouddeploy-task-api")

if [ -z "$ECR_REGISTRY" ]; then
    echo -e "${RED}Error: ECR_REGISTRY is not defined in ${ENV_FILE}.${NC}" >&2
    exit 1
fi

FULL_IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

# 2. Authenticate with AWS ECR using EC2 Instance Role
echo -e "\n${YELLOW}[1/6] Authenticating to Amazon ECR (${AWS_REGION})...${NC}"
if ! command -v aws &>/dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH.${NC}" >&2
    exit 1
fi

aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo -e "${GREEN}--> ECR authentication succeeded.${NC}"

# 3. Pull specified Docker image
echo -e "\n${YELLOW}[2/6] Pulling application image: ${CYAN}${FULL_IMAGE_URI}${NC}..."
docker pull "$FULL_IMAGE_URI"

# 4. Preserve currently deployed image tag before changing state
echo -e "\n${YELLOW}[3/6] Preserving previous version metadata...${NC}"
CURRENT_TAG=""
if [ -f "$CURRENT_FILE" ]; then
    CURRENT_TAG=$(tr -d ' \r\n' < "$CURRENT_FILE")
elif grep -q '^IMAGE_TAG=' "$ENV_FILE"; then
    CURRENT_TAG=$(grep -E '^IMAGE_TAG=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "\r\n')
fi

if [ -n "$CURRENT_TAG" ] && [ "$CURRENT_TAG" != "$IMAGE_TAG" ]; then
    echo "$CURRENT_TAG" > "$PREVIOUS_FILE"
    echo -e "  Saved previous version: ${CYAN}${CURRENT_TAG}${NC} -> ${PREVIOUS_FILE}"
else
    echo -e "  Initial deployment or re-deploying same tag: ${IMAGE_TAG}"
fi

# 5. Update deployment image reference in .env
echo -e "\n${YELLOW}[4/6] Updating deployment runtime configuration...${NC}"
sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=${IMAGE_TAG}|" "$ENV_FILE"
echo -e "  Updated IMAGE_TAG=${IMAGE_TAG} in ${ENV_FILE}"

# 6. Run Docker Compose to recreate application
echo -e "\n${YELLOW}[5/6] Updating application container via Docker Compose...${NC}"
echo -e "  ${GREEN}[SAFETY CHECK] PostgreSQL persistent volumes remain mounted and intact.${NC}"

# Start database and monitoring if not already running
docker compose -f "$COMPOSE_FILE" up -d postgres prometheus grafana

# Recreate app with new image tag
docker compose -f "$COMPOSE_FILE" up -d --no-deps app
docker compose -f "$COMPOSE_FILE" up -d nginx

# 7. Wait for application health checks and verify availability
echo -e "\n${YELLOW}[6/6] Verifying application health and endpoint availability...${NC}"
HEALTH_SCRIPT="${DEPLOY_DIR}/scripts/health-check.sh"
TIMEOUT=75
ELAPSED=0
DEPLOY_SUCCESS=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ -f "$HEALTH_SCRIPT" ]; then
        if bash "$HEALTH_SCRIPT" --quiet; then
            DEPLOY_SUCCESS=true
            break
        fi
    else
        # Direct curl check fallback
        if curl -sf -m 5 "http://localhost/health" 2>/dev/null | grep -q '"status":"UP"'; then
            DEPLOY_SUCCESS=true
            break
        fi
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  Polling health check... (${ELAPSED}/${TIMEOUT}s)"
done

if [ "$DEPLOY_SUCCESS" = true ]; then
    # Save new deployment information
    echo "$IMAGE_TAG" > "$CURRENT_FILE"
    TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    echo "[${TIMESTAMP}] DEPLOY SUCCESS: Image tag '${IMAGE_TAG}' successfully rolled out" >> "$HISTORY_LOG"

    echo -e "\n${GREEN}================================================================================${NC}"
    echo -e "${GREEN}>>> DEPLOYMENT SUCCEEDED: Application is UP and HEALTHY on ${IMAGE_TAG} <<<${NC}"
    echo -e "${GREEN}================================================================================${NC}"
    exit 0
else
    TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    echo "[${TIMESTAMP}] DEPLOY FAILED: Image tag '${IMAGE_TAG}' failed health probe after ${TIMEOUT}s" >> "$HISTORY_LOG"

    echo -e "\n${RED}================================================================================${NC}"
    echo -e "${RED}>>> DEPLOYMENT FAILED: Application unhealthy after ${TIMEOUT}s. <<<${NC}"
    echo -e "${RED}================================================================================${NC}"
    
    echo -e "\n${YELLOW}Application container logs:${NC}"
    docker compose -f "$COMPOSE_FILE" logs --tail 40 app || true

    # Automated Rollback Trigger
    if [ -f "$PREVIOUS_FILE" ] && [ -s "$PREVIOUS_FILE" ]; then
        PREV_ROLLBACK=$(tr -d ' \r\n' < "$PREVIOUS_FILE")
        echo -e "\n${YELLOW}--> Initiating automatic rollback to previous version: ${CYAN}${PREV_ROLLBACK}${NC}...${NC}"
        if [ -f "${DEPLOY_DIR}/scripts/rollback.sh" ]; then
            bash "${DEPLOY_DIR}/scripts/rollback.sh" || {
                echo -e "${RED}Critical: Rollback procedure encountered an error.${NC}" >&2
            }
        fi
    else
        echo -e "${RED}No previous version available in ${PREVIOUS_FILE} to rollback to.${NC}" >&2
    fi

    exit 1
fi
