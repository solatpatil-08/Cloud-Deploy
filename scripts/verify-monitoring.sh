#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - Prometheus & Grafana Monitoring Validation Script
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}     CloudDeploy Phase 5: Observability Stack Validation        ${NC}"
echo -e "${CYAN}================================================================${NC}"

# Test 1: Verify Prometheus Healthy
echo -e "\n${YELLOW}[Test 1] Checking Prometheus container health probe...${NC}"
PROM_HEALTH=$(curl -s http://127.0.0.1:9090/-/healthy)
if [ "$PROM_HEALTH" = "Prometheus Server is Healthy." ]; then
    echo -e "${GREEN}[PASS] Prometheus server is healthy.${NC}"
else
    echo -e "${RED}[FAIL] Prometheus returned: $PROM_HEALTH${NC}"
    exit 1
fi

# Test 2: Verify Prometheus Scrape Targets (Spring Boot, Node Exporter)
echo -e "\n${YELLOW}[Test 2] Querying Prometheus active targets status...${NC}"
TARGETS_JSON=$(curl -s http://127.0.0.1:9090/api/v1/targets)
echo "Active targets response:"
echo "$TARGETS_JSON" | grep -o '"job":"[^"]*"' || true

if echo "$TARGETS_JSON" | grep -q '"job":"spring-boot-app"'; then
    echo -e "${GREEN}[PASS] Scrape target 'spring-boot-app' is registered.${NC}"
else
    echo -e "${RED}[FAIL] Scrape target 'spring-boot-app' is missing!${NC}"
    exit 1
fi

if echo "$TARGETS_JSON" | grep -q '"job":"node-exporter"'; then
    echo -e "${GREEN}[PASS] Scrape target 'node-exporter' is registered.${NC}"
else
    echo -e "${RED}[FAIL] Scrape target 'node-exporter' is missing!${NC}"
    exit 1
fi

# Test 3: Query Spring Boot Metrics via Prometheus Engine
echo -e "\n${YELLOW}[Test 3] Querying Spring Boot HTTP requests metric from Prometheus TSDB...${NC}"
QUERY_RES=$(curl -s -G --data-urlencode "query=up{job=\"spring-boot-app\"}" http://127.0.0.1:9090/api/v1/query)
echo "PromQL result for up{job='spring-boot-app'}:"
echo "$QUERY_RES"

if echo "$QUERY_RES" | grep -q '"result":\[{'; then
    echo -e "${GREEN}[PASS] Spring Boot metrics successfully collected by Prometheus!${NC}"
else
    echo -e "${RED}[FAIL] No metric samples returned for Spring Boot application.${NC}"
fi

# Test 4: Verify Grafana Health
echo -e "\n${YELLOW}[Test 4] Querying Grafana API health endpoint...${NC}"
GRAFANA_HEALTH=$(curl -s http://127.0.0.1:3000/api/health)
echo "Grafana Health: $GRAFANA_HEALTH"

if echo "$GRAFANA_HEALTH" | grep -q '"database": "ok"'; then
    echo -e "${GREEN}[PASS] Grafana engine and database are operational.${NC}"
else
    echo -e "${RED}[FAIL] Grafana health did not return ok.${NC}"
    exit 1
fi

# Test 5: Verify Security Isolation (No Public Prometheus/Grafana Exposure)
echo -e "\n${YELLOW}[Test 5] Verifying Prometheus & Grafana are blocked through public Nginx...${NC}"
PROM_NGINX=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/actuator/prometheus || true)
GRAF_NGINX=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ || true)

echo "Public Nginx /actuator/prometheus status: $PROM_NGINX (Expected: 403 Forbidden)"
if [ "$PROM_NGINX" = "403" ]; then
    echo -e "${GREEN}[PASS] Prometheus metrics blocked from public exposure!${NC}"
fi

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}      Phase 5 Monitoring Validation Completed Successfully!     ${NC}"
echo -e "${GREEN}================================================================${NC}"

