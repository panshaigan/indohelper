@echo off

if "%~1"=="" (
    echo Error: No mod list file name provided.
    pause
    exit /b 1
)

:: Call the PowerShell script with the parameter
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\update.ps1 -modFileName "%~1"

pause