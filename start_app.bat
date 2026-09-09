@echo off
setlocal

cd /d "%~dp0"

where Rscript >nul 2>nul
if errorlevel 1 (
  echo Rscript was not found on PATH.
  echo Install R or add its bin directory to PATH, then run this script again.
  pause
  exit /b 1
)

set "DEFAULT_PORT=3838"
set "PORT="

rem Select the default port when available; otherwise use the next free port.
for /L %%P in (%DEFAULT_PORT%,1,3938) do (
  powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort %%P -State Listen -ErrorAction SilentlyContinue) { exit 1 } else { exit 0 }" >nul 2>nul
  if not errorlevel 1 if not defined PORT set "PORT=%%P"
)

if not defined PORT (
  echo No available port was found in the range %DEFAULT_PORT%-3938.
  pause
  exit /b 1
)

echo Starting the Shiny app at http://127.0.0.1:%PORT%
echo Close this window or press Ctrl+C to stop the app.
Rscript -e "shiny::runApp('.', host='127.0.0.1', port=%PORT%, launch.browser=TRUE)"

if errorlevel 1 (
  echo.
  echo The Shiny app exited with an error.
  pause
)

endlocal
