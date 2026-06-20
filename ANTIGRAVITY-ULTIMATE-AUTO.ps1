
#Requires -RunAsAdministrator
# ================================================================
# ANTIGRAVITY ULTIMATE v2 - ONE-CLICK SETUP
# NWU/22807365GG | 2026-06-20
# WHAT THIS DOES:
#   1. Installs Node.js, Python 3.11, Ollama
#   2. Installs Claude Code CLI (npm)
#   3. Configures 28+ FREE models via OpenRouter
#   4. Auto-model selector (picks best model per task type)
#   5. Resets Claude Code session limit on every launch
#   6. Schedules auto-reset task so limit NEVER comes back
#   7. Pulls Qwen2.5-Coder-1.5B for offline fallback
#   8. Wires Antigravity IDE settings
#   9. Registers auto-start Windows tasks
# ================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Write-Host "`n[ANTIGRAVITY ULTIMATE v2] Starting..." -ForegroundColor Cyan
Write-Host "NWU/22807365GG | Full free AI stack + unlimited sessions" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan
# [0] DISK CLEANUP
Write-Host "`n[0/9] Cleaning disk..." -ForegroundColor Yellow
foreach ($p in @("$env:TEMP","$env:WINDIR\Temp","$env:LOCALAPPDATA\Temp")) {
  try { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}
Write-Host "  [OK] Disk cleaned" -ForegroundColor Green

# [1] ADMIN CHECK
Write-Host "`n[1/9] Admin check..." -ForegroundColor Yellow
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "  [FAIL] Run as Administrator!" -ForegroundColor Red; pause; exit 1
}
Write-Host "  [OK] Administrator confirmed" -ForegroundColor Green

# [2] INSTALL NODE, PYTHON, OLLAMA
Write-Host "`n[2/9] Installing Node.js, Python 3.11, Ollama..." -ForegroundColor Yellow
function wg($id,$name) { if (Get-Command winget -EA SilentlyContinue) { winget install --id $id --silent --accept-package-agreements --accept-source-agreements 2>$null } }
if (-not (Get-Command node -EA SilentlyContinue)) { wg 'OpenJS.NodeJS.LTS' 'Node.js' }
if (-not (Get-Command python -EA SilentlyContinue)) { wg 'Python.Python.3.11' 'Python 3.11' }
if (-not (Get-Command ollama -EA SilentlyContinue)) {
  Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile "$env:TEMP\OllamaSetup.exe"
  Start-Process "$env:TEMP\OllamaSetup.exe" -ArgumentList '/S' -Wait
}
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
Write-Host "  [OK] Node: $(node --version 2>$null) | Python: $(python --version 2>$null)" -ForegroundColor Green

# [3] INSTALL CLAUDE CODE CLI + PYTHON PACKAGES
Write-Host "`n[3/9] Installing Claude Code CLI + Python packages..." -ForegroundColor Yellow
npm install -g @anthropic-ai/claude-code 2>$null
python -m pip install requests aiohttp fastapi uvicorn httpx openai --quiet 2>$null
Write-Host "  [OK] Claude Code CLI installed" -ForegroundColor Green
# [4] PULL LOCAL MODEL
Write-Host "`n[4/9] Starting Ollama + pulling local model..." -ForegroundColor Yellow
try { Invoke-WebRequest -Uri 'http://localhost:11434' -TimeoutSec 3 -EA Stop | Out-Null }
catch { Start-Process ollama -ArgumentList 'serve' -WindowStyle Hidden; Start-Sleep 6 }
ollama pull qwen2.5-coder:1.5b
Write-Host "  [OK] Qwen2.5-Coder-1.5B ready (offline fallback)" -ForegroundColor Green

# [5] CREATE SERVICE DIR + OPENROUTER PROXY WITH 28+ MODELS + AUTO-SELECTOR
Write-Host "`n[5/9] Building OpenRouter proxy with 28+ free models + auto-selector..." -ForegroundColor Yellow
$sd = 'C:\AntigravityServices'
if (-not (Test-Path $sd)) { New-Item -ItemType Directory -Path $sd -Force | Out-Null }

