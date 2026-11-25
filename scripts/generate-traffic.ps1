# ==============================================================================
# CloudDeploy - Synthetic Traffic Generator (PowerShell)
# ==============================================================================

param (
    [int]$Cycles = 10
)

$BaseUrl = "http://localhost"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    CloudDeploy Traffic Generator: Sending $Cycles traffic bursts...    " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

for ($i = 1; $i -le $Cycles; $i++) {
    $randId = Get-Random -Minimum 100 -Maximum 99999
    $username = "ps_user_$randId"
    $email = "ps_user_$randId@example.com"
    $password = "Password123!"

    Write-Host "`n[Cycle $i/$Cycles] Simulating user workflow: $username" -ForegroundColor Yellow

    # 1. Register User
    $regBody = @{ username = $username; email = $email; password = $password } | ConvertTo-Json
    try {
        $regRes = Invoke-WebRequest -Uri "$BaseUrl/api/v1/auth/register" -Method Post -Body $regBody -ContentType "application/json" -UseBasicParsing
        Write-Host "  -> Register: HTTP $($regRes.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  -> Register: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # 2. Login User
    $loginBody = @{ usernameOrEmail = $username; password = $password } | ConvertTo-Json
    try {
        $loginRes = Invoke-RestMethod -Uri "$BaseUrl/api/v1/auth/login" -Method Post -Body $loginBody -ContentType "application/json"
        $token = $loginRes.token
        Write-Host "  -> Login: HTTP 200 (Token acquired)" -ForegroundColor Green

        # 3. Create Task
        $taskBody = @{ title = "Task $randId"; description = "Observability task"; priority = "HIGH"; status = "TODO" } | ConvertTo-Json
        $headers = @{ Authorization = "Bearer $token" }
        $taskRes = Invoke-WebRequest -Uri "$BaseUrl/api/v1/tasks" -Method Post -Body $taskBody -Headers $headers -ContentType "application/json" -UseBasicParsing
        Write-Host "  -> Create Task: HTTP $($taskRes.StatusCode)" -ForegroundColor Green

        # 4. List Tasks
        $listRes = Invoke-WebRequest -Uri "$BaseUrl/api/v1/tasks" -Method Get -Headers $headers -UseBasicParsing
        Write-Host "  -> List Tasks: HTTP $($listRes.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  -> Task operations: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # 5. Public Health Probe
    try {
        $hRes = Invoke-WebRequest -Uri "$BaseUrl/health" -Method Get -UseBasicParsing
        Write-Host "  -> Health probe: HTTP $($hRes.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  -> Health probe: $($_.Exception.Message)" -ForegroundColor Gray
    }

    Start-Sleep -Seconds 1
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "    Traffic simulation completed! Check Prometheus and Grafana.  " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

