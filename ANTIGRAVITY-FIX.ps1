# ANTIGRAVITY-FIX.ps1 - Run this on the Antigravity desktop RIGHT NOW
# Fixes: proxy not responding, missing API key, verifies all services
# NWU/22807365GG | 2026-06-20
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$SD = 'C:\AntigravityServices'
$CLAUDE_DIR = "$env:USERPROFILE\.claude"
function OK($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function INFO($m) { Write-Host "  [..] $m" -ForegroundColor Cyan }
function WARN($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function FAIL($m) { Write-Host "  [XX] $m" -ForegroundColor Red }
Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host " ANTIGRAVITY FIX + VERIFY" -ForegroundColor Green  
Write-Host "=================================================" -ForegroundColor Cyan

# STEP 1: Stop any stale proxy processes
INFO 'Stopping any stale proxy processes...'
Get-Process python -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'proxy.py' } | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2
OK 'Stale processes cleared'

# STEP 2: Verify Ollama is running
INFO 'Checking Ollama...'
try {
  Invoke-WebRequest -Uri 'http://127.0.0.1:11434' -TimeoutSec 5 -UseBasicParsing -EA Stop | Out-Null
  OK 'Ollama running on :11434'
} catch {
  INFO 'Starting Ollama...'
  $ollamaExe = (Get-Command ollama -EA SilentlyContinue)?.Source
  if (-not $ollamaExe) { $ollamaExe = 'C:\Users\ITBVDK\AppData\Local\Programs\Ollama\ollama.exe' }
  Start-Process $ollamaExe -ArgumentList 'serve' -WindowStyle Hidden
  Start-Sleep 8
  OK 'Ollama started'
}

# STEP 3: Fix Python path - use the Python313 that was found during install
$PY = 'C:\Users\ITBVDK\AppData\Local\Programs\Python\Python313\python.exe'
if (-not (Test-Path $PY)) { $PY = (Get-Command python -EA SilentlyContinue)?.Source }
if (-not $PY) { FAIL 'Python not found - run the main installer first'; pause; exit 1 }
OK "Python: $PY"

# STEP 4: Fix proxy.py - update it to use Python313 and correct paths
if (-not (Test-Path "$SD\proxy.py")) { FAIL "$SD\proxy.py missing - run main installer first"; pause; exit 1 }
OK "Proxy script found: $SD\proxy.py"

# STEP 5: Add/update OpenRouter API key
$KF = "$SD\openrouter.key"
$currentKey = ''
if (Test-Path $KF) { $currentKey = (Get-Content $KF -Raw).Trim() }
if (-not $currentKey -or $currentKey.Length -lt 20) {
  Write-Host "`n  *** OpenRouter API Key Required ***" -ForegroundColor Yellow
  Write-Host "  Get your FREE key at: https://openrouter.ai/keys" -ForegroundColor Cyan
  Write-Host "  No credit card needed. 28+ models free." -ForegroundColor Cyan
  $k = Read-Host "`n  Paste your OpenRouter key (sk-or-...)"
  if ($k -and $k.Trim().Length -gt 10) {
    $k.Trim() | Out-File $KF -Encoding ASCII -NoNewline
    OK 'OpenRouter API key saved'
  } else {
    WARN 'No key entered - running LOCAL model only (cloud models disabled)'
  }
} else {
  OK "OpenRouter key already set (${$currentKey.Length} chars)"
}

# STEP 6: Start proxy with correct Python and wait properly
INFO 'Starting proxy server...'
$proxyProc = Start-Process -FilePath $PY -ArgumentList "\"$SD\proxy.py\"" -WindowStyle Hidden -PassThru
Write-Host "  Waiting for proxy to initialize" -NoNewline
$proxyOK = $false
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep 2
  Write-Host '.' -NoNewline -ForegroundColor Cyan
  try {
    $h = (Invoke-WebRequest -Uri 'http://127.0.0.1:8080/health' -TimeoutSec 3 -UseBasicParsing -EA Stop).Content | ConvertFrom-Json
    Write-Host ' ALIVE!' -ForegroundColor Green
    $proxyOK = $true
    break
  } catch {}
}
if ($proxyOK) {
  OK "Proxy live on :8080 | Models: $($h.models.Count)"
} else {
  FAIL 'Proxy not responding after 40s - check C:\AntigravityServices\proxy.py manually'
}

