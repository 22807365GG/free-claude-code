# =============================================================
# ANTIGRAVITY LOCAL SETTINGS CONFIGURATOR
# Disables cloud profile prompts, enables offline-first mode
# Wires Claude Code (local proxy) + Qwen2.5-Coder:1.5B (Ollama)
# NWU/22807365GG | 2026-06-15
# Run: irm <raw_url> | iex
# =============================================================

Write-Host "`n[AG-CONFIG] Antigravity Offline-First Local Setup" -ForegroundColor Magenta
Write-Host "[AG-CONFIG] Suppressing cloud prompts + wiring local AI engines" -ForegroundColor Cyan

# ---- Locate Antigravity settings paths ----
$agPaths = @(
    "$env:APPDATA\Antigravity\User",
    "$env:LOCALAPPDATA\Antigravity\User",
    "$env:USERPROFILE\.antigravity",
    "$env:APPDATA\Code\User"  # fallback if AG uses VSCode settings
)

$settingsLocations = @()
foreach ($p in $agPaths) {
    if (Test-Path $p) { $settingsLocations += $p }
    else {
        New-Item -ItemType Directory -Force -Path $p | Out-Null
        $settingsLocations += $p
    }
}

Write-Host "[1/5] Config paths ready: $($settingsLocations.Count) location(s)" -ForegroundColor Green

# ---- Build the settings JSON payload ----
$agSettings = @{
    # Disable ALL cloud/account prompts on boot
    "telemetry.telemetryLevel"              = "off"
    "telemetry.enableTelemetry"             = $false
    "update.mode"                           = "none"
    "update.showReleaseNotes"               = $false
    "workbench.startupEditor"               = "none"
    "workbench.colorTheme"                  = "Default Dark Modern"

    # Suppress sign-in / account / cloud profile prompts
    "accounts.preferredAccountForExtensions" = ""
    "github.gitAuthentication"              = $false
    "github.enterprise.uri"                 = ""
    "remote.tunnels.access.preventSleep"    = $false
    "extensions.autoCheckUpdates"           = $false
    "extensions.autoUpdate"                 = $false

    # Antigravity-specific: offline mode flags
    "antigravity.cloudSync.enabled"         = $false
    "antigravity.profile.autoSignIn"        = $false
    "antigravity.profile.showSignInPrompt"  = $false
    "antigravity.telemetry.enabled"         = $false
    "antigravity.update.autoCheck"          = $false
    "antigravity.onboarding.completed"      = $true
    "antigravity.firstRun"                  = $false

    # Claude Code via local proxy (no cloud auth needed)
    "antigravity.claude.endpoint"           = "http://localhost:8080"
    "antigravity.claude.apiKey"             = "local-proxy-no-auth"
    "antigravity.claude.model"              = "claude-3-5-sonnet-20241022"
    "antigravity.claude.useLocalProxy"      = $true

    # Qwen2.5-Coder via Ollama MCP (offline)
    "antigravity.localModel.provider"       = "ollama"
    "antigravity.localModel.endpoint"       = "http://localhost:11434"
    "antigravity.localModel.model"          = "qwen2.5-coder:1.5b"
    "antigravity.localModel.enabled"        = $true
    "antigravity.agent.defaultModel"        = "qwen2.5-coder:1.5b"
    "antigravity.agent.fallbackModel"       = "claude-3-5-sonnet-20241022"

    # MCP server config
    "mcp.servers.ollama.url"               = "http://localhost:11434"
    "mcp.servers.ollama.model"             = "qwen2.5-coder:1.5b"
    "mcp.servers.ollama.enabled"           = $true

    # Editor performance
    "editor.inlineSuggest.enabled"          = $true
    "editor.suggest.showMethods"            = $true
    "files.autoSave"                        = "afterDelay"
    "files.autoSaveDelay"                   = 1000
    "terminal.integrated.defaultProfile.windows" = "PowerShell"
} | ConvertTo-Json -Depth 5

Write-Host "[2/5] Settings JSON built" -ForegroundColor Green

# ---- Write settings.json to all detected paths ----
foreach ($loc in $settingsLocations) {
    $settingsFile = Join-Path $loc "settings.json"
    try {
        # Merge with existing settings if present
        if (Test-Path $settingsFile) {
            $existing = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
            if ($null -eq $existing) { $existing = @{} }
            $new = $agSettings | ConvertFrom-Json -AsHashtable
            foreach ($k in $new.Keys) { $existing[$k] = $new[$k] }
            $existing | ConvertTo-Json -Depth 5 | Set-Content $settingsFile -Encoding UTF8
        } else {
            $agSettings | Set-Content $settingsFile -Encoding UTF8
        }
        Write-Host "   [OK] Written: $settingsFile" -ForegroundColor Green
    } catch {
        Write-Host "   [WARN] Could not write $settingsFile : $_" -ForegroundColor Yellow
    }
}

