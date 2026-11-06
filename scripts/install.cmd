@echo off
setlocal EnableExtensions
rem Try PowerShell first; fall back to Node when PowerShell is blocked
rem (ExecutionPolicy, AppLocker, Constrained Language Mode).
rem Force the Node path with:  set TRELLIS_NO_POWERSHELL=1
set "HERE=%~dp0"
if /i "%TRELLIS_NO_POWERSHELL%"=="1" goto :node
where powershell >nul 2>nul
if errorlevel 1 goto :nops
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%install.ps1" %*
if not errorlevel 1 exit /b 0
echo.
echo [!] PowerShell failed; falling back to Node.
goto :node
:nops
echo [!] PowerShell not found; using Node.
:node
where node >nul 2>nul
if errorlevel 1 (
  echo ERROR: PowerShell is unavailable and Node was not found.
  exit /b 1
)
node "%HERE%win-fallback.mjs" install %*
exit /b %ERRORLEVEL%