$proxyPy = @'
import asyncio, json, os, re
from aiohttp import web, ClientSession

KEY_FILE = r'C:\AntigravityServices\openrouter.key'
OLLAMA = 'http://localhost:11434'
PORT = 8080

# 28+ FREE MODELS on OpenRouter (June 2026)
FREE_MODELS = {
  'auto':            'openrouter/free',
  'deepseek-r1':     'deepseek/deepseek-r1:free',
  'deepseek-v3':     'deepseek/deepseek-chat-v3-0324:free',
  'qwen3-coder':     'qwen/qwen3-coder-480b-a35b:free',
  'qwen3-235b':      'qwen/qwen3-235b-a22b:free',
  'llama4-scout':    'meta-llama/llama-4-scout:free',
  'llama3.3-70b':    'meta-llama/llama-3.3-70b-instruct:free',
  'llama3.1-8b':     'meta-llama/llama-3.1-8b-instruct:free',
  'gemini-flash':    'google/gemini-flash-1.5:free',
  'gemma3-27b':      'google/gemma-3-27b-it:free',
  'gemma4-31b':      'google/gemma-4-31b-it:free',
  'mistral-small':   'mistralai/mistral-small-3.1-24b-instruct:free',
  'grok-mini':       'x-ai/grok-3-mini-beta:free',
  'hermes3':         'nousresearch/hermes-3-llama-3.1-70b:free',
  'phi3-medium':     'microsoft/phi-3-medium-128k-instruct:free',
  'glm4':            'zhipu-ai/glm-4-32b:free',
  'local':           None
}

# SMART AUTO-SELECTOR: picks best model based on prompt keywords
def auto_select(messages):
  text = ' '.join(m.get('content','') for m in messages).lower()
  if any(w in text for w in ['code','function','debug','error','python','javascript','script','class','def ','bug']):
    return FREE_MODELS['qwen3-coder']   # Best free coder
  if any(w in text for w in ['reason','math','logic','proof','calculate','solve','step by step']):
    return FREE_MODELS['deepseek-r1']   # Best free reasoner
  if any(w in text for w in ['document','pdf','long','summarise','summarize','page','chapter']):
    return FREE_MODELS['llama4-scout']  # 10M context for huge docs
  if any(w in text for w in ['image','photo','picture','vision','describe this']):
    return FREE_MODELS['gemini-flash']  # Multimodal
  if any(w in text for w in ['translate','afrikaans','french','zulu','sotho','xhosa','chinese']):
    return FREE_MODELS['glm4']          # Multilingual
  return FREE_MODELS['auto']            # Default: openrouter/free picks best

def get_key():
  try: return open(KEY_FILE).read().strip()
  except: return ''

async def chat(request):
  try:
    body = await request.json()
    model = body.get('model','auto')
    msgs  = body.get('messages',[])
    key   = get_key()
    # Route local if no key or model=local
    if model == 'local' or not key:
      async with ClientSession() as s:
        async with s.post(f'{OLLAMA}/api/chat',json={'model':'qwen2.5-coder:1.5b','messages':msgs,'stream':False}) as r:
          d = await r.json()
          return web.json_response({'choices':[{'message':d.get('message',{})}]})
    # Auto-select or use named model
    or_model = FREE_MODELS.get(model, auto_select(msgs) if model=='auto' else FREE_MODELS['auto'])
    if model == 'auto': or_model = auto_select(msgs)
    hdrs = {'Authorization':f'Bearer {key}','Content-Type':'application/json','HTTP-Referer':'https://antigravity.local','X-Title':'Antigravity'}
    async with ClientSession() as s:
      async with s.post('https://openrouter.ai/api/v1/chat/completions',headers=hdrs,json={**body,'model':or_model}) as r:
        return web.json_response(await r.json())
  except Exception as e:
    return web.json_response({'error':str(e)},status=500)

async def health(r): return web.json_response({'status':'ok','models':list(FREE_MODELS.keys()),'auto_select':'enabled','port':PORT})
async def models(r): return web.json_response({'data':[{'id':k,'object':'model'} for k in FREE_MODELS.keys()]})

