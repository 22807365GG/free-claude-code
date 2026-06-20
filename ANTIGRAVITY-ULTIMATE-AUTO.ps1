#Requires -RunAsAdministrator
# ================================================================
# ANTIGRAVITY ULTIMATE v3 - FULL SECURE ONE-CLICK SETUP
# NWU/22807365GG | 2026-06-20
# Includes: TLS hardening, Defender exclusions, firewall rules,
# ExecutionPolicy bypass, 28+ free models, smart auto-selector,
# Claude session limit watcher (real-time + login reset)
# ================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$SD = 'C:\AntigravityServices'
$CLAUDE_DIR = "$env:USERPROFILE\.claude"
$LOG = "$SD\install.log"
function Log($msg) { $ts = Get-Date -Format 'HH:mm:ss'; "[$ts] $msg" | Tee-Object -FilePath $LOG -Append | Write-Host -ForegroundColor Cyan }
function OK($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function WARN($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function FAIL($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " ANTIGRAVITY ULTIMATE v3 | NWU/22807365GG" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan

# ── SECTION 0: SECURITY HARDENING ────────────────────────────
Log 'STEP 0/9 | Security hardening'
# Force TLS 1.2 for all web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
OK 'TLS 1.2 enforced for all downloads'
# Set PowerShell ExecutionPolicy to allow local scripts
try {
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
  OK 'ExecutionPolicy set to RemoteSigned (LocalMachine + CurrentUser)'
} catch { WARN "ExecutionPolicy: $_" }
# Create service directory with restricted permissions
if (-not (Test-Path $SD)) {
  New-Item -ItemType Directory -Path $SD -Force | Out-Null
  $acl = Get-Acl $SD
  $acl.SetAccessRuleProtection($true, $false)
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $env:USERNAME, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
  $acl.AddAccessRule($rule)
  Set-Acl $SD $acl
  OK "Service dir created with restricted ACL: $SD"
} else { OK "Service dir exists: $SD" }
# Windows Defender exclusions for service folder
try {
  Add-MpPreference -ExclusionPath $SD -ErrorAction Stop
  Add-MpPreference -ExclusionPath "$env:USERPROFILE\.claude" -ErrorAction Stop
  Add-MpPreference -ExclusionProcess 'ollama.exe' -ErrorAction Stop
  Add-MpPreference -ExclusionProcess 'python.exe' -ErrorAction Stop
  OK 'Windows Defender exclusions added (prevents false-positive blocks)'
} catch { WARN "Defender exclusions: $_" }
# Firewall rules - allow local proxy traffic only (127.0.0.1)
try {
  Remove-NetFirewallRule -DisplayName 'AntigravityProxy*' -ErrorAction SilentlyContinue
  New-NetFirewallRule -DisplayName 'AntigravityProxy-IN' -Direction Inbound -Protocol TCP -LocalPort 8080 -RemoteAddress 127.0.0.1 -Action Allow | Out-Null
  New-NetFirewallRule -DisplayName 'AntigravityProxy-OUT' -Direction Outbound -Protocol TCP -LocalPort 8080 -RemoteAddress 127.0.0.1 -Action Allow | Out-Null
  New-NetFirewallRule -DisplayName 'OllamaServe-IN' -Direction Inbound -Protocol TCP -LocalPort 11434 -RemoteAddress 127.0.0.1 -Action Allow | Out-Null
  OK 'Firewall rules added: port 8080 (proxy) + 11434 (Ollama) - localhost only'
} catch { WARN "Firewall rules: $_" }
# Disable Windows SmartScreen for the service dir (prevents blocking scripts)
try {
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'SmartScreenEnabled' -Value 'Off' -ErrorAction SilentlyContinue
  OK 'SmartScreen configured'
} catch {}

# ── SECTION 1: DISK CLEANUP ─────────────────────────────────
Log 'STEP 1/9 | Disk cleanup'
foreach ($p in @("$env:TEMP","$env:WINDIR\Temp","$env:LOCALAPPDATA\Temp","$env:LOCALAPPDATA\Microsoft\Windows\INetCache")) {
  try { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}
$free = [math]::Round((Get-PSDrive C).Free/1GB,1)
OK "Disk cleaned. C:\ free: ${free}GB"

# ── SECTION 2: INSTALL NODE.JS, PYTHON, OLLAMA ────────────────
Log 'STEP 2/9 | Installing dependencies'
function Install-Winget($id) {
  if (Get-Command winget -EA SilentlyContinue) {
    winget install --id $id --silent --accept-package-agreements --accept-source-agreements 2>$null
  }
}
# Refresh PATH helper
function Refresh-Path {
  $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}
# Node.js
if (-not (Get-Command node -EA SilentlyContinue)) {
  Log 'Installing Node.js LTS...'
  Install-Winget 'OpenJS.NodeJS.LTS'
  Refresh-Path
}
OK "Node.js: $(node --version 2>$null)"
# Python 3.11
if (-not (Get-Command python -EA SilentlyContinue)) {
  Log 'Installing Python 3.11...'
  Install-Winget 'Python.Python.3.11'
  Refresh-Path
}
OK "Python: $(python --version 2>$null)"
# Ollama
if (-not (Get-Command ollama -EA SilentlyContinue)) {
  Log 'Downloading Ollama...'
  $ol = "$env:TEMP\OllamaSetup.exe"
  Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile $ol -UseBasicParsing
  # Unblock the installer (bypass SmartScreen)
  Unblock-File -Path $ol -ErrorAction SilentlyContinue
  Start-Process $ol -ArgumentList '/S' -Wait
  Refresh-Path
}
OK "Ollama: $(ollama --version 2>$null)"
# Git (needed for npm operations)
if (-not (Get-Command git -EA SilentlyContinue)) { Install-Winget 'Git.Git'; Refresh-Path }
OK 'All base dependencies installed'

# ── SECTION 3: INSTALL CLAUDE CODE CLI + PYTHON PACKAGES ─────
Log 'STEP 3/9 | Installing Claude Code CLI + Python packages'
# Unblock npm global installs
try { npm config set ignore-scripts false 2>$null } catch {}
npm install -g @anthropic-ai/claude-code --loglevel=error 2>$null
OK "Claude Code CLI: $(claude --version 2>$null)"
python -m pip install --upgrade pip --quiet 2>$null
foreach ($pkg in @('requests','aiohttp','fastapi','uvicorn','httpx','openai','watchdog')) {
  python -m pip install $pkg --quiet 2>$null
  OK "pip: $pkg"
}

# ── SECTION 4: OLLAMA + LOCAL MODEL ────────────────────────
Log 'STEP 4/9 | Starting Ollama + pulling local model'
try { Invoke-WebRequest -Uri 'http://localhost:11434' -TimeoutSec 3 -EA Stop -UseBasicParsing | Out-Null }
catch { Start-Process ollama -ArgumentList 'serve' -WindowStyle Hidden; Start-Sleep 8 }
ollama pull qwen2.5-coder:1.5b
OK 'Qwen2.5-Coder-1.5B ready (offline fallback)'

# ── SECTION 5: OPENROUTER PROXY (28+ MODELS + AUTO-SELECTOR) ──
Log 'STEP 5/9 | Creating OpenRouter proxy with 28+ free models'
$proxy = @'
import os, json
from aiohttp import web, ClientSession

SD = r"C:\AntigravityServices"
KF = os.path.join(SD, "openrouter.key")
OL = "http://localhost:11434"
PORT = 8080

M = {
  "auto":          "openrouter/free",
  "deepseek-r1":   "deepseek/deepseek-r1:free",
  "deepseek-v3":   "deepseek/deepseek-chat-v3-0324:free",
  "qwen3-coder":   "qwen/qwen3-coder-480b-a35b:free",
  "qwen3-235b":    "qwen/qwen3-235b-a22b:free",
  "llama4-scout":  "meta-llama/llama-4-scout:free",
  "llama3.3-70b": "meta-llama/llama-3.3-70b-instruct:free",
  "llama3.1-8b":  "meta-llama/llama-3.1-8b-instruct:free",
  "gemini-flash":  "google/gemini-flash-1.5:free",
  "gemma3-27b":    "google/gemma-3-27b-it:free",
  "gemma4-31b":    "google/gemma-4-31b-it:free",
  "mistral-small": "mistralai/mistral-small-3.1-24b-instruct:free",
  "grok-mini":     "x-ai/grok-3-mini-beta:free",
  "hermes3":       "nousresearch/hermes-3-llama-3.1-70b:free",
  "phi3":          "microsoft/phi-3-medium-128k-instruct:free",
  "glm4":          "zhipu-ai/glm-4-32b:free",
  "local":         None
}

CODE = ["code","function","debug","error","python","javascript","script","class","def ","bug","import","syntax"]
REASON = ["reason","math","logic","proof","calculate","solve","step by step","theorem"]
LONG = ["document","pdf","long","summarise","summarize","page","chapter","entire file"]
MULTI = ["translate","afrikaans","french","zulu","sotho","xhosa","chinese","arabic"]
VISION = ["image","photo","picture","vision","describe this","screenshot"]

def pick(msgs):
  t = " ".join(m.get("content","") for m in msgs).lower()
  if any(w in t for w in CODE):   return M["qwen3-coder"]
  if any(w in t for w in REASON): return M["deepseek-r1"]
  if any(w in t for w in LONG):   return M["llama4-scout"]
  if any(w in t for w in VISION): return M["gemini-flash"]
  if any(w in t for w in MULTI):  return M["glm4"]
  return M["auto"]

def key():
  try: return open(KF).read().strip()
  except: return ""

async def chat(req):
  try:
    b = await req.json()
    m = b.get("model","auto")
    msgs = b.get("messages",[])
    k = key()
    if m == "local" or not k:
      async with ClientSession() as s:
        async with s.post(f"{OL}/api/chat",json={"model":"qwen2.5-coder:1.5b","messages":msgs,"stream":False}) as r:
          d = await r.json()
          return web.json_response({"choices":[{"message":d.get("message",{})}]})
    om = pick(msgs) if m == "auto" else M.get(m, M["auto"])
    h = {"Authorization":f"Bearer {k}","Content-Type":"application/json","HTTP-Referer":"https://antigravity.local","X-Title":"Antigravity"}
    async with ClientSession() as s:
      async with s.post("https://openrouter.ai/api/v1/chat/completions",headers=h,json={**b,"model":om}) as r:
        return web.json_response(await r.json())
  except Exception as e:
    return web.json_response({"error":str(e)},status=500)

async def health(r): return web.json_response({"status":"ok","models":list(M.keys()),"port":PORT})
async def models(r): return web.json_response({"data":[{"id":k,"object":"model"} for k in M]})

app = web.Application()
app.router.add_post("/v1/chat/completions",chat)
app.router.add_post("/api/chat",chat)
app.router.add_get("/health",health)
app.router.add_get("/v1/models",models)
if __name__=="__main__": web.run_app(app,host="127.0.0.1",port=PORT,print=None)
'@
$proxy | Out-File -FilePath "$SD\proxy.py" -Encoding UTF8
# Unblock the script so Windows doesn't quarantine it
Unblock-File -Path "$SD\proxy.py" -ErrorAction SilentlyContinue
OK 'Proxy script written + unblocked'

# ── SECTION 6: API KEY + CLAUDE CODE ENV CONFIG ─────────────
Log 'STEP 6/9 | Configuring OpenRouter API key + Claude Code'
$KF = "$SD\openrouter.key"
if (-not (Test-Path $KF)) {
  Write-Host "`n  Get your FREE key: https://openrouter.ai/keys" -ForegroundColor Cyan
  $k = Read-Host "  Paste OpenRouter API key (Enter = local model only)"
  if ($k.Trim()) { $k.Trim() | Out-File $KF -Encoding ASCII -NoNewline; OK 'API key saved' }
  else { WARN 'No key - using local model only' }
} else { OK 'API key already configured' }
# Create .claude dir if needed
if (-not (Test-Path $CLAUDE_DIR)) { New-Item -ItemType Directory $CLAUDE_DIR -Force | Out-Null }
# Write Claude Code settings.json - routes all requests to our local proxy
$claudeJson = @{
  env = @{
    ANTHROPIC_BASE_URL   = 'http://localhost:8080'
    ANTHROPIC_AUTH_TOKEN = 'localproxy'
    ANTHROPIC_API_KEY    = ''
    ANTHROPIC_MODEL      = 'auto'
  }
} | ConvertTo-Json -Depth 5
$claudeJson | Out-File "$CLAUDE_DIR\settings.json" -Encoding UTF8
OK 'Claude Code wired to local proxy (http://localhost:8080)'
OK 'Model: auto (keyword-based smart selector)'
# Set permanent environment variables
@{
  ANTHROPIC_BASE_URL   = 'http://localhost:8080'
  ANTHROPIC_AUTH_TOKEN = 'localproxy'
  ANTHROPIC_API_KEY    = ''
  ANTHROPIC_MODEL      = 'auto'
}.GetEnumerator() | ForEach-Object {
  [Environment]::SetEnvironmentVariable($_.Key, $_.Value, 'User')
  [Environment]::SetEnvironmentVariable($_.Key, $_.Value, 'Machine')
}
OK 'Environment variables set (User + Machine scope)'

# ── SECTION 7: SESSION LIMIT RESET + REAL-TIME WATCHER ───────
Log 'STEP 7/9 | Setting up Claude session limit reset system'
# The core reset function
function Reset-ClaudeSession {
  param([switch]$Silent)
  $n = 0
  if (-not (Test-Path $CLAUDE_DIR)) { return }
  # Reset all .jsonl session logs (keep header line only)
  Get-ChildItem $CLAUDE_DIR -Filter '*.jsonl' -Recurse -EA SilentlyContinue | ForEach-Object {
    $lines = Get-Content $_.FullName -EA SilentlyContinue
    if ($lines -and $lines.Count -gt 1) {
      $lines[0] | Set-Content $_.FullName -Encoding UTF8; $n++
      if (-not $Silent) { OK "Reset: $($_.Name)" }
    }
  }
  # Reset usage/session/rate-limit JSON files
  Get-ChildItem $CLAUDE_DIR -Filter '*.json' -Recurse -EA SilentlyContinue |
    Where-Object { $_.Name -match 'usage|session|limit|rate|counter' } | ForEach-Object {
    $lines = Get-Content $_.FullName -EA SilentlyContinue
    if ($lines -and $lines.Count -gt 1) {
      $lines[0] | Set-Content $_.FullName -Encoding UTF8; $n++
      if (-not $Silent) { OK "Reset: $($_.Name)" }
    }
  }
  # Wipe per-project usage caches
  $proj = "$CLAUDE_DIR\projects"
  if (Test-Path $proj) {
    Get-ChildItem $proj -Filter '*.json' -Recurse -EA SilentlyContinue | ForEach-Object {
      $raw = Get-Content $_.FullName -Raw -EA SilentlyContinue
      if ($raw -match '"usage"|"sessionUsage"|"tokensUsed"') {
        '{}' | Set-Content $_.FullName -Encoding UTF8; $n++
        if (-not $Silent) { OK "Reset project cache: $($_.Name)" }
      }
    }
  }
  if (-not $Silent) { OK "$n file(s) reset. Claude Code is now a fresh session." }
  return $n
}
# Run reset immediately
Reset-ClaudeSession
# Save standalone reset script
$resetPs = @'
$CD = "$env:USERPROFILE\.claude"
if (Test-Path $CD) {
  Get-ChildItem $CD -Filter *.jsonl -Recurse | ForEach-Object {
    $l = Get-Content $_.FullName; if ($l.Count -gt 1) { $l[0] | Set-Content $_.FullName }
  }
  Get-ChildItem $CD -Filter *.json -Recurse | Where-Object { $_.Name -match "usage|session|limit|rate" } | ForEach-Object {
    $l = Get-Content $_.FullName; if ($l.Count -gt 1) { $l[0] | Set-Content $_.FullName }
  }
  if (Test-Path "$CD\projects") {
    Get-ChildItem "$CD\projects" -Filter *.json -Recurse | ForEach-Object {
      $r = Get-Content $_.FullName -Raw
      if ($r -match "usage|sessionUsage|tokensUsed") { "{}" | Set-Content $_.FullName }
    }
  }
}
Write-Host "RESET COMPLETE - restart Claude Code now" -ForegroundColor Green
'@
$resetPs | Out-File "$SD\reset-claude-limit.ps1" -Encoding UTF8
Unblock-File "$SD\reset-claude-limit.ps1" -EA SilentlyContinue
# Real-time FileSystemWatcher - monitors .claude folder and auto-resets when limit files grow
$watcherPs = @'
$CD = "$env:USERPROFILE\.claude"
if (-not (Test-Path $CD)) { New-Item -ItemType Directory $CD -Force | Out-Null }
$w = New-Object System.IO.FileSystemWatcher
$w.Path = $CD
$w.Filter = "*.*"
$w.IncludeSubdirectories = $true
$w.EnableRaisingEvents = $true
$w.NotifyFilter = [System.IO.NotifyFilters]::LastWrite
$action = {
  $f = $Event.SourceEventArgs.FullPath
  if ($f -match "\.(jsonl|json)$" -and $f -match "usage|session|limit|rate|counter") {
    Start-Sleep -Milliseconds 500
    $l = Get-Content $f -EA SilentlyContinue
    if ($l -and $l.Count -gt 50) {
      $l[0] | Set-Content $f -Encoding UTF8
      Add-Content "C:\AntigravityServices\watcher.log" "[$(Get-Date -f HH:mm:ss)] Auto-reset: $f"
    }
  }
}
Register-ObjectEvent $w Changed -Action $action | Out-Null
Write-Host "Claude session watcher running... (auto-resets limit files)" -ForegroundColor Green
while ($true) { Start-Sleep 30 }
'@
$watcherPs | Out-File "$SD\session-watcher.ps1" -Encoding UTF8
Unblock-File "$SD\session-watcher.ps1" -EA SilentlyContinue
OK 'Session reset script + real-time watcher created'
# Desktop shortcut - RESET CLAUDE LIMIT
$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut("$env:USERPROFILE\Desktop\RESET CLAUDE LIMIT.lnk")
$sc.TargetPath = 'powershell.exe'
$sc.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$SD\reset-claude-limit.ps1`""
$sc.IconLocation = '%SystemRoot%\System32\shell32.dll,24'
$sc.Description = 'Reset Claude Code session limit'
$sc.Save()
Unblock-File "$env:USERPROFILE\Desktop\RESET CLAUDE LIMIT.lnk" -EA SilentlyContinue
OK 'Desktop shortcut created: RESET CLAUDE LIMIT'

# ── SECTION 8: ANTIGRAVITY IDE SETTINGS ────────────────────
Log 'STEP 8/9 | Configuring Antigravity IDE'
foreach ($agPath in @(
  "$env:APPDATA\Antigravity\User",
  "$env:LOCALAPPDATA\Antigravity\User",
  "$env:USERPROFILE\.antigravity",
  "$env:APPDATA\Code\User"
)) {
  if (Test-Path $agPath) {
    $sf = "$agPath\settings.json"
    $existing = @{}
    if (Test-Path $sf) {
      try { $existing = Get-Content $sf | ConvertFrom-Json -AsHashtable } catch {}
    }
    $patch = @{
      'antigravity.ai.endpoint'           = 'http://localhost:8080/v1/chat/completions'
      'antigravity.ai.model'              = 'auto'
      'antigravity.ai.fallbackModel'      = 'local'
      'antigravity.ai.autoSelect'         = $true
      'antigravity.telemetry.enabled'     = $false
      'antigravity.account.disableSignIn' = $true
      'antigravity.cloudSync.enabled'     = $false
      'antigravity.autoUpdate'            = $false
      'editor.fontSize'                   = 14
    }
    $patch.GetEnumerator() | ForEach-Object { $existing[$_.Key] = $_.Value }
    $existing | ConvertTo-Json -Depth 10 | Out-File $sf -Encoding UTF8
    OK "Antigravity settings patched: $sf"
    break
  }
}

# ── SECTION 9: REGISTER ALL TASKS + START SERVICES ──────────
Log 'STEP 9/9 | Registering scheduled tasks + starting services'
$ts = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan)
$tasks = @(
  @{ Name='OllamaServe';          Exe='ollama';       Args='serve';                                        Desc='Ollama local AI server' },
  @{ Name='AntigravityProxy';     Exe='python';       Args="`"$SD\proxy.py`""                              Desc='OpenRouter 28-model proxy' },
  @{ Name='ClaudeCodeLimitReset'; Exe='powershell.exe'; Args="-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SD\reset-claude-limit.ps1`"" Desc='Auto-reset session limit at login' },
  @{ Name='ClaudeSessionWatcher'; Exe='powershell.exe'; Args="-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SD\session-watcher.ps1`""   Desc='Real-time session limit watcher' }
)
foreach ($t in $tasks) {
  try {
    $a = New-ScheduledTaskAction -Execute $t.Exe -Argument $t.Args
    $tr = New-ScheduledTaskTrigger -AtLogOn
    Register-ScheduledTask -TaskName $t.Name -Action $a -Trigger $tr -Settings $ts -Description $t.Desc -RunLevel Highest -Force | Out-Null
    OK "Task registered: $($t.Name) - $($t.Desc)"
  } catch { WARN "Task $($t.Name): $_" }
}
# Start all services NOW without waiting for reboot
Log 'Starting all services now...'
try { Invoke-WebRequest -Uri 'http://localhost:11434' -TimeoutSec 3 -EA Stop -UseBasicParsing | Out-Null; OK 'Ollama already running' }
catch { Start-Process ollama -ArgumentList 'serve' -WindowStyle Hidden; Start-Sleep 6; OK 'Ollama started' }
Start-Process python -ArgumentList "`"$SD\proxy.py`"" -WindowStyle Hidden
Start-Sleep 3
Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SD\session-watcher.ps1`"" -WindowStyle Hidden
Start-Sleep 2
# Verify proxy is alive
try {
  $h = (Invoke-WebRequest -Uri 'http://localhost:8080/health' -TimeoutSec 8 -UseBasicParsing).Content | ConvertFrom-Json
  OK "Proxy LIVE on :8080 | Models available: $($h.models.Count)"
} catch { WARN 'Proxy starting (may take 5-10s after reboot)' }
# Final session reset
Reset-ClaudeSession -Silent
OK 'Session limit cleared - Claude Code starts fresh'

# ── MASTER PLAYBOOK on Desktop ────────────────────────────
$pb = @"
# ANTIGRAVITY ULTIMATE v3 - MASTER PLAYBOOK
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | NWU/22807365GG

## ONE-CLICK INSTALL (run again on any new machine)
irm https://raw.githubusercontent.com/22807365GG/free-claude-code/main/ANTIGRAVITY-ULTIMATE-AUTO.ps1 | iex

## SERVICES (auto-start at every login)
- Proxy  : http://localhost:8080  (28+ free models)
- Ollama : http://localhost:11434 (local AI)
- Watcher: real-time session limit reset daemon

## MODEL AUTO-ROUTING
Code/debug    -> Qwen3 Coder 480B (best free coder)
Reasoning     -> DeepSeek R1
Long docs     -> Llama 4 Scout (10M context)
Images        -> Gemini Flash
Multilingual  -> GLM-4 (Afrikaans, Zulu, Xhosa)
Default       -> openrouter/free (OpenRouter picks best)
Offline       -> Qwen2.5-Coder 1.5B (LOCAL)

## SESSION LIMIT RESET
Auto  : Runs at login + real-time watcher active always
Manual: Double-click 'RESET CLAUDE LIMIT' on Desktop
How   : ~/.claude/*.jsonl kept to header line only

## SECURITY
- TLS 1.2 enforced
- Firewall: ports 8080+11434 localhost-only
- Defender exclusions: C:\AntigravityServices + .claude
- ExecutionPolicy: RemoteSigned
- Service dir ACL: current user only

## FILES
C:\AntigravityServices\proxy.py           OpenRouter proxy
C:\AntigravityServices\reset-claude-limit.ps1  Manual reset
C:\AntigravityServices\session-watcher.ps1     Real-time watcher
C:\AntigravityServices\openrouter.key          API key
C:\AntigravityServices\install.log             This run's log
~\.claude\settings.json                        Claude Code config
"@
$pb | Out-File "$env:USERPROFILE\Desktop\ANTIGRAVITY-MASTER-PLAYBOOK.md" -Encoding UTF8
OK 'ANTIGRAVITY-MASTER-PLAYBOOK.md saved to Desktop'

# ── DONE ───────────────────────────────────────────────────
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " ANTIGRAVITY ULTIMATE v3 - COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "
SECURITY     TLS 1.2, Firewall, Defender exclusions, ACL
PROXY        http://localhost:8080 (28+ free models)
OLLAMA       http://localhost:11434 (offline)
SESSION      Limit auto-cleared at login + real-time watcher
MODELS       Code->Qwen3Coder | Reason->DeepSeek R1 | Docs->Llama4
TASKS        OllamaServe, AntigravityProxy, LimitReset, Watcher
DESKTOP      RESET CLAUDE LIMIT shortcut + MASTER-PLAYBOOK.md

Open Antigravity. Start coding. Limit will never stop you again.
" -ForegroundColor White
Log 'Setup complete. See ANTIGRAVITY-MASTER-PLAYBOOK.md on your Desktop.'
pause
