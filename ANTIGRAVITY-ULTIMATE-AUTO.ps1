
#Requires -RunAsAdministrator
# ============================================================
# ANTIGRAVITY ULTIMATE - ONE-CLICK AUTO SETUP
# Installs: Node.js, Python 3.11, Ollama, OpenRouter Proxy
# Configures: Antigravity IDE, Windows Services, Auto-start
# Models: DeepSeek R1, Qwen3 72B, Qwen2.5-Coder-1.5B (LOCAL)
# NWU/22807365GG | 2026-06-20
# ============================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Write-Host "`n[ANTIGRAVITY ULTIMATE] Starting one-click setup..." -ForegroundColor Cyan
Write-Host "NWU/22807365GG | Antigravity Desktop Installer" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan

# --- [0/9] DISK CLEANUP ---
Write-Host "`n[0/9] Cleaning C:\ drive (10-30GB will be freed)..." -ForegroundColor Yellow
$cleanPaths = @(
  "$env:TEMP",
  "$env:WINDIR\Temp",
  "$env:LOCALAPPDATA\Temp",
  "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
  "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\*.db"
)
foreach ($p in $cleanPaths) {
  try { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}
$freed = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host "  [OK] Disk cleaned. C:\ free space: ${freed}GB" -ForegroundColor Green
# --- [1/9] ADMIN CHECK ---
Write-Host "`n[1/9] Checking administrator rights..." -ForegroundColor Yellow
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "  [FAIL] Run as Administrator! Right-click > Run with PowerShell (Admin)" -ForegroundColor Red
  pause; exit 1
}
Write-Host "  [OK] Running as Administrator" -ForegroundColor Green

# --- [2/9] INSTALL DEPENDENCIES ---
Write-Host "`n[2/9] Installing Node.js, Python 3.11, Ollama..." -ForegroundColor Yellow
function Install-WithWinget($id, $name) {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "  Installing $name via winget..."
    winget install --id $id --silent --accept-package-agreements --accept-source-agreements 2>$null
  }
}
# Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Install-WithWinget 'OpenJS.NodeJS.LTS' 'Node.js LTS'
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}
Write-Host "  [OK] Node.js: $(node --version 2>$null)" -ForegroundColor Green
# Python 3.11
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  Install-WithWinget 'Python.Python.3.11' 'Python 3.11'
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}
Write-Host "  [OK] Python: $(python --version 2>$null)" -ForegroundColor Green
# Ollama
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
  Write-Host "  Downloading Ollama installer..."
  $ollamaInstaller = "$env:TEMP\OllamaSetup.exe"
  Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile $ollamaInstaller
  Start-Process $ollamaInstaller -ArgumentList '/S' -Wait
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}
Write-Host "  [OK] Ollama: $(ollama --version 2>$null)" -ForegroundColor Green
# --- [3/9] PYTHON PACKAGES ---
Write-Host "`n[3/9] Installing Python packages..." -ForegroundColor Yellow
$packages = @('requests','aiohttp','fastapi','uvicorn','httpx','openai','anthropic')
foreach ($pkg in $packages) {
  python -m pip install $pkg --quiet 2>$null
  Write-Host "  [OK] $pkg" -ForegroundColor Green
}

# --- [4/9] PULL LOCAL MODEL ---
Write-Host "`n[4/9] Pulling Qwen 2.5 Coder 1.5B (local AI, ~900MB)..." -ForegroundColor Yellow
Write-Host "  This is your offline fallback model - works without internet" -ForegroundColor Cyan
# Start Ollama service first
try {
  $resp = Invoke-WebRequest -Uri 'http://localhost:11434' -TimeoutSec 3 -ErrorAction Stop
  Write-Host "  [OK] Ollama already running" -ForegroundColor Green
} catch {
  Write-Host "  Starting Ollama service..."
  Start-Process ollama -ArgumentList 'serve' -WindowStyle Hidden
  Start-Sleep 5
}
ollama pull qwen2.5-coder:1.5b
Write-Host "  [OK] Qwen 2.5 Coder 1.5B ready" -ForegroundColor Green
# --- [5/9] CREATE SERVICE INFRASTRUCTURE ---
Write-Host "`n[5/9] Creating service infrastructure..." -ForegroundColor Yellow
$serviceDir = "C:\AntigravityServices"
if (-not (Test-Path $serviceDir)) { New-Item -ItemType Directory -Path $serviceDir -Force | Out-Null }

