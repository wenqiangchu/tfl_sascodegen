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

echo Checking ports %DEFAULT_PORT%-3938...

rem Check each candidate port using the native netstat command.
for /L %%P in (%DEFAULT_PORT%,1,3938) do (
  if not defined PORT (
    netstat -ano | findstr /R /C:":%%P .*LISTENING" >nul 2>nul
    if errorlevel 1 set "PORT=%%P"
  )
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
