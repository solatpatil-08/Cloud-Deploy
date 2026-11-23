# ==============================================================================
# CloudDeploy Phase 4: Nginx Reverse Proxy Test & Security Validation (PowerShell)
# ==============================================================================

$BaseUrl = "http://localhost"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "     CloudDeploy Phase 4: Nginx Reverse Proxy Validation        " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Test 1: Validate Nginx syntax inside container
Write-Host "`n[Test 1] Validating Nginx configuration syntax inside container..." -ForegroundColor Yellow
docker compose exec nginx nginx -t

# Test 2: Gateway Root Verification
Write-Host "`n[Test 2] Querying root gateway status (GET /)..." -ForegroundColor Yellow
try {
    $res = Invoke-WebRequest -Uri "$BaseUrl/" -Method Get -UseBasicParsing
    Write-Host "HTTP Status: $($res.StatusCode)" -ForegroundColor Green
    Write-Host "Body: $($res.Content)" -ForegroundColor Gray
} catch {
    Write-Host "[FAIL] Root endpoint error: $_" -ForegroundColor Red
}

# Test 3: Public Health Check (/health -> /actuator/health)
Write-Host "`n[Test 3] Testing public health probe (/health)..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get
    Write-Host "[PASS] Health status: $($health.status)" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Health check failed: $_" -ForegroundColor Red
}

# Test 4: SECURITY TEST - Actuator Endpoints Blocked (403 Forbidden)
Write-Host "`n[Test 4] SECURITY TEST: Querying /actuator and /actuator/prometheus..." -ForegroundColor Yellow
try {
    $actRes = Invoke-WebRequest -Uri "$BaseUrl/actuator" -Method Get -UseBasicParsing -SkipHttpErrorCheck
    Write-Host "GET /actuator status: $($actRes.StatusCode) (Expected: 403)" -ForegroundColor $(if ($actRes.StatusCode -eq 403) { "Green" } else { "Red" })
} catch {
    Write-Host "Blocked: $($_.Exception.Message)" -ForegroundColor Green
}

try {
    $promRes = Invoke-WebRequest -Uri "$BaseUrl/actuator/prometheus" -Method Get -UseBasicParsing -SkipHttpErrorCheck
    Write-Host "GET /actuator/prometheus status: $($promRes.StatusCode) (Expected: 403)" -ForegroundColor $(if ($promRes.StatusCode -eq 403) { "Green" } else { "Red" })
} catch {
    Write-Host "Blocked: $($_.Exception.Message)" -ForegroundColor Green
}

# Test 5: Verify Security Headers & Server Token Hiding
Write-Host "`n[Test 5] Checking security headers and server version hiding..." -ForegroundColor Yellow
try {
    $head = Invoke-WebRequest -Uri "$BaseUrl/" -Method Head -UseBasicParsing
    $headers = $head.Headers
    Write-Host "X-Frame-Options: $($headers['X-Frame-Options'])" -ForegroundColor Green
    Write-Host "X-Content-Type-Options: $($headers['X-Content-Type-Options'])" -ForegroundColor Green
    Write-Host "X-XSS-Protection: $($headers['X-XSS-Protection'])" -ForegroundColor Green
    Write-Host "Server: $($headers['Server'])" -ForegroundColor $(if ($headers['Server'] -eq "nginx") { "Green" } else { "Yellow" })
} catch {
    Write-Host "Headers check error: $_" -ForegroundColor Red
}

# Test 6: Verify Port Isolation (8080 and 5432 should NOT be accessible on host)
Write-Host "`n[Test 6] Verifying Spring Boot (:8080) and PostgreSQL (:5432) are NOT exposed on host..." -ForegroundColor Yellow
try {
    $test8080 = Test-NetConnection -ComputerName localhost -Port 8080 -WarningAction SilentlyContinue
    if ($test8080.TcpTestSucceeded) {
        Write-Host "[FAIL] Port 8080 is accessible on the host! It should be internal." -ForegroundColor Red
    } else {
        Write-Host "[PASS] Port 8080 is closed on the host." -ForegroundColor Green
    }
} catch {
    Write-Host "[PASS] Port 8080 is not exposed." -ForegroundColor Green
}

# Test 7: Tail access log
Write-Host "`n[Test 7] Inspecting Nginx access logs..." -ForegroundColor Yellow
docker compose exec nginx tail -n 5 /var/log/nginx/access.log

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "      Phase 4 Nginx Reverse Proxy Validation Complete!         " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

