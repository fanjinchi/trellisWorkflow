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
if not errorlevel 1 goto :done
echo.
echo [!] PowerShell failed; falling back to Node.
goto :node
:nops
echo [!] PowerShell not found; using Node.
:node
where node >nul 2>nul
if errorlevel 1 (
  echo ERROR: PowerShell is unavailable and Node was not found.
  set "RC=1"
  goto :done
)
node "%HERE%win-fallback.mjs" install %*
set "RC=%ERRORLEVEL%"
goto :done
:done
if not defined RC set "RC=0"
rem Pause only when double-clicked, so terminal and CI invocation are not blocked.
echo %cmdcmdline% | find /i "%~nx0" >nul
if not errorlevel 1 pause
exit /b %RC%