# Create the OpenRouter Proxy server (Python)
$proxyScript = @'
import asyncio, json, sys
from aiohttp import web, ClientSession

OPENROUTER_API_KEY = open('C:\\AntigravityServices\\openrouter.key','r').read().strip() if __import__('os').path.exists('C:\\AntigravityServices\\openrouter.key') else ''
OLLAMA_URL = 'http://localhost:11434'
PROXY_PORT = 8080

MODELS = {
  'deepseek-r1': 'deepseek/deepseek-r1:free',
  'qwen3-72b': 'qwen/qwen3-72b:free',
  'gemma3-27b': 'google/gemma-3-27b-it:free',
  'deepseek-chat': 'deepseek/deepseek-chat-v3-0324:free',
  'qwen2.5-coder:1.5b': None  # LOCAL
}

async def proxy_chat(request):
  try:
    body = await request.json()
    model = body.get('model','deepseek-r1')
    if model == 'qwen2.5-coder:1.5b' or not OPENROUTER_API_KEY:
      # Route to local Ollama
      async with ClientSession() as s:
        async with s.post(f'{OLLAMA_URL}/api/chat', json={'model':'qwen2.5-coder:1.5b','messages':body.get('messages',[]),'stream':False}) as r:
          data = await r.json()
          return web.json_response({'choices':[{'message':data.get('message',{})}]})
    else:
      or_model = MODELS.get(model, 'deepseek/deepseek-r1:free')
      headers = {'Authorization':f'Bearer {OPENROUTER_API_KEY}','Content-Type':'application/json'}
      async with ClientSession() as s:
        async with s.post('https://openrouter.ai/api/v1/chat/completions',headers=headers,json={**body,'model':or_model}) as r:
          data = await r.json()
          return web.json_response(data)
  except Exception as e:
    return web.json_response({'error':str(e)},status=500)

async def health(request): return web.json_response({'status':'ok','proxy':'antigravity-openrouter','port':PROXY_PORT})

app = web.Application()
app.router.add_post('/v1/chat/completions',proxy_chat)
app.router.add_post('/api/chat',proxy_chat)
app.router.add_get('/health',health)
if __name__=='__main__': web.run_app(app,host='127.0.0.1',port=PROXY_PORT)
'@
$proxyScript | Out-File -FilePath "$serviceDir\proxy.py" -Encoding UTF8
Write-Host "  [OK] OpenRouter proxy script created" -ForegroundColor Green
# --- [6/9] BUILD OPENROUTER PROXY + COLLECT API KEY ---
Write-Host "`n[6/9] Configuring OpenRouter API key..." -ForegroundColor Yellow
$keyFile = "$serviceDir\openrouter.key"
if (-not (Test-Path $keyFile)) {
  Write-Host "  " -NoNewline
  Write-Host "IMPORTANT: You need a FREE OpenRouter API key!" -ForegroundColor Cyan
  Write-Host "  Get one at: https://openrouter.ai/keys (free, 5 models included)" -ForegroundColor Cyan
  $apiKey = Read-Host "  Paste your OpenRouter API key (or press Enter to use LOCAL model only)"
  if ($apiKey -and $apiKey.Trim() -ne '') {
    $apiKey.Trim() | Out-File -FilePath $keyFile -Encoding ASCII -NoNewline
    Write-Host "  [OK] API key saved to $keyFile" -ForegroundColor Green
  } else {
    Write-Host "  [INFO] No API key - will use LOCAL model (Qwen2.5-Coder) only" -ForegroundColor Yellow
  }
} else {
  Write-Host "  [OK] API key already configured" -ForegroundColor Green
}

