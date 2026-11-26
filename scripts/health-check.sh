#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - Full-Stack Health Check Automation Script
# Verifies container health, system services, and HTTP endpoint availability.
#
# Checks performed:
# 1. Docker daemon service
# 2. PostgreSQL container (clouddeploy-prod-postgres)
# 3. Spring Boot API container (clouddeploy-prod-app)
# 4. Nginx reverse proxy container (clouddeploy-prod-nginx)
# 5. Prometheus monitoring container (clouddeploy-prod-prometheus)
# 6. Grafana dashboard container (clouddeploy-prod-grafana)
# 7. Public health endpoint (http://localhost/health)
# 8. Actuator security check (http://localhost/actuator blocked with HTTP 403)
#
# Exit Codes:
#   0 - All components healthy
#   1 - One or more components degraded or down
# ==============================================================================

set -euo pipefail

QUIET=false
if [ "${1:-}" == "--quiet" ] || [ "${1:-}" == "-q" ]; then
    QUIET=true
fi

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    if [ "$QUIET" = false ]; then
        echo -e "$1"
    fi
}

log "${CYAN}================================================================================${NC}"
log "${CYAN}                  CloudDeploy Production Health Check Audit                     ${NC}"
log "${CYAN}                  Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')                   ${NC}"
log "${CYAN}================================================================================${NC}"

FAILED=0

# Helper: check container state and Docker health status
check_container() {
    local name="$1"
    local expected_status="${2:-healthy}"

    local container_id
    container_id=$(docker ps -aq -f "name=^/${name}$" || true)

    if [ -z "$container_id" ]; then
        log "  Container ${name}: ${RED}[FAIL] Container does not exist${NC}"
        FAILED=$((FAILED + 1))
        return
    fi

    local state
    local health
    state=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id" 2>/dev/null || echo "none")

    if [ "$state" != "running" ]; then
        log "  Container ${name}: ${RED}[FAIL] State is ${state} (expected: running)${NC}"
        FAILED=$((FAILED + 1))
        return
    fi

    if [ "$health" != "none" ] && [ "$health" != "$expected_status" ]; then
        log "  Container ${name}: ${RED}[FAIL] Health is ${health} (expected: ${expected_status})${NC}"
        FAILED=$((FAILED + 1))
        return
    fi

    if [ "$health" = "none" ]; then
        log "  Container ${name}: ${GREEN}[PASS] Running (no healthcheck defined)${NC}"
    else
        log "  Container ${name}: ${GREEN}[PASS] Running & Healthy${NC}"
    fi
}

# 1. Docker Daemon Check
log "\n${YELLOW}[1/4] Checking Docker Daemon Service...${NC}"
if systemctl is-active --quiet docker 2>/dev/null || docker info >/dev/null 2>&1; then
    log "  Docker Service: ${GREEN}[PASS] Active & Running${NC}"
else
    log "  Docker Service: ${RED}[FAIL] Inactive or not responding${NC}"
    FAILED=$((FAILED + 1))
fi

# 2. Production Container Audits
log "\n${YELLOW}[2/4] Checking Production Containers...${NC}"
check_container "clouddeploy-prod-postgres" "healthy"
check_container "clouddeploy-prod-app" "healthy"
check_container "clouddeploy-prod-nginx" "healthy"
check_container "clouddeploy-prod-prometheus" "healthy"
check_container "clouddeploy-prod-grafana" "healthy"

# Optional: node-exporter check
if docker ps -aq -f "name=^/clouddeploy-prod-node-exporter$" | grep -q .; then
    check_container "clouddeploy-prod-node-exporter" "none"
fi

# 3. Application Health Probe (/health)
log "\n${YELLOW}[3/4] Testing Application Public Health Endpoint...${NC}"
HEALTH_RES=$(curl -s -m 5 "http://localhost/health" 2>/dev/null || echo "{}")
if echo "$HEALTH_RES" | grep -q '"status":"UP"'; then
    log "  HTTP GET http://localhost/health: ${GREEN}[PASS] Status: UP${NC}"
else
    log "  HTTP GET http://localhost/health: ${RED}[FAIL] Response: ${HEALTH_RES}${NC}"
    FAILED=$((FAILED + 1))
fi

# 4. Security Verification (Actuator endpoint blocked from public ingress)
log "\n${YELLOW}[4/4] Verifying Actuator Security Rules...${NC}"
ACTUATOR_CODE=$(curl -s -m 5 -o /dev/null -w "%{http_code}" "http://localhost/actuator" 2>/dev/null || echo "000")
if [ "$ACTUATOR_CODE" = "403" ]; then
    log "  Public Actuator Access: ${GREEN}[PASS] Blocked with HTTP 403 Forbidden${NC}"
else
    log "  Public Actuator Access: ${RED}[FAIL] Unexpected HTTP code: ${ACTUATOR_CODE} (Expected: 403)${NC}"
    FAILED=$((FAILED + 1))
fi

# Final Summary
log "\n${CYAN}================================================================================${NC}"
if [ "$FAILED" -eq 0 ]; then
    log "${GREEN}>>> HEALTH CHECK AUDIT PASSED: All services and endpoints are operational. <<<${NC}"
    log "${CYAN}================================================================================${NC}"
    exit 0
else
    log "${RED}>>> HEALTH CHECK AUDIT FAILED: ${FAILED} check(s) reported errors. <<<${NC}"
    log "${CYAN}================================================================================${NC}"
    exit 1
fi