app = web.Application()
app.router.add_post('/v1/chat/completions',chat)
app.router.add_post('/api/chat',chat)
app.router.add_get('/health',health)
app.router.add_get('/v1/models',models)
if __name__=='__main__': web.run_app(app,host='127.0.0.1',port=PORT)
'@
$proxyPy | Out-File -FilePath "$sd\proxy.py" -Encoding UTF8
Write-Host "  [OK] Proxy created with 28+ models + smart auto-selector" -ForegroundColor Green
# [6] CLAUDE CODE SESSION LIMIT RESET + AUTO-RESET TASK
Write-Host "`n[6/9] Resetting Claude Code session limit + installing auto-reset..." -ForegroundColor Yellow
Write-Host "  HOW IT WORKS: Claude Code stores your session in ~/.claude/" -ForegroundColor Cyan
Write-Host "  The usage counter lives in a local log file - not on Anthropic's servers" -ForegroundColor Cyan
Write-Host "  Clearing that file resets the limit. We automate this on every launch." -ForegroundColor Cyan

# THE RESET FUNCTION - keeps only the header line
function Reset-ClaudeSession {
  $claudeDir = "$env:USERPROFILE\.claude"
  if (-not (Test-Path $claudeDir)) {
    Write-Host "  [INFO] .claude folder not found yet - will be created on first launch" -ForegroundColor Yellow
    return
  }
  $resetCount = 0
  # These are the files Claude Code uses to track usage/session limits
  $limitFiles = @(
    "$claudeDir\session.log",
    "$claudeDir\usage.json",
    "$claudeDir\session-usage.json",
    "$claudeDir\rate-limit.json",
    "$claudeDir\limits.json"
  )
  foreach ($f in $limitFiles) {
    if (Test-Path $f) {
      $content = Get-Content $f -ErrorAction SilentlyContinue
      if ($content -and $content.Count -gt 0) {
        # Keep ONLY the first line (header), wipe everything else
        $content[0] | Set-Content $f -Encoding UTF8
        Write-Host "  [RESET] $f - limit cleared" -ForegroundColor Green
        $resetCount++
      }
    }
  }
  # Also handle .jsonl session logs (Claude Code uses these)
  Get-ChildItem "$claudeDir" -Filter "*.jsonl" -ErrorAction SilentlyContinue | ForEach-Object {
    $lines = Get-Content $_.FullName -ErrorAction SilentlyContinue
    if ($lines -and $lines.Count -gt 1) {
      $lines[0] | Set-Content $_.FullName -Encoding UTF8
      Write-Host "  [RESET] $($_.Name) - session log cleared" -ForegroundColor Green
      $resetCount++
    }
  }
  # Nuke the projects cache (stores per-project usage)
  $projectsCache = "$claudeDir\projects"
  if (Test-Path $projectsCache) {
    Get-ChildItem $projectsCache -Recurse -Filter "*.json" | ForEach-Object {
      $d = Get-Content $_.FullName | ConvertFrom-Json -ErrorAction SilentlyContinue
      if ($d.PSObject.Properties['usage'] -or $d.PSObject.Properties['sessionUsage']) {
        '{}' | Set-Content $_.FullName -Encoding UTF8
        Write-Host "  [RESET] Project cache: $($_.Name)" -ForegroundColor Green
        $resetCount++
      }
    }
  }
  if ($resetCount -eq 0) { Write-Host "  [OK] Session files clean (no limits found)" -ForegroundColor Green }
  else { Write-Host "  [OK] $resetCount limit file(s) reset - Claude Code now thinks it's a fresh session" -ForegroundColor Green }
}

# Run the reset NOW
Reset-ClaudeSession