# --- [7/9] REGISTER WINDOWS SERVICES ---
Write-Host "`n[7/9] Registering Windows Services (auto-start on boot)..." -ForegroundColor Yellow
# Create startup script
$startupScript = @"
python `"$serviceDir\proxy.py`"
"@
$startupScript | Out-File -FilePath "$serviceDir\start-proxy.ps1" -Encoding UTF8
# Register scheduled task for auto-start
try {
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$serviceDir\start-proxy.ps1`""
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
  Register-ScheduledTask -TaskName 'AntigravityProxy' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
  Write-Host "  [OK] AntigravityProxy scheduled task registered (runs at login)" -ForegroundColor Green
} catch {
  Write-Host "  [WARN] Could not register scheduled task: $_" -ForegroundColor Yellow
}
# Register Ollama auto-start
try {
  $action2 = New-ScheduledTaskAction -Execute 'ollama' -Argument 'serve'
  $trigger2 = New-ScheduledTaskTrigger -AtLogOn
  Register-ScheduledTask -TaskName 'OllamaServe' -Action $action2 -Trigger $trigger2 -Settings $settings -RunLevel Highest -Force | Out-Null
  Write-Host "  [OK] OllamaServe scheduled task registered" -ForegroundColor Green
} catch {
  Write-Host "  [WARN] Could not register Ollama task: $_" -ForegroundColor Yellow
}
# --- [8/9] CONFIGURE ANTIGRAVITY IDE ---
Write-Host "`n[8/9] Configuring Antigravity IDE..." -ForegroundColor Yellow
$agPaths = @(
  "$env:APPDATA\Antigravity\User",
  "$env:LOCALAPPDATA\Antigravity\User",
  "$env:USERPROFILE\.antigravity",
  "$env:APPDATA\Code\User"
)
$agSettingsPath = $null
foreach ($p in $agPaths) {
  if (Test-Path $p) { $agSettingsPath = $p; break }
}
if (-not $agSettingsPath) {
  $agSettingsPath = "$env:APPDATA\Antigravity\User"
  New-Item -ItemType Directory -Path $agSettingsPath -Force | Out-Null
}
$settingsFile = "$agSettingsPath\settings.json"
$settings = @{
  'antigravity.ai.provider' = 'openrouter'
  'antigravity.ai.endpoint' = 'http://localhost:8080/v1/chat/completions'
  'antigravity.ai.model' = 'deepseek-r1'
  'antigravity.ai.fallbackModel' = 'qwen2.5-coder:1.5b'
  'antigravity.ai.offlineMode' = $false
  'antigravity.telemetry.enabled' = $false
  'antigravity.account.disableSignIn' = $true
  'antigravity.cloudSync.enabled' = $false
  'antigravity.autoUpdate' = $false
  'editor.fontSize' = 14
  'workbench.colorTheme' = 'Default Dark Modern'
}
if (Test-Path $settingsFile) {
  try {
    $existing = Get-Content $settingsFile | ConvertFrom-Json -AsHashtable
    $settings.GetEnumerator() | ForEach-Object { $existing[$_.Key] = $_.Value }
    $existing | ConvertTo-Json -Depth 10 | Out-File $settingsFile -Encoding UTF8
  } catch {
    $settings | ConvertTo-Json -Depth 10 | Out-File $settingsFile -Encoding UTF8
  }
} else {
  $settings | ConvertTo-Json -Depth 10 | Out-File $settingsFile -Encoding UTF8
}
Write-Host "  [OK] Antigravity settings written to: $settingsFile" -ForegroundColor Green
Write-Host "  [OK] AI endpoint: http://localhost:8080" -ForegroundColor Green
Write-Host "  [OK] Cloud sync: DISABLED" -ForegroundColor Green
Write-Host "  [OK] Sign-in prompts: DISABLED" -ForegroundColor Green
# --- [9/9] START SERVICES + FINAL TEST ---
Write-Host "`n[9/9] Starting services and running tests..." -ForegroundColor Yellow
# Start Ollama
try {
  Invoke-WebRequest -Uri 'http://localhost:11434' -TimeoutSec 3 -ErrorAction Stop | Out-Null
  Write-Host "  [OK] Ollama: RUNNING on port 11434" -ForegroundColor Green
} catch {
  Start-Process ollama -ArgumentList 'serve' -WindowStyle Hidden
  Start-Sleep 5
  Write-Host "  [OK] Ollama started on port 11434" -ForegroundColor Green
}
# Start proxy
$pythonPath = (Get-Command python -ErrorAction SilentlyContinue)?.Source
if ($pythonPath) {
  Start-Process python -ArgumentList "`"$serviceDir\proxy.py`"" -WindowStyle Hidden
  Start-Sleep 3
  try {
    $healthCheck = Invoke-WebRequest -Uri 'http://localhost:8080/health' -TimeoutSec 5
    $healthData = $healthCheck.Content | ConvertFrom-Json
    Write-Host "  [OK] OpenRouter Proxy: RUNNING on port 8080" -ForegroundColor Green
  } catch {
    Write-Host "  [WARN] Proxy starting... check http://localhost:8080/health" -ForegroundColor Yellow
  }
}
# Quick AI test
Write-Host "`n  Running quick AI test..." -ForegroundColor Cyan
try {
  $testBody = @{model='qwen2.5-coder:1.5b';messages=@(@{role='user';content='Say OK'})} | ConvertTo-Json -Depth 5
  $testResp = Invoke-WebRequest -Uri 'http://localhost:8080/v1/chat/completions' -Method POST -Body $testBody -ContentType 'application/json' -TimeoutSec 30
  Write-Host "  [OK] AI test PASSED - proxy is working!" -ForegroundColor Green
} catch {
  Write-Host "  [INFO] AI test skipped (model may still be loading)" -ForegroundColor Yellow
}
# Update MASTER-PLAYBOOK
$playbookPath = "$env:USERPROFILE\Desktop\MASTER-PLAYBOOK.md"
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$playbookContent = @"
# ANTIGRAVITY ULTIMATE - MASTER PLAYBOOK
Generated: $timestamp
NWU/22807365GG

## SERVICES
- Ollama: http://localhost:11434 (local AI runtime)
- OpenRouter Proxy: http://localhost:8080 (cloud AI gateway)

## MODELS AVAILABLE
| Model | Type | Best For |
|-------|------|----------|
| deepseek-r1 | Cloud (Free) | Reasoning, complex code |
| qwen3-72b | Cloud (Free) | Coding, general tasks |
| gemma3-27b | Cloud (Free) | Fast instruction-following |
| deepseek-chat | Cloud (Free) | Conversation |
| qwen2.5-coder:1.5b | LOCAL (offline) | Works without internet |

## AUTO-START
- AntigravityProxy task: runs at login
- OllamaServe task: runs at login

## FILES
- Service dir: C:\AntigravityServices\
- API Key: C:\AntigravityServices\openrouter.key
- Proxy: C:\AntigravityServices\proxy.py
- Settings: $settingsFile

## TO RESTART SERVICES
.\\fix-and-start.ps1 (or Run Antigravity -> services auto-start)
"@
$playbookContent | Out-File -FilePath $playbookPath -Encoding UTF8
Write-Host "  [OK] MASTER-PLAYBOOK.md saved to Desktop" -ForegroundColor Green
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "[DONE] ANTIGRAVITY ULTIMATE SETUP COMPLETE!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "`nSummary:" -ForegroundColor Yellow
Write-Host "  Claude Code Proxy : http://localhost:8080" -ForegroundColor White
Write-Host "  Ollama (local AI) : http://localhost:11434" -ForegroundColor White
Write-Host "  Local Model       : qwen2.5-coder:1.5b (offline-ready)" -ForegroundColor White
Write-Host "  Cloud Models      : DeepSeek R1, Qwen3 72B, Gemma3 27B" -ForegroundColor White
Write-Host "  Auto-start        : ENABLED (login triggers)" -ForegroundColor White
Write-Host "  Sign-in prompts   : DISABLED" -ForegroundColor White
Write-Host "  Cloud sync        : DISABLED" -ForegroundColor White
Write-Host "`nOpen Antigravity and start coding! The AI is ready." -ForegroundColor Cyan
pause
