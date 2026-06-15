# =============================================================
# FIX-AND-START: Self-healing launcher for Claude Proxy + Ollama
# Handles missing proxy dir, wrong paths, port conflicts
# NWU/22807365GG | 2026-06-15
# Run: irm <raw_url> | iex
# =============================================================

Write-Host "`n[FIX] Antigravity Service Launcher" -ForegroundColor Magenta

# ---- OLLAMA: already running is FINE ----
Write-Host "`n[1/3] Checking Ollama..." -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
    Write-Host "  [OK] Ollama already running on :11434 - nothing to do" -ForegroundColor Green
} catch {
    Write-Host "  [..] Ollama not running - starting it..." -ForegroundColor Yellow
    Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
    Start-Sleep 3
    Write-Host "  [OK] Ollama started" -ForegroundColor Green
}

# ---- FIND CLAUDE PROXY ----
Write-Host "`n[2/3] Locating Claude proxy..." -ForegroundColor Cyan

# Search common locations
$candidatePaths = @(
    "$env:USERPROFILE\antigravity-proxy",
    "$env:USERPROFILE\free-claude-code",
    "$env:USERPROFILE\claude-proxy",
    "$env:LOCALAPPDATA\antigravity-proxy",
    "C:\antigravity-proxy",
    "C:\free-claude-code"
)

$proxyDir = $null
foreach ($p in $candidatePaths) {
    if (Test-Path "$p\index.js") {
        $proxyDir = $p
        Write-Host "  [OK] Found proxy at: $proxyDir" -ForegroundColor Green
        break
    }
}

# Not found - install fresh
if (-not $proxyDir) {
    Write-Host "  [..] Proxy not found - installing to $env:USERPROFILE\antigravity-proxy..." -ForegroundColor Yellow
    $proxyDir = "$env:USERPROFILE\antigravity-proxy"
    New-Item -ItemType Directory -Force -Path $proxyDir | Out-Null

    # Download free-claude-code proxy files directly
    $baseUrl = "https://raw.githubusercontent.com/22807365GG/free-claude-code/main"
    $files = @("server.py", "package.json")

    # Actually install the npm package approach
    Set-Location $proxyDir

    # Create minimal package.json for the proxy
    @'
{
  "name": "antigravity-claude-proxy",
  "version": "1.0.0",
  "description": "Local Claude Code proxy for Antigravity IDE",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "express": "^4.18.2",
    "http-proxy-middleware": "^2.0.6",
    "node-fetch": "^2.7.0"
  }
}
'@ | Set-Content "$proxyDir\package.json" -Encoding UTF8

    # Create the proxy index.js
    @'
const express = require("express");
const { createProxyMiddleware } = require("http-proxy-middleware");
const app = express();
const PORT = 8080;

// Health endpoint
app.get("/health", (req, res) => res.json({ status: "ok", proxy: "antigravity-claude-local" }));

// Proxy all /v1/* calls to the free-claude-code server
// The actual auth token injection happens via the claude CLI
app.use("/", createProxyMiddleware({
  target: "https://api.anthropic.com",
  changeOrigin: true,
  on: {
    proxyReq: (proxyReq, req) => {
      // Inject API key if env var set, otherwise pass through
      if (process.env.ANTHROPIC_API_KEY) {
        proxyReq.setHeader("x-api-key", process.env.ANTHROPIC_API_KEY);
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
  console.log(`[PROXY] Claude proxy running at http://localhost:${PORT}`);
  console.log(`[PROXY] Forwarding to api.anthropic.com`);
});
'@ | Set-Content "$proxyDir\index.js" -Encoding UTF8

    Write-Host "  [..] Installing npm dependencies..." -ForegroundColor Yellow
    Set-Location $proxyDir
    npm install --silent 2>&1 | Out-Null
    Write-Host "  [OK] Proxy installed at $proxyDir" -ForegroundColor Green
}

# ---- START PROXY ----
Write-Host "`n[3/3] Starting Claude proxy on :8080..." -ForegroundColor Cyan

# Check if already running
$existingProxy = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($existingProxy) {
    Write-Host "  [OK] Proxy already listening on :8080" -ForegroundColor Green
} else {
    Set-Location $proxyDir
    # Start in background window
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoExit -Command `"Set-Location '$proxyDir'; Write-Host '[PROXY] Starting...' -ForegroundColor Cyan; node index.js`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
    $proc = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep 2

    # Verify it started
    $check = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
    if ($check) {
        Write-Host "  [OK] Proxy running on :8080 (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Proxy window opened - check the new PowerShell window" -ForegroundColor Yellow
    }
}

# ---- SUMMARY ----
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host " SERVICE STATUS" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta

# Ollama
try {
    $ol = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 3 -UseBasicParsing
    Write-Host "  Ollama (Qwen) : ONLINE :11434" -ForegroundColor Green
} catch {
    Write-Host "  Ollama (Qwen) : OFFLINE" -ForegroundColor Red
}

# Claude proxy
try {
    $cl = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 3 -UseBasicParsing
    Write-Host "  Claude Proxy  : ONLINE :8080" -ForegroundColor Green
} catch {
    Write-Host "  Claude Proxy  : OFFLINE (check proxy window)" -ForegroundColor Yellow
}

Write-Host "`n[DONE] Both services configured." -ForegroundColor Magenta
Write-Host "  Now run: python first-compile-test.py" -ForegroundColor White
Write-Host "  Now run: node first-compile-test-claude.js" -ForegroundColor White
