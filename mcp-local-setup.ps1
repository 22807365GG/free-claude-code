# ============================================================
# LOCAL MCP CONFIGURATION - Antigravity IDE + Ollama
# Wires Qwen2.5-Coder:1.5B into Antigravity Agent Chat Panel
# NWU/22807365GG | 2026-06-15
# Run: irm <raw_url> | iex  (in Antigravity terminal)
# ============================================================

Write-Host "`n[MCP] Antigravity Local MCP Setup - Qwen2.5-Coder:1.5B" -ForegroundColor Magenta
Write-Host "[MCP] This wires your local Ollama engine into Antigravity Agent Chat" -ForegroundColor Cyan

# ---- STEP 1: Check/Install Ollama ----
Write-Host "`n[1/5] Checking Ollama..." -ForegroundColor Cyan
try {
    $ov = ollama --version 2>&1
    Write-Host "[OK] Ollama found: $ov" -ForegroundColor Green
} catch {
    Write-Host "[..] Installing Ollama for Windows..." -ForegroundColor Yellow
    $ollamaInstaller = "$env:TEMP\OllamaSetup.exe"
    Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $ollamaInstaller
    Start-Process -FilePath $ollamaInstaller -ArgumentList "/silent" -Wait
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + $env:PATH
    Write-Host "[OK] Ollama installed" -ForegroundColor Green
}

# ---- STEP 2: Pull Qwen2.5-Coder:1.5B model ----
Write-Host "`n[2/5] Pulling qwen2.5-coder:1.5b (this may take a few minutes)..." -ForegroundColor Cyan
try {
    # Start ollama serve in background if not running
    $ollamaRunning = Get-Process ollama -ErrorAction SilentlyContinue
    if (-not $ollamaRunning) {
        Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 3
    }
    ollama pull qwen2.5-coder:1.5b
    Write-Host "[OK] qwen2.5-coder:1.5b pulled successfully" -ForegroundColor Green
} catch {
    Write-Host "[!!] Could not pull model - ensure internet connection" -ForegroundColor Yellow
    Write-Host "     Run manually: ollama pull qwen2.5-coder:1.5b" -ForegroundColor White
}

# ---- STEP 3: Write mcp_config.json ----
Write-Host "`n[3/5] Writing MCP configuration..." -ForegroundColor Cyan

# Antigravity/VS Code MCP config locations (try all)
$mcpLocations = @(
    "$env:APPDATA\Antigravity\User\mcp_config.json",
    "$env:APPDATA\Code\User\mcp_config.json",
    "$env:USERPROFILE\.antigravity\mcp_config.json",
    (Join-Path (Get-Location) "mcp_config.json")
)

$mcpSchema = @'
{
  "mcpServers": {
    "ollama-local-bridge": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-ollama",
        "--endpoint",
        "http://localhost:11434"
      ],
      "env": {
        "OLLAMA_MODEL": "qwen2.5-coder:1.5b"
      }
    }
  }
}
'@

# Write to workspace root (Antigravity picks this up automatically)
$workspaceMcp = Join-Path (Get-Location) "mcp_config.json"
Set-Content -Path $workspaceMcp -Value $mcpSchema -Encoding UTF8
Write-Host "[OK] mcp_config.json written to workspace: $workspaceMcp" -ForegroundColor Green

# Also write to Antigravity/VS Code global user settings
$globalDirs = @(
    "$env:APPDATA\Antigravity\User",
    "$env:APPDATA\Code\User",
    "$env:USERPROFILE\.antigravity"
)
foreach ($dir in $globalDirs) {
    if (Test-Path (Split-Path $dir -Parent)) {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Content -Path (Join-Path $dir "mcp_config.json") -Value $mcpSchema -Encoding UTF8
        Write-Host "[OK] Also written to: $dir\mcp_config.json" -ForegroundColor Green
    }
}

# ---- STEP 4: Install MCP Ollama server package ----
Write-Host "`n[4/5] Installing @modelcontextprotocol/server-ollama..." -ForegroundColor Cyan
try {
    npm install -g @modelcontextprotocol/server-ollama 2>&1 | Out-Null
    Write-Host "[OK] @modelcontextprotocol/server-ollama installed" -ForegroundColor Green
} catch {
    Write-Host "[OK] Will use npx on-demand (no global install needed)" -ForegroundColor Green
}

# ---- STEP 5: Update .vscode/settings.json for Antigravity ----
Write-Host "`n[5/5] Updating Antigravity workspace settings..." -ForegroundColor Cyan
$vsDir = Join-Path (Get-Location) ".vscode"
New-Item -ItemType Directory -Path $vsDir -Force | Out-Null
$vsSettings = Join-Path $vsDir "settings.json"

# Read existing settings if present
if (Test-Path $vsSettings) {
    $existing = Get-Content $vsSettings -Raw | ConvertFrom-Json
} else {
    $existing = [PSCustomObject]@{}
}

# Add MCP and Ollama settings
$existing | Add-Member -NotePropertyName "mcp.enabled" -NotePropertyValue $true -Force
$existing | Add-Member -NotePropertyName "mcp.configPath" -NotePropertyValue "./mcp_config.json" -Force
$existing | Add-Member -NotePropertyName "ollama.endpoint" -NotePropertyValue "http://localhost:11434" -Force
$existing | Add-Member -NotePropertyName "ollama.defaultModel" -NotePropertyValue "qwen2.5-coder:1.5b" -Force

$existing | ConvertTo-Json -Depth 10 | Set-Content $vsSettings -Encoding UTF8
Write-Host "[OK] .vscode/settings.json updated with MCP config" -ForegroundColor Green

# ---- Final: Start Ollama serve in background ----
$ollamaRunning = Get-Process ollama -ErrorAction SilentlyContinue
if (-not $ollamaRunning) {
    Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
    Write-Host "[OK] Ollama serve started in background" -ForegroundColor Green
} else {
    Write-Host "[OK] Ollama already running" -ForegroundColor Green
}

Write-Host @"

====================================================
  MCP LOCAL SETUP COMPLETE!
====================================================
  Qwen2.5-Coder:1.5B is now wired into Antigravity

  In Antigravity Agent Chat panel:
  1. Click the Refresh icon next to the model list
  2. Click the model dropdown
  3. Select: Ollama / qwen2.5-coder:1.5b

  OR press Ctrl+Shift+P:
  -> Type: Open MCP Configuration JSON

  Config file: mcp_config.json (workspace root)
  Ollama endpoint: http://localhost:11434
  Model: qwen2.5-coder:1.5b
  Quota: UNLIMITED (100% local)
====================================================
"@ -ForegroundColor Magenta
