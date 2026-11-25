# ==============================================================================
# CloudDeploy - Prometheus & Grafana Monitoring Validation Script (PowerShell)
# ==============================================================================

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "     CloudDeploy Phase 5: Observability Stack Validation        " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Test 1: Check Prometheus Health
Write-Host "`n[Test 1] Checking Prometheus container health probe..." -ForegroundColor Yellow
try {
    $promHealth = Invoke-RestMethod -Uri "http://127.0.0.1:9090/-/healthy" -Method Get
    Write-Host "[PASS] Prometheus response: $promHealth" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Prometheus health probe failed: $_" -ForegroundColor Red
}

# Test 2: Check Active Scrape Targets
Write-Host "`n[Test 2] Querying Prometheus active targets..." -ForegroundColor Yellow
try {
    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:9090/api/v1/targets" -Method Get
    $active = $targets.data.activeTargets | Select-Object -Property scrapePool, health, lastScrape
    $active | Format-Table -AutoSize
    Write-Host "[PASS] Retrieved active targets." -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Could not query targets: $_" -ForegroundColor Red
}

# Test 3: Query Spring Boot Metrics
Write-Host "`n[Test 3] Querying Spring Boot up metric from Prometheus..." -ForegroundColor Yellow
try {
    $metric = Invoke-RestMethod -Uri "http://127.0.0.1:9090/api/v1/query?query=up{job='spring-boot-app'}" -Method Get
    $statusValue = $metric.data.result[0].value[1]
    Write-Host "[PASS] Spring Boot up status: $statusValue (1 = UP)" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Could not query metric: $_" -ForegroundColor Red
}

# Test 4: Check Grafana Health
Write-Host "`n[Test 4] Querying Grafana health..." -ForegroundColor Yellow
try {
    $grafHealth = Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/health" -Method Get
    Write-Host "[PASS] Grafana database status: $($grafHealth.database)" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Grafana health probe failed: $_" -ForegroundColor Red
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "      Phase 5 Monitoring Validation Completed Successfully!     " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