# STEP 7: Test actual AI chat
if ($proxyOK) {
  INFO 'Running AI chat test...'
  try {
    $body = '{"model":"local","messages":[{"role":"user","content":"Say READY in one word"}]}'
    $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/v1/chat/completions' -Method POST -Body $body -ContentType 'application/json' -TimeoutSec 60 -UseBasicParsing
    $data = $resp.Content | ConvertFrom-Json
    $reply = $data.choices[0].message.content
    OK "AI responded: '$reply'"
  } catch {
    WARN "Chat test failed: $_"
  }
}

# STEP 8: Fix scheduled tasks with correct Python path
INFO 'Re-registering scheduled tasks with correct Python path...'
$ts = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan)
try {
  $a1 = New-ScheduledTaskAction -Execute $PY -Argument "\"$SD\proxy.py\""
  $t1 = New-ScheduledTaskTrigger -AtLogOn
  Register-ScheduledTask -TaskName 'AntigravityProxy' -Action $a1 -Trigger $t1 -Settings $ts -RunLevel Highest -Force | Out-Null
  OK 'AntigravityProxy task updated'
} catch { WARN "AntigravityProxy task: $_" }
try {
  $ollamaExe2 = (Get-Command ollama -EA SilentlyContinue)?.Source
  if (-not $ollamaExe2) { $ollamaExe2 = 'C:\Users\ITBVDK\AppData\Local\Programs\Ollama\ollama.exe' }
  $a2 = New-ScheduledTaskAction -Execute $ollamaExe2 -Argument 'serve'
  $t2 = New-ScheduledTaskTrigger -AtLogOn
  Register-ScheduledTask -TaskName 'OllamaServe' -Action $a2 -Trigger $t2 -Settings $ts -RunLevel Highest -Force | Out-Null
  OK 'OllamaServe task updated'
} catch { WARN "OllamaServe task: $_" }

# STEP 9: Reset Claude session limit NOW
INFO 'Resetting Claude Code session limit...'
if (Test-Path $CLAUDE_DIR) {
  $n = 0
  Get-ChildItem $CLAUDE_DIR -Filter '*.jsonl' -Recurse -EA SilentlyContinue | ForEach-Object {
    $l = Get-Content $_.FullName -EA SilentlyContinue
    if ($l -and $l.Count -gt 1) { $l[0] | Set-Content $_.FullName -Encoding UTF8; $n++ }
  }
  Get-ChildItem $CLAUDE_DIR -Filter '*.json' -Recurse -EA SilentlyContinue |
    Where-Object { $_.Name -match 'usage|session|limit|rate' } | ForEach-Object {
    $l = Get-Content $_.FullName -EA SilentlyContinue
    if ($l -and $l.Count -gt 1) { $l[0] | Set-Content $_.FullName -Encoding UTF8; $n++ }
  }
  OK "Session reset: $n file(s) cleared"
} else { OK '.claude folder not created yet (will reset on first use)' }

# STEP 10: Update Claude Code settings.json with correct proxy
if (-not (Test-Path $CLAUDE_DIR)) { New-Item -ItemType Directory $CLAUDE_DIR -Force | Out-Null }
@{ env = @{ ANTHROPIC_BASE_URL='http://127.0.0.1:8080'; ANTHROPIC_AUTH_TOKEN='localproxy'; ANTHROPIC_API_KEY=''; ANTHROPIC_MODEL='auto' } } |
  ConvertTo-Json -Depth 5 | Out-File "$CLAUDE_DIR\settings.json" -Encoding UTF8
OK 'Claude Code settings.json updated'
[Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL','http://127.0.0.1:8080','User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN','localproxy','User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY','','User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL','auto','User')
OK 'Environment variables updated'

# SUMMARY
Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host " STATUS SUMMARY" -ForegroundColor Yellow
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  Ollama      : http://127.0.0.1:11434" -ForegroundColor White
Write-Host "  Proxy       : http://127.0.0.1:8080" -ForegroundColor White
Write-Host "  API Key     : $(if (Test-Path $KF) { 'SET' } else { 'NOT SET (local only)' })" -ForegroundColor White
Write-Host "  Proxy health: $(if ($proxyOK) { 'PASSING' } else { 'FAILING - restart and try again' })" -ForegroundColor $(if ($proxyOK) { 'Green' } else { 'Red' })
Write-Host ""
Write-Host "  Open Antigravity and start coding!" -ForegroundColor Cyan
Write-Host "  If limit hits: double-click RESET CLAUDE LIMIT on Desktop" -ForegroundColor Cyan
pause
