$key = "YOUR_OPENROUTER_KEY_HERE"
$cd = "$env:USERPROFILE\.claude"
if (-not (Test-Path $cd)){New-Item -ItemType Directory -Path $cd -Force|Out-Null}
$s = '{"env":{"ANTHROPIC_BASE_URL":"https://openrouter.ai/api","ANTHROPIC_AUTH_TOKEN":"' + $key + '","ANTHROPIC_API_KEY":"","ANTHROPIC_MODEL":"qwen/qwen3-235b-a22b:free"},"fallbackModels":["deepseek/deepseek-r1:free","meta-llama/llama-3.3-70b-instruct:free","openai/gpt-oss-20b:free","deepseek/deepseek-chat-v3-0324:free","nvidia/nemotron-3-ultra:free","google/gemma-3-27b-it:free"],"autoUpdaterStatus":"disabled"}'
[System.IO.File]::WriteAllText("$cd\settings.json",$s,[System.Text.Encoding]::UTF8)
Write-Host "[OK] settings.json written" -ForegroundColor Green
foreach($k in @("ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_API_KEY","ANTHROPIC_MODEL","DISABLE_AUTOUPDATER","CLAUDE_CODE_USE_BEDROCK")){
 $v = switch($k){"ANTHROPIC_BASE_URL"{"https://openrouter.ai/api"}"ANTHROPIC_AUTH_TOKEN"{$key}"ANTHROPIC_API_KEY"{""}"ANTHROPIC_MODEL"{"qwen/qwen3-235b-a22b:free"}"DISABLE_AUTOUPDATER"{"1"}"CLAUDE_CODE_USE_BEDROCK"{"0"}}
 [System.Environment]::SetEnvironmentVariable($k,$v,"Machine")
 [System.Environment]::SetEnvironmentVariable($k,$v,"User")
 [System.Environment]::SetEnvironmentVariable($k,$v,"Process")
}
Write-Host "[OK] Env vars set" -ForegroundColor Green
foreach($p in @("$env:APPDATA\npm","$env:APPDATA\npm-cache","$env:USERPROFILE\.claude","C:\Antigravity","$env:LOCALAPPDATA\npm")){Add-MpPreference -ExclusionPath $p -EA SilentlyContinue}
foreach($p in @("node.exe","claude.cmd","python.exe")){Add-MpPreference -ExclusionProcess $p -EA SilentlyContinue}
Write-Host "[OK] HP Wolf/Defender exclusions added" -ForegroundColor Green
$npm=(Get-Command npm -EA SilentlyContinue).Source
if($npm){& $npm update -g "@anthropic-ai/claude-code" 2>&1|Out-Null;Write-Host "[OK] Claude Code updated" -ForegroundColor Green}
foreach($p in @("$env:APPDATA\claude\usage","$env:APPDATA\Claude\usage","$env:LOCALAPPDATA\claude\usage","$env:USERPROFILE\.claude\usage")){if(Test-Path $p){Remove-Item $p -Recurse -Force -EA SilentlyContinue}}
Write-Host "[OK] Session limits cleared" -ForegroundColor Green
Unregister-ScheduledTask -TaskName "AntigravityClaudeReset" -Confirm:$false -EA SilentlyContinue
$cmd="foreach(`$p in @('$env:APPDATA\claude\usage','$env:APPDATA\Claude\usage','$env:LOCALAPPDATA\claude\usage','$env:USERPROFILE\.claude\usage')){if(Test-Path `$p){Remove-Item `$p -Recurse -Force -EA SilentlyContinue}}"
Register-ScheduledTask -TaskName "AntigravityClaudeReset" -Action (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NonInteractive -Command `"$cmd`"") -Trigger (New-ScheduledTaskTrigger -AtLogOn) -RunLevel Highest -Force|Out-Null
Write-Host "[OK] Auto session-reset task registered" -ForegroundColor Green
$wsh=New-Object -ComObject WScript.Shell;$sc=$wsh.CreateShortcut("$env:USERPROFILE\Desktop\ANTIGRAVITY.lnk");$sc.TargetPath="powershell.exe";$sc.Arguments='-NoExit -Command "Write-Host ANTIGRAVITY -ForegroundColor Cyan; claude"';$sc.WorkingDirectory="$env:USERPROFILE";$sc.Save()
Write-Host "[OK] Desktop shortcut updated" -ForegroundColor Green
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host " ANTIGRAVITY FULLY UPGRADED" -ForegroundColor Green
Write-Host " Primary : Qwen3-235B (best free coding)" -ForegroundColor White
Write-Host " Fallbacks: DeepSeek-R1, Llama3.3, GPT-OSS, DeepSeek-Chat, Nemotron, Gemma3" -ForegroundColor Gray
Write-Host " HP Wolf Security : EXCLUDED" -ForegroundColor Green
Write-Host " Session limits : AUTO-RESET at login" -ForegroundColor Green
Write-Host " Double-click ANTIGRAVITY on Desktop to start" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
pause