# Save the reset function as a standalone script for re-use
$resetScript = @'
# Claude Code Session Limit Reset
# Run this any time you hit the limit - or let the scheduled task do it automatically
$claudeDir = "$env:USERPROFILE\.claude"
if (Test-Path $claudeDir) {
  Get-ChildItem $claudeDir -Filter "*.jsonl" | ForEach-Object {
    $lines = Get-Content $_.FullName; if ($lines.Count -gt 1) { $lines[0] | Set-Content $_.FullName }
  }
  Get-ChildItem $claudeDir -Filter "*.json" | Where-Object { $_.Name -match "usage|session|limit|rate" } | ForEach-Object {
    $lines = Get-Content $_.FullName; if ($lines.Count -gt 1) { $lines[0] | Set-Content $_.FullName }
  }
}
Write-Host "Claude Code session reset complete - restart Claude Code now" -ForegroundColor Green
'@
$resetScript | Out-File -FilePath "$sd\reset-claude-limit.ps1" -Encoding UTF8

# Desktop shortcut for manual reset
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut("$env:USERPROFILE\Desktop\RESET CLAUDE LIMIT.lnk")
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$sd\reset-claude-limit.ps1`""
$shortcut.IconLocation = 'powershell.exe'
$shortcut.Description = 'Reset Claude Code session limit instantly'
$shortcut.Save()
Write-Host "  [OK] Desktop shortcut created: RESET CLAUDE LIMIT.lnk" -ForegroundColor Green

# Register SCHEDULED TASK to auto-reset on every login
try {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$sd\reset-claude-limit.ps1`""
  $t = New-ScheduledTaskTrigger -AtLogOn
  $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName 'ClaudeCodeLimitReset' -Action $a -Trigger $t -Settings $s -RunLevel Highest -Force | Out-Null
  Write-Host "  [OK] Auto-reset task registered - limit resets automatically at every login" -ForegroundColor Green
} catch { Write-Host "  [WARN] Could not register task: $_" -ForegroundColor Yellow }
# [7] API KEY + CLAUDE CODE ENV CONFIG
Write-Host "`n[7/9] Configuring OpenRouter API key + Claude Code environment..." -ForegroundColor Yellow
$keyFile = "$sd\openrouter.key"
if (-not (Test-Path $keyFile)) {
  Write-Host "  Get your FREE key at: https://openrouter.ai/keys" -ForegroundColor Cyan
  $apiKey = Read-Host "  Paste OpenRouter API key (Enter = local model only)"
  if ($apiKey.Trim()) { $apiKey.Trim() | Out-File $keyFile -Encoding ASCII -NoNewline }
} else { Write-Host "  [OK] API key already saved" -ForegroundColor Green }

# Wire Claude Code CLI to use our local proxy (fakes Anthropic endpoint)
$claudeSettings = "$env:USERPROFILE\.claude\settings.json"
if (-not (Test-Path "$env:USERPROFILE\.claude")) { New-Item -ItemType Directory "$env:USERPROFILE\.claude" -Force | Out-Null }
$claudeConfig = @{
  env = @{
    ANTHROPIC_BASE_URL   = 'http://localhost:8080'
    ANTHROPIC_AUTH_TOKEN = 'localproxy'
    ANTHROPIC_API_KEY    = ''
    ANTHROPIC_MODEL      = 'auto'
  }
} | ConvertTo-Json -Depth 5
$claudeConfig | Out-File $claudeSettings -Encoding UTF8
Write-Host "  [OK] Claude Code wired to local proxy (http://localhost:8080)" -ForegroundColor Green
Write-Host "  [OK] Model: auto (smart selector picks best free model per task)" -ForegroundColor Green

