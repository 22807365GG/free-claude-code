# =============================================================
# FULL AUTO-INSTALL: Claude Proxy + Ollama as Windows Services
# Finds Antigravity folder, installs proxy inside, registers as services
# Starts automatically on every boot - no terminal needed ever
# NWU/22807365GG | 2026-06-15
# Run: irm <raw_url> | iex  (AS ADMIN)
# =============================================================

#Requires -RunAsAdministrator

Write-Host "`n[INSTALL] Antigravity Service Installer - Full Auto" -ForegroundColor Magenta
Write-Host "This will install and register Claude Code + Qwen2.5-Coder as Windows Services" -ForegroundColor Cyan

# ---- STEP 1: Locate Antigravity installation ----
Write-Host "`n[1/6] Locating Antigravity installation..." -ForegroundColor Cyan

$agPaths = @(
    "$env:LOCALAPPDATA\Programs\Antigravity",
    "$env:PROGRAMFILES\Antigravity",
    "${env:PROGRAMFILES(x86)}\Antigravity",
    "$env:APPDATA\Antigravity",
    "C:\Antigravity"
)

$agRoot = $null
foreach ($p in $agPaths) {
    if (Test-Path "$p\Antigravity.exe" -or Test-Path "$p\Code.exe" -or Test-Path $p) {
        $agRoot = $p
        break
    }
}

if (-not $agRoot) {
    # Fallback: create in AppData
    $agRoot = "$env:LOCALAPPDATA\Antigravity"
    New-Item -ItemType Directory -Force -Path $agRoot | Out-Null
}

Write-Host "  [OK] Antigravity root: $agRoot" -ForegroundColor Green

# ---- STEP 2: Install Claude proxy inside Antigravity folder ----
Write-Host "`n[2/6] Installing Claude proxy..." -ForegroundColor Cyan

$proxyDir = Join-Path $agRoot "claude-proxy"
if (-not (Test-Path $proxyDir)) {
    New-Item -ItemType Directory -Force -Path $proxyDir | Out-Null
}

# Create package.json
$packageJson = @'
{
  "name": "antigravity-claude-proxy",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "http-proxy-middleware": "^2.0.6"
  }
}
'@
$packageJson | Set-Content "$proxyDir\package.json" -Encoding UTF8

# Create server.js (simple express proxy)
$serverJs = @'
const express = require("express");
const { createProxyMiddleware } = require("http-proxy-middleware");
const app = express();
const PORT = process.env.PORT || 8080;

app.get("/health", (req, res) => {
  res.json({ status: "ok", service: "antigravity-claude-proxy", port: PORT });
});

// Proxy to free-claude-code OAuth flow
// This assumes the user has run `claude auth` once to save their token
app.use("/v1", createProxyMiddleware({
  target: "https://api.anthropic.com",
  changeOrigin: true,
  pathRewrite: { "^/v1": "/v1" },
  on: {
    proxyReq: (proxyReq, req) => {
      // Read saved credentials from claude CLI config
      const fs = require("fs");
      const path = require("path");
      const os = require("os");
      const configPath = path.join(os.homedir(), ".claude", "config.json");
      
      try {
        if (fs.existsSync(configPath)) {
          const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
          if (config.api_key) {
            proxyReq.setHeader("x-api-key", config.api_key);
          }
        }
      } catch (e) {
        console.warn("[PROXY] No saved API key found - run: claude auth");
      }
      
      proxyReq.setHeader("anthropic-version", "2023-06-01");
    },
    error: (err, req, res) => {
      console.error("[PROXY ERROR]", err.message);
      res.status(502).json({ error: err.message });
    }
  }
}));

app.listen(PORT, "127.0.0.1", () => {
  console.log(`[PROXY] Listening on http://127.0.0.1:${PORT}`);
});
'@
$serverJs | Set-Content "$proxyDir\server.js" -Encoding UTF8

Write-Host "  [..] Installing npm dependencies (this may take 30s)..." -ForegroundColor Yellow
Set-Location $proxyDir
npm install --silent --no-progress 2>&1 | Out-Null
Write-Host "  [OK] Proxy installed: $proxyDir" -ForegroundColor Green

# ---- STEP 3: Download NSSM (service wrapper) ----
Write-Host "`n[3/6] Downloading NSSM (service manager)..." -ForegroundColor Cyan

$nssmDir = Join-Path $agRoot "nssm"
if (-not (Test-Path $nssmDir)) {
    New-Item -ItemType Directory -Force -Path $nssmDir | Out-Null
}

$nssmExe = Join-Path $nssmDir "nssm.exe"
if (-not (Test-Path $nssmExe)) {
    $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
    $zipPath = Join-Path $env:TEMP "nssm.zip"
    
    Write-Host "  [..] Downloading from nssm.cc..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $nssmUrl -OutFile $zipPath -UseBasicParsing
    
    Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
    
    # Copy correct architecture
    $arch = if ([Environment]::Is64BitOperatingSystem) { "win64" } else { "win32" }
    Copy-Item "$env:TEMP\nssm-2.24\$arch\nssm.exe" $nssmExe -Force
    
    Remove-Item $zipPath -Force
    Remove-Item "$env:TEMP\nssm-2.24" -Recurse -Force
}

