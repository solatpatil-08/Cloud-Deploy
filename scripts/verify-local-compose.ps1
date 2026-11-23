# ==============================================================================
# CloudDeploy - Local Docker Compose Verification Script (PowerShell)
# ==============================================================================

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "      CloudDeploy Phase 3: Docker & Compose Verification       " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Environment file check
if (-not (Test-Path .env)) {
    Write-Host "[INFO] .env not found. Copying from .env.example..." -ForegroundColor Yellow
    Copy-Item .env.example .env
}

# 2. Build Docker containers
Write-Host "`n[1/6] Building Spring Boot application image..." -ForegroundColor Yellow
docker compose build --no-cache app

# 3. Start services
Write-Host "`n[2/6] Starting PostgreSQL, Application, and Nginx..." -ForegroundColor Yellow
docker compose up -d

# 4. Wait for health checks
Write-Host "`n[3/6] Waiting for service health checks to pass..." -ForegroundColor Yellow
$maxRetries = 18
$count = 0
$healthy = $false

while ($count -lt $maxRetries) {
    $appStatus = docker inspect --format='{{json .State.Health.Status}}' clouddeploy-app 2>$null
    $dbStatus = docker inspect --format='{{json .State.Health.Status}}' clouddeploy-postgres 2>$null
    $nginxStatus = docker inspect --format='{{json .State.Health.Status}}' clouddeploy-nginx 2>$null

    Write-Host "Attempt ($($count+1)/$maxRetries) - postgres: $dbStatus | app: $appStatus | nginx: $nginxStatus"

    if ($appStatus -eq '"healthy"' -and $dbStatus -eq '"healthy"' -and $nginxStatus -eq '"healthy"') {
        $healthy = $true
        break
    }

    Start-Sleep -Seconds 5
    $count++
}

if (-not $healthy) {
    Write-Host "`n[ERROR] Services failed to reach healthy state within timeout!" -ForegroundColor Red
    docker compose logs
    exit 1
}

Write-Host "`n[SUCCESS] All containers are healthy!" -ForegroundColor Green

# 5. Check Health Endpoint
Write-Host "`n[4/6] Querying /actuator/health via Nginx..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost/actuator/health" -Method Get
    Write-Host "Health Status: $($health.status)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to query health endpoint: $_" -ForegroundColor Red
    exit 1
}

# 6. Check Auth Endpoint
Write-Host "`n[5/6] Testing API user registration through Nginx..." -ForegroundColor Yellow
$body = @{
    username = "ps_test_user"
    email = "ps_test@example.com"
    password = "Password123!"
} | ConvertTo-Json

try {
    $res = Invoke-RestMethod -Uri "http://localhost/api/v1/auth/register" -Method Post -Body $body -ContentType "application/json"
    Write-Host "[SUCCESS] User created! JWT Token received: $($res.token.Substring(0, 20))..." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Registration failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n[6/6] Docker Compose Services:" -ForegroundColor Yellow
docker compose ps

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "      Phase 3 Verification PASSED! Everything is operational.   " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

