@echo off
setlocal
cd /d "%~dp0"
echo [*] Building DEV GUI package...
where wsl >nul 2>&1
if %ERRORLEVEL% equ 0 (
    wsl bash -c "./inizialize_gui.sh dev"
) else (
    bash -c "./inizialize_gui.sh dev"
)
if %ERRORLEVEL% neq 0 (
    echo [!] Build failed!
) else (
    echo [+] DEV Build completed successfully in compressed\
)
pause