Write-Host "[3/5] Settings written" -ForegroundColor Green

# ---- Write MCP config.json (Antigravity Agent panel) ----
$mcpConfig = @{
    mcpServers = @{
        "ollama-qwen" = @{
            command = "ollama"
            args = @("serve")
            env = @{}
            disabled = $false
            autoApprove = @("read","write","execute")
        }
    }
    models = @(
        @{
            id = "qwen2.5-coder:1.5b"
            name = "Qwen2.5 Coder 1.5B (Local)"
            provider = "ollama"
            endpoint = "http://localhost:11434/api"
            contextLength = 32768
            offline = $true
        },
        @{
            id = "claude-3-5-sonnet-20241022"
            name = "Claude 3.5 Sonnet (Local Proxy)"
            provider = "anthropic"
            endpoint = "http://localhost:8080"
            apiKey = "local-proxy"
            offline = $false
        }
    )
    defaultModel = "qwen2.5-coder:1.5b"
    offlineMode = $true
    disableCloudSync = $true
} | ConvertTo-Json -Depth 6

foreach ($loc in $settingsLocations) {
    $mcpFile = Join-Path $loc "mcp_config.json"
    try {
        $mcpConfig | Set-Content $mcpFile -Encoding UTF8
        Write-Host "   [OK] MCP config: $mcpFile" -ForegroundColor Green
    } catch {
        Write-Host "   [WARN] $mcpFile : $_" -ForegroundColor Yellow
    }
}

Write-Host "[4/5] MCP config written" -ForegroundColor Green

# ---- Write boot startup script (auto-starts services) ----
$startupScript = @'
# Antigravity Auto-Start: Claude Proxy + Ollama
# Place in: shell:startup folder OR run as scheduled task

$logFile = "$env:TEMP\antigravity-services.log"
"$(Get-Date) Starting Antigravity local services..." | Out-File $logFile -Append

# Start Ollama serve (background)
$ollamaProc = Get-Process ollama -ErrorAction SilentlyContinue
if (-not $ollamaProc) {
    Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
    "$(Get-Date) Ollama started" | Out-File $logFile -Append
}

# Start Claude Code proxy
$claudeProxy = Get-Process -Name "node" -ErrorAction SilentlyContinue | 
    Where-Object { $_.CommandLine -like "*free-claude*" }
if (-not $claudeProxy) {
    $proxyPath = "$env:USERPROFILE\antigravity-proxy"
    if (Test-Path "$proxyPath\package.json") {
        Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command `"Set-Location '$proxyPath'; node index.js`"" -WindowStyle Hidden
        "$(Get-Date) Claude proxy started" | Out-File $logFile -Append
    }
}
"$(Get-Date) All services initialized" | Out-File $logFile -Append
'@

$startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$startupFile = Join-Path $startupPath "antigravity-services.ps1"
try {
    $startupScript | Set-Content $startupFile -Encoding UTF8
    Write-Host "   [OK] Boot startup script: $startupFile" -ForegroundColor Green
} catch {
    Write-Host "   [WARN] Could not write startup script: $_" -ForegroundColor Yellow
}

# Register scheduled task as backup
try {
    $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startupFile`""
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn
    $taskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable
    Register-ScheduledTask -TaskName "AntigravityLocalServices" -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Force -RunLevel Highest | Out-Null
    Write-Host "   [OK] Scheduled task registered: AntigravityLocalServices" -ForegroundColor Green
} catch {
    Write-Host "   [INFO] Scheduled task skipped (may need admin): $_" -ForegroundColor Cyan
}

Write-Host "[5/5] Boot automation configured" -ForegroundColor Green
Write-Host "`n[DONE] Antigravity is now configured for offline-first operation!" -ForegroundColor Magenta
Write-Host "  Claude Code  : http://localhost:8080  (run proxy first)" -ForegroundColor White
Write-Host "  Qwen2.5-Coder: http://localhost:11434 (ollama serve)" -ForegroundColor White
Write-Host "  Sign-in prompts: DISABLED" -ForegroundColor Green
Write-Host "  Cloud sync     : DISABLED" -ForegroundColor Green
Write-Host "  Auto-start     : ENABLED on login" -ForegroundColor Green