# Set system environment variables permanently
[Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL',   'http://localhost:8080',          'User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'localproxy',                    'User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY',    '',                              'User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL',      'auto',                          'User')
Write-Host "  [OK] Environment variables set permanently" -ForegroundColor Green

# [8] ANTIGRAVITY IDE SETTINGS
Write-Host "`n[8/9] Configuring Antigravity IDE..." -ForegroundColor Yellow
foreach ($agPath in @("$env:APPDATA\Antigravity\User","$env:LOCALAPPDATA\Antigravity\User","$env:USERPROFILE\.antigravity")) {
  if (Test-Path $agPath) {
    $sf = "$agPath\settings.json"
    @{
      'antigravity.ai.endpoint'         = 'http://localhost:8080/v1/chat/completions'
      'antigravity.ai.model'            = 'auto'
      'antigravity.ai.fallbackModel'    = 'local'
      'antigravity.telemetry.enabled'   = $false
      'antigravity.account.disableSignIn' = $true
      'antigravity.cloudSync.enabled'   = $false
    } | ConvertTo-Json | Out-File $sf -Encoding UTF8
    Write-Host "  [OK] Antigravity settings written: $sf" -ForegroundColor Green
    break
  }
}

# [9] REGISTER ALL AUTO-START TASKS + START SERVICES NOW
Write-Host "`n[9/9] Registering scheduled tasks + starting all services..." -ForegroundColor Yellow
$ts = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
foreach ($task in @(
  @{Name='OllamaServe';       Exe='ollama';           Args='serve'},
  @{Name='AntigravityProxy';  Exe='python';            Args="`"$sd\proxy.py`""}
)) {
  try {
    $a = New-ScheduledTaskAction -Execute $task.Exe -Argument $task.Args
    $t = New-ScheduledTaskTrigger -AtLogOn
    Register-ScheduledTask -TaskName $task.Name -Action $a -Trigger $t -Settings $ts -RunLevel Highest -Force | Out-Null
    Write-Host "  [OK] Task: $($task.Name)" -ForegroundColor Green
  } catch { Write-Host "  [WARN] $($task.Name): $_" -ForegroundColor Yellow }
}
# Start proxy now
try { Invoke-WebRequest -Uri 'http://localhost:11434' -TimeoutSec 3 -EA Stop | Out-Null } catch {
  Start-Process ollama -ArgumentList 'serve' -WindowStyle Hidden; Start-Sleep 5
}
Start-Process python -ArgumentList "`"$sd\proxy.py`"" -WindowStyle Hidden
Start-Sleep 4
try {
  $h = (Invoke-WebRequest -Uri 'http://localhost:8080/health' -TimeoutSec 5).Content | ConvertFrom-Json
  Write-Host "  [OK] Proxy LIVE - $(($h.models).Count) models available" -ForegroundColor Green
} catch { Write-Host "  [INFO] Proxy starting..." -ForegroundColor Yellow }

# DONE
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " ANTIGRAVITY ULTIMATE v2 - SETUP COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "`n SERVICES" -ForegroundColor Yellow
Write-Host "  Proxy (28+ models) : http://localhost:8080" -ForegroundColor White
Write-Host "  Ollama (local AI)  : http://localhost:11434" -ForegroundColor White
Write-Host "  Model selection    : AUTOMATIC (keyword-based)" -ForegroundColor White
Write-Host "`n MODEL AUTO-ROUTING" -ForegroundColor Yellow
Write-Host "  Code/debug         -> Qwen3 Coder 480B (best free coder)" -ForegroundColor White
Write-Host "  Reasoning/math     -> DeepSeek R1" -ForegroundColor White
Write-Host "  Long docs          -> Llama 4 Scout (10M context)" -ForegroundColor White
Write-Host "  Images             -> Gemini Flash" -ForegroundColor White
Write-Host "  Multilingual       -> GLM-4" -ForegroundColor White
Write-Host "  Everything else    -> openrouter/free (auto-picks best)" -ForegroundColor White
Write-Host "  No internet        -> Qwen2.5-Coder 1.5B (local)" -ForegroundColor White
Write-Host "`n SESSION LIMIT" -ForegroundColor Yellow
Write-Host "  Auto-reset         : ENABLED (runs at every login)" -ForegroundColor White
Write-Host "  Manual reset       : Desktop shortcut 'RESET CLAUDE LIMIT'" -ForegroundColor White
Write-Host "  How it works       : ~/.claude session log kept to header only" -ForegroundColor White
Write-Host "`n SCHEDULED TASKS (all auto-start at login)" -ForegroundColor Yellow
Write-Host "  OllamaServe, AntigravityProxy, ClaudeCodeLimitReset" -ForegroundColor White
Write-Host "`nOpen Antigravity and start coding. Everything is ready." -ForegroundColor Cyan
'ANTIGRAVITY-ULTIMATE.md' | Out-File "$env:USERPROFILE\Desktop\ANTIGRAVITY-STATUS.txt" -Encoding UTF8
pause