Write-Host "  [OK] NSSM ready: $nssmExe" -ForegroundColor Green

# ---- STEP 4: Register Ollama as Windows Service ----
Write-Host "`n[4/6] Registering Ollama as Windows Service..." -ForegroundColor Cyan

$ollamaExe = (Get-Command ollama -ErrorAction SilentlyContinue).Source
if (-not $ollamaExe) {
    Write-Host "  [WARN] Ollama not found in PATH - install it first: https://ollama.com" -ForegroundColor Yellow
} else {
    # Check if service already exists
    $existingOllama = Get-Service -Name "OllamaService" -ErrorAction SilentlyContinue
    if ($existingOllama) {
        Write-Host "  [..] Service already exists - removing old registration..." -ForegroundColor Yellow
        Stop-Service OllamaService -Force -ErrorAction SilentlyContinue
        & $nssmExe remove OllamaService confirm
    }
    
    & $nssmExe install OllamaService "$ollamaExe" "serve"
    & $nssmExe set OllamaService AppDirectory (Split-Path $ollamaExe)
    & $nssmExe set OllamaService DisplayName "Ollama - Local AI Models"
    & $nssmExe set OllamaService Description "Runs Ollama server for Qwen2.5-Coder and other local models"
    & $nssmExe set OllamaService Start SERVICE_AUTO_START
    & $nssmExe set OllamaService AppStdout "$agRoot\logs\ollama-stdout.log"
    & $nssmExe set OllamaService AppStderr "$agRoot\logs\ollama-stderr.log"
    
    New-Item -ItemType Directory -Force -Path "$agRoot\logs" | Out-Null
    
    Start-Service OllamaService
    Write-Host "  [OK] OllamaService registered and started" -ForegroundColor Green
}

# ---- STEP 5: Register Claude Proxy as Windows Service ----
Write-Host "`n[5/6] Registering Claude Proxy as Windows Service..." -ForegroundColor Cyan

$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeExe) {
    Write-Host "  [FAIL] Node.js not found - install it first: https://nodejs.org" -ForegroundColor Red
    exit 1
}

$existingClaude = Get-Service -Name "ClaudeProxyService" -ErrorAction SilentlyContinue
if ($existingClaude) {
    Write-Host "  [..] Service already exists - removing old registration..." -ForegroundColor Yellow
    Stop-Service ClaudeProxyService -Force -ErrorAction SilentlyContinue
    & $nssmExe remove ClaudeProxyService confirm
}

$serverJsPath = Join-Path $proxyDir "server.js"
& $nssmExe install ClaudeProxyService "$nodeExe" "\"$serverJsPath\""
& $nssmExe set ClaudeProxyService AppDirectory "$proxyDir"
& $nssmExe set ClaudeProxyService DisplayName "Claude Code Local Proxy"
& $nssmExe set ClaudeProxyService Description "Local proxy for Claude Code integration with Antigravity IDE"
& $nssmExe set ClaudeProxyService Start SERVICE_AUTO_START
& $nssmExe set ClaudeProxyService AppEnvironmentExtra "PORT=8080"
& $nssmExe set ClaudeProxyService AppStdout "$agRoot\logs\claude-proxy-stdout.log"
& $nssmExe set ClaudeProxyService AppStderr "$agRoot\logs\claude-proxy-stderr.log"

Start-Service ClaudeProxyService
Write-Host "  [OK] ClaudeProxyService registered and started" -ForegroundColor Green

# ---- STEP 6: Verify services are running ----
Write-Host "`n[6/6] Verifying services..." -ForegroundColor Cyan

Start-Sleep 3

# Check Ollama
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -UseBasicParsing
    Write-Host "  [OK] Ollama responding on :11434" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Ollama not responding yet - check logs: $agRoot\logs\ollama-stderr.log" -ForegroundColor Yellow
}

# Check Claude proxy
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 5 -UseBasicParsing
    Write-Host "  [OK] Claude proxy responding on :8080" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Proxy not responding yet - check logs: $agRoot\logs\claude-proxy-stderr.log" -ForegroundColor Yellow
}

# ---- DONE ----
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host " INSTALLATION COMPLETE" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "
Services installed:" -ForegroundColor White
Write-Host "  - OllamaService      : AUTO-START (Qwen2.5-Coder)" -ForegroundColor Green
Write-Host "  - ClaudeProxyService : AUTO-START (Claude Code)" -ForegroundColor Green
Write-Host "
Proxy location: $proxyDir" -ForegroundColor White
Write-Host "Logs location : $agRoot\logs" -ForegroundColor White
Write-Host "
On next reboot:" -ForegroundColor Cyan
Write-Host "  Both services start automatically - no terminal needed" -ForegroundColor Green
Write-Host "  Just open Antigravity and start coding!" -ForegroundColor Green
Write-Host "
Manage services:" -ForegroundColor White
Write-Host "  services.msc  (open Services control panel)" -ForegroundColor Gray
Write-Host "  Or: Get-Service Ollama*,Claude* | Restart-Service" -ForegroundColor Gray
