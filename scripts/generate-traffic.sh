#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - Synthetic Traffic Generator for Observability Verification
# Generates realistic API calls (user register, login, tasks CRUD, 404, 401)
# to populate Prometheus metrics and Grafana dashboards.
# ==============================================================================

set -euo pipefail

BASE_URL="http://localhost"
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

NUM_CYCLES=${1:-10}

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}    CloudDeploy Traffic Generator: Sending $NUM_CYCLES traffic bursts...    ${NC}"
echo -e "${CYAN}================================================================${NC}"

for i in $(seq 1 "$NUM_CYCLES"); do
    RAND_ID=$((RANDOM % 10000 + 100))
    USERNAME="user_${RAND_ID}"
    EMAIL="user_${RAND_ID}@example.com"
    PASSWORD="Password123!"

    echo -e "\n${YELLOW}[Cycle $i/$NUM_CYCLES] Simulating user workflow: $USERNAME${NC}"

    # 1. Register User (201 Created)
    curl -s -o /dev/null -w "  -> Register: HTTP %{http_code}\n" -X POST "$BASE_URL/api/v1/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"

    # 2. Login User (200 OK)
    LOGIN_RES=$(curl -s -X POST "$BASE_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"usernameOrEmail\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")
    
    TOKEN=$(echo "$LOGIN_RES" | grep -o '"token":"[^"]*' | cut -d'"' -f4 || echo "")

    if [ -n "$TOKEN" ]; then
        echo -e "  -> Login: HTTP 200 (Token acquired)"

        # 3. Create Tasks (201 Created)
        curl -s -o /dev/null -w "  -> Create Task 1: HTTP %{http_code}\n" -X POST "$BASE_URL/api/v1/tasks" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $TOKEN" \
            -d "{\"title\":\"Task A-$RAND_ID\",\"description\":\"Test task\",\"priority\":\"HIGH\",\"status\":\"TODO\"}"

        curl -s -o /dev/null -w "  -> Create Task 2: HTTP %{http_code}\n" -X POST "$BASE_URL/api/v1/tasks" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $TOKEN" \
            -d "{\"title\":\"Task B-$RAND_ID\",\"description\":\"Another task\",\"priority\":\"MEDIUM\",\"status\":\"IN_PROGRESS\"}"

        # 4. List Tasks with Filters & Sorting (200 OK)
        curl -s -o /dev/null -w "  -> List Tasks: HTTP %{http_code}\n" -X GET "$BASE_URL/api/v1/tasks?status=TODO&sortBy=createdAt&sortDir=desc" \
            -H "Authorization: Bearer $TOKEN"
    fi

    # 5. Simulate 401 Unauthorized
    curl -s -o /dev/null -w "  -> Bad Auth: HTTP %{http_code} (Expected 401)\n" -X POST "$BASE_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"usernameOrEmail\":\"invalid_user\",\"password\":\"WrongPassword!\"}"

    # 6. Simulate 404 Not Found
    curl -s -o /dev/null -w "  -> Non-existent route: HTTP %{http_code} (Expected 404)\n" -X GET "$BASE_URL/api/non-existent-endpoint"

    # 7. Public Health Check (200 OK)
    curl -s -o /dev/null -w "  -> Health probe: HTTP %{http_code}\n" -X GET "$BASE_URL/health"

    sleep 1
done

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}    Traffic simulation completed! Check Prometheus and Grafana.  ${NC}"
echo -e "${GREEN}================================================================${NC}"

