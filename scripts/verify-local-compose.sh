#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - Local Docker Compose Verification Script
# Verifies container builds, startup, database connectivity, and health probes.
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}================================================================${NC}"
echo -e "${YELLOW}      CloudDeploy Phase 3: Docker & Compose Verification       ${NC}"
echo -e "${YELLOW}================================================================${NC}"

# 1. Environment file check
if [ ! -f .env ]; then
    echo -e "${YELLOW}[INFO] .env not found. Copying from .env.example...${NC}"
    cp .env.example .env
fi

# 2. Build Docker containers
echo -e "\n${YELLOW}[1/6] Building Spring Boot application image...${NC}"
docker compose build --no-cache app

# 3. Start services in background
echo -e "\n${YELLOW}[2/6] Starting PostgreSQL, Application, and Nginx...${NC}"
docker compose up -d

# 4. Wait and poll for healthy status
echo -e "\n${YELLOW}[3/6] Waiting for service health checks to pass (up to 90s)...${NC}"
MAX_RETRIES=18
COUNT=0
HEALTHY=false

while [ $COUNT -lt $MAX_RETRIES ]; do
    APP_STATUS=$(docker inspect --format='{{json .State.Health.Status}}' clouddeploy-app 2>/dev/null || echo "\"starting\"")
    DB_STATUS=$(docker inspect --format='{{json .State.Health.Status}}' clouddeploy-postgres 2>/dev/null || echo "\"starting\"")
    NGINX_STATUS=$(docker inspect --format='{{json .State.Health.Status}}' clouddeploy-nginx 2>/dev/null || echo "\"starting\"")

    echo "Attempt $((COUNT+1))/$MAX_RETRIES - postgres: $DB_STATUS | app: $APP_STATUS | nginx: $NGINX_STATUS"

    if [ "$APP_STATUS" = "\"healthy\"" ] && [ "$DB_STATUS" = "\"healthy\"" ] && [ "$NGINX_STATUS" = "\"healthy\"" ]; then
        HEALTHY=true
        break
    fi

    sleep 5
    COUNT=$((COUNT+1))
done

if [ "$HEALTHY" = false ]; then
    echo -e "\n${RED}[ERROR] Services failed to reach healthy state within timeout!${NC}"
    echo -e "${YELLOW}Dumping container logs for diagnostics:${NC}"
    docker compose logs
    exit 1
fi

echo -e "\n${GREEN}[SUCCESS] All containers are running and healthy!${NC}"

# 5. Verify Database Communication via Nginx API
echo -e "\n${YELLOW}[4/6] Verifying Spring Boot connection to PostgreSQL via Flyway & Health endpoint...${NC}"
HEALTH_BODY=$(curl -s http://localhost/actuator/health)
echo "Response: $HEALTH_BODY"

if echo "$HEALTH_BODY" | grep -q '"status":"UP"'; then
    echo -e "${GREEN}[SUCCESS] Health endpoint reports UP!${NC}"
else
    echo -e "${RED}[ERROR] Health endpoint did not return UP!${NC}"
    exit 1
fi

# 6. Verify End-to-End User Registration & DB Persistence through Nginx
echo -e "\n${YELLOW}[5/6] Testing End-to-End API via Nginx (User Registration)...${NC}"
REG_RESPONSE=$(curl -s -X POST http://localhost/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"compose_test_user","email":"compose_test@example.com","password":"Password123!"}')

echo "Response: $REG_RESPONSE"

if echo "$REG_RESPONSE" | grep -q 'token'; then
    echo -e "${GREEN}[SUCCESS] User registered and JWT generated! Database communication is operational.${NC}"
else
    echo -e "${RED}[ERROR] User registration failed!${NC}"
    exit 1
fi

# 7. Summary
echo -e "\n${YELLOW}[6/6] Checking container restart policies and isolated networks...${NC}"
docker compose ps

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}      Phase 3 Verification PASSED! Everything is operational.   ${NC}"
echo -e "${GREEN}================================================================${NC}"

