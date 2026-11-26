#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - Application Rollback Automation Script
# Restores the previously deployed application Docker image in case of failure.
#
# Safety Principles:
# - NEVER deletes or down-grades PostgreSQL persistent volumes
# - NEVER executes `docker compose down -v`
# - Preserves historical deployment logs and telemetry
# - Verifies health of restored version before declaring success
# ==============================================================================

set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/clouddeploy}"
PREVIOUS_FILE="${DEPLOY_DIR}/.previous_version"
CURRENT_FILE="${DEPLOY_DIR}/.current_version"
ENV_FILE="${DEPLOY_DIR}/.env"
COMPOSE_FILE="${DEPLOY_DIR}/compose.prod.yaml"
HISTORY_LOG="${DEPLOY_DIR}/logs/deployment-history.log"
LOG_FILE="${DEPLOY_DIR}/logs/rollback.log"

mkdir -p "${DEPLOY_DIR}/logs"
exec > >(tee -a "$LOG_FILE") 2>&1

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}================================================================================${NC}"
echo -e "${CYAN}                    CloudDeploy Application Rollback                            ${NC}"
echo -e "${CYAN}                    Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')                 ${NC}"
echo -e "${CYAN}================================================================================${NC}"

# 1. Identify previous application version
if [ ! -f "$PREVIOUS_FILE" ] || [ ! -s "$PREVIOUS_FILE" ]; then
    echo -e "${RED}Error: Previous version file '${PREVIOUS_FILE}' not found or empty.${NC}" >&2
    echo -e "${RED}Cannot determine previous version to rollback to.${NC}" >&2
    exit 1
fi

PREVIOUS_TAG=$(tr -d ' \r\n' < "$PREVIOUS_FILE")
CURRENT_TAG="unknown"
if [ -f "$CURRENT_FILE" ]; then
    CURRENT_TAG=$(tr -d ' \r\n' < "$CURRENT_FILE")
fi

echo -e "${YELLOW}--> Current version:  ${CYAN}${CURRENT_TAG}${NC}"
echo -e "${YELLOW}--> Rollback target:  ${CYAN}${PREVIOUS_TAG}${NC}"

if [ "$PREVIOUS_TAG" = "$CURRENT_TAG" ]; then
    echo -e "${RED}Warning: Rollback target is identical to current version (${PREVIOUS_TAG}).${NC}"
fi

# Load environment configuration if available
if [ -f "$ENV_FILE" ]; then
    AWS_REGION=$(grep -E '^AWS_REGION=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "\r\n' || echo "ap-south-1")
    ECR_REGISTRY=$(grep -E '^ECR_REGISTRY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "\r\n' || echo "")
    ECR_REPOSITORY=$(grep -E '^ECR_REPOSITORY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d ' "\r\n' || echo "clouddeploy-task-api")
else
    AWS_REGION="${AWS_REGION:-ap-south-1}"
    ECR_REGISTRY="${ECR_REGISTRY:-}"
    ECR_REPOSITORY="${ECR_REPOSITORY:-clouddeploy-task-api}"
fi

# 2. Authenticate to ECR and pull the rollback image if necessary
if [ -n "$ECR_REGISTRY" ] && command -v aws &>/dev/null; then
    echo -e "${YELLOW}--> Authenticating to AWS ECR in ${AWS_REGION}...${NC}"
    aws ecr get-login-password --region "$AWS_REGION" 2>/dev/null | \
        docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null 2>&1 || true

    echo -e "${YELLOW}--> Verifying presence of target image: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${PREVIOUS_TAG}...${NC}"
    docker pull "${ECR_REGISTRY}/${ECR_REPOSITORY}:${PREVIOUS_TAG}" || true
fi

# 3. Update deployment image reference in .env
echo -e "${YELLOW}--> Updating runtime configuration in ${ENV_FILE}...${NC}"
if [ -f "$ENV_FILE" ]; then
    if grep -q '^IMAGE_TAG=' "$ENV_FILE"; then
        sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=${PREVIOUS_TAG}|" "$ENV_FILE"
    else
        echo "IMAGE_TAG=${PREVIOUS_TAG}" >> "$ENV_FILE"
    fi
fi

# 4. Restart the application container (Preserve all database volumes!)
echo -e "${YELLOW}--> Redeploying application container with image tag ${PREVIOUS_TAG}...${NC}"
echo -e "    ${GREEN}[SAFETY CHECK] Database volumes remain untouched.${NC}"

docker compose -f "$COMPOSE_FILE" up -d --no-deps app
docker compose -f "$COMPOSE_FILE" up -d nginx

# 5. Wait for application health check
echo -e "${YELLOW}--> Awaiting application container health verification...${NC}"
HEALTH_SCRIPT="${DEPLOY_DIR}/scripts/health-check.sh"
TIMEOUT=60
ELAPSED=0
HEALTHY=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    if [ -f "$HEALTH_SCRIPT" ]; then
        if bash "$HEALTH_SCRIPT" --quiet; then
            HEALTHY=true
            break
        fi
    else
        # Fallback to direct curl if health-check.sh is absent
        if curl -sf -m 5 "http://localhost/health" 2>/dev/null | grep -q '"status":"UP"'; then
            HEALTHY=true
            break
        fi
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  Waiting for service health... (${ELAPSED}/${TIMEOUT}s)"
done

if [ "$HEALTHY" = true ]; then
    # Update current version tracking
    echo "$PREVIOUS_TAG" > "$CURRENT_FILE"

    TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    echo "[${TIMESTAMP}] ROLLBACK SUCCESS: Restored ${PREVIOUS_TAG} (Replaced failing ${CURRENT_TAG})" >> "$HISTORY_LOG"

    echo -e "\n${GREEN}================================================================================${NC}"
    echo -e "${GREEN}>>> ROLLBACK SUCCESSFUL: Restored application version ${PREVIOUS_TAG} <<<${NC}"
    echo -e "${GREEN}================================================================================${NC}"
    exit 0
else
    echo -e "\n${RED}================================================================================${NC}"
    echo -e "${RED}>>> ROLLBACK FAILED: Application did not recover to healthy state within ${TIMEOUT}s. <<<${NC}"
    echo -e "${RED}================================================================================${NC}"
    docker compose -f "$COMPOSE_FILE" logs --tail 40 app || true
    exit 1
fi
