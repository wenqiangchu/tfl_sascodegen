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

echo Starting the Shiny app at http://127.0.0.1:3838
echo Close this window or press Ctrl+C to stop the app.
Rscript -e "shiny::runApp('.', host='127.0.0.1', port=3838, launch.browser=TRUE)"

if errorlevel 1 (
  echo.
  echo The Shiny app exited with an error.
  pause
)

endlocal
