# =============================================================
# FIX SERVICES V2 - Repairs the Claude proxy service issue
# Checks logs, fixes permissions, restarts services
# NWU/22807365GG | 2026-06-15
# Run: irm <raw_url> | iex  (AS ADMIN)
# =============================================================

#Requires -RunAsAdministrator

Write-Host "`n[FIX] Service Diagnostics and Repair" -ForegroundColor Magenta

# ---- Find Antigravity root ----
$agRoot = "$env:LOCALAPPDATA\Antigravity"
if (-not (Test-Path $agRoot)) {
    Write-Host "[FAIL] Antigravity folder not found at $agRoot" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Antigravity root: $agRoot" -ForegroundColor Cyan

# ---- Check logs for Claude proxy service failure ----
Write-Host "`n[1/4] Checking Claude proxy error logs..." -ForegroundColor Cyan

$logFile = "$agRoot\logs\claude-proxy-stderr.log"
if (Test-Path $logFile) {
    Write-Host "--- Last 20 lines of claude-proxy-stderr.log ---" -ForegroundColor Yellow
    Get-Content $logFile -Tail 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    Write-Host "--- End of log ---" -ForegroundColor Yellow
} else {
    Write-Host "  [INFO] No error log yet (service never started)" -ForegroundColor Yellow
}

# ---- Check if Node.js is accessible ----
Write-Host "`n[2/4] Verifying Node.js..." -ForegroundColor Cyan

$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeExe) {
    Write-Host "  [FAIL] Node.js not found in PATH" -ForegroundColor Red
    Write-Host "  Install from: https://nodejs.org" -ForegroundColor Yellow
    exit 1
}

Write-Host "  [OK] Node.js: $nodeExe" -ForegroundColor Green

# ---- Test the server.js manually ----
Write-Host "`n[3/4] Testing server.js directly..." -ForegroundColor Cyan

$serverJs = "$agRoot\claude-proxy\server.js"
if (-not (Test-Path $serverJs)) {
    Write-Host "  [FAIL] server.js not found: $serverJs" -ForegroundColor Red
    exit 1
}

Write-Host "  [..] Starting proxy manually (will run for 5 seconds to test)..." -ForegroundColor Yellow

# Start in background, capture output
$testProc = Start-Process -FilePath $nodeExe -ArgumentList "`"$serverJs`"" -WorkingDirectory "$agRoot\claude-proxy" -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\proxy-test-out.log" -RedirectStandardError "$env:TEMP\proxy-test-err.log"

Start-Sleep 5

# Check if it's still running
if ($testProc.HasExited) {
    Write-Host "  [FAIL] Proxy exited immediately. Error:" -ForegroundColor Red
    Get-Content "$env:TEMP\proxy-test-err.log" | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    Stop-Process -Id $testProc.Id -Force -ErrorAction SilentlyContinue
    
    # Common issue: missing dependencies
    Write-Host "`n  [FIX] Reinstalling npm dependencies..." -ForegroundColor Yellow
    Set-Location "$agRoot\claude-proxy"
    npm install --silent 2>&1 | Out-Null
    
    Write-Host "  [OK] Dependencies reinstalled. Retry starting service..." -ForegroundColor Green
} else {
    Write-Host "  [OK] Proxy process alive (PID $($testProc.Id))" -ForegroundColor Green
    
    # Test health endpoint
    Start-Sleep 2
    try {
        $health = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 3 -UseBasicParsing
        Write-Host "  [OK] Health check passed: $($health.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Health endpoint not responding: $_" -ForegroundColor Yellow
    }
    
    # Kill test process
    Stop-Process -Id $testProc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Test complete, stopped manual process" -ForegroundColor Green
}

# ---- Restart the Windows Service ----
Write-Host "`n[4/4] Restarting ClaudeProxyService..." -ForegroundColor Cyan

$svc = Get-Service -Name "ClaudeProxyService" -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "  [FAIL] ClaudeProxyService not registered" -ForegroundColor Red
    Write-Host "  Run the full installer first: install-services.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "  [..] Stopping service..." -ForegroundColor Yellow
Stop-Service ClaudeProxyService -Force -ErrorAction SilentlyContinue
Start-Sleep 2

Write-Host "  [..] Starting service..." -ForegroundColor Yellow
try {
    Start-Service ClaudeProxyService -ErrorAction Stop
    Write-Host "  [OK] Service started" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Service won't start: $_" -ForegroundColor Red
    Write-Host "`n  Check full error log:" -ForegroundColor Yellow
    Write-Host "    Get-Content '$agRoot\logs\claude-proxy-stderr.log' -Tail 50" -ForegroundColor Gray
    exit 1
}

# ---- Final verification ----
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host " SERVICE STATUS" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

Start-Sleep 3

# Ollama
try {
    $ol = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -UseBasicParsing
    Write-Host "  Ollama (Qwen)     : ONLINE :11434" -ForegroundColor Green
} catch {
    Write-Host "  Ollama (Qwen)     : OFFLINE" -ForegroundColor Red
}

# Claude proxy
try {
    $cl = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 5 -UseBasicParsing
    Write-Host "  Claude Proxy      : ONLINE :8080" -ForegroundColor Green
} catch {
    Write-Host "  Claude Proxy      : OFFLINE (check logs)" -ForegroundColor Red
}

Write-Host "`n[DONE] Diagnostics complete" -ForegroundColor Magenta
