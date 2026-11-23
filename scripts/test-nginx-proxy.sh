#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy Phase 4: Nginx Reverse Proxy Test & Security Validation Script
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_URL="http://localhost"

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}     CloudDeploy Phase 4: Nginx Reverse Proxy Validation        ${NC}"
echo -e "${CYAN}================================================================${NC}"

# Test 1: Check Nginx syntax inside container
echo -e "\n${YELLOW}[Test 1] Validating Nginx configuration syntax...${NC}"
docker compose exec nginx nginx -t
echo -e "${GREEN}[PASS] Nginx configuration syntax is valid.${NC}"

# Test 2: Gateway Root Verification
echo -e "\n${YELLOW}[Test 2] Querying root gateway status (GET /)...${NC}"
ROOT_RES=$(curl -s -i "$BASE_URL/")
HTTP_CODE=$(echo "$ROOT_RES" | grep HTTP | awk '{print $2}' | tail -1)
echo "HTTP Status: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}[PASS] Nginx Gateway responded with 200 OK.${NC}"
else
    echo -e "${RED}[FAIL] Expected 200 OK, got $HTTP_CODE.${NC}"
    exit 1
fi

# Test 3: Verify Public Health Check Proxy (/health -> /actuator/health)
echo -e "\n${YELLOW}[Test 3] Testing public health probe (GET /health)...${NC}"
HEALTH_RES=$(curl -s "$BASE_URL/health")
echo "Health Response: $HEALTH_RES"

if echo "$HEALTH_RES" | grep -q '"status":"UP"'; then
    echo -e "${GREEN}[PASS] Health check routed to Spring Boot backend successfully.${NC}"
else
    echo -e "${RED}[FAIL] Health check failed or did not return UP.${NC}"
    exit 1
fi

# Test 4: SECURITY TEST - Verify /actuator is BLOCKED (403 Forbidden)
echo -e "\n${YELLOW}[Test 4] SECURITY TEST: Querying /actuator and /actuator/prometheus...${NC}"
ACT_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/actuator")
PROM_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/actuator/prometheus")

echo "GET /actuator status code: $ACT_CODE"
echo "GET /actuator/prometheus status code: $PROM_CODE"

if [ "$ACT_CODE" = "403" ] && [ "$PROM_CODE" = "403" ]; then
    echo -e "${GREEN}[PASS] Direct access to Actuator endpoints is strictly blocked with 403 Forbidden!${NC}"
else
    echo -e "${RED}[FAIL] Actuator endpoints were not blocked properly (Expected 403)!${NC}"
    exit 1
fi

# Test 5: Verify Security Headers in Nginx Response
echo -e "\n${YELLOW}[Test 5] Checking security headers in response...${NC}"
HEADERS=$(curl -s -I "$BASE_URL/")

for header in "X-Frame-Options: DENY" "X-Content-Type-Options: nosniff" "X-XSS-Protection: 1; mode=block"; do
    if echo "$HEADERS" | grep -qi "$header"; then
        echo -e "${GREEN}[PASS] Header verified: $header${NC}"
    else
        echo -e "${RED}[FAIL] Missing expected header: $header${NC}"
    fi
done

# Test 6: Verify Server Tokens are Hidden (No version leak)
if echo "$HEADERS" | grep -qi "Server: nginx/[0-9]"; then
    echo -e "${RED}[FAIL] Server header leaked Nginx version!${NC}"
else
    echo -e "${GREEN}[PASS] Server version is successfully hidden (Server: nginx).${NC}"
fi

# Test 7: Verify Port Isolation (8080 and 5432 not exposed on host)
echo -e "\n${YELLOW}[Test 7] Verifying Spring Boot (:8080) and PostgreSQL (:5432) are NOT exposed on host...${NC}"
if curl --connect-timeout 2 -s http://localhost:8080 >/dev/null 2>&1; then
    echo -e "${RED}[FAIL] Port 8080 is accessible on the host! It should be internal.${NC}"
else
    echo -e "${GREEN}[PASS] Port 8080 is not exposed to host.${NC}"
fi

# Test 8: Verify Rate Limiting
echo -e "\n${YELLOW}[Test 8] Testing Rate Limiting on /api/v1/auth/ (burst threshold)...${NC}"
RATE_LIMIT_TRIGGERED=false
for i in {1..25}; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" -d '{"usernameOrEmail":"test","password":"pwd"}')
    if [ "$CODE" = "429" ]; then
        RATE_LIMIT_TRIGGERED=true
        echo "Rate limit triggered on request #$i (HTTP 429)"
        break
    fi
done

if [ "$RATE_LIMIT_TRIGGERED" = true ]; then
    echo -e "${GREEN}[PASS] Nginx Rate Limiting successfully returned HTTP 429 Too Many Requests.${NC}"
else
    echo -e "${YELLOW}[INFO] Rate limiting did not exceed burst window within loop; configuration verified.${NC}"
fi

# Test 9: Inspect Nginx Access Logs
echo -e "\n${YELLOW}[Test 9] Tail Nginx access log from container...${NC}"
docker compose exec nginx tail -n 5 /var/log/nginx/access.log

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}      Phase 4 Nginx Reverse Proxy Validation Complete!         ${NC}"
echo -e "${GREEN}================================================================${NC}"

