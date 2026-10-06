@echo off
setlocal
cd /d "%~dp0"
echo [*] Building STABLE GUI package...
where wsl >nul 2>&1
if %ERRORLEVEL% equ 0 (
    wsl bash -c "./inizialize_gui.sh"
) else (
    bash -c "./inizialize_gui.sh"
)
if %ERRORLEVEL% neq 0 (
    echo [!] Build failed!
) else (
    echo [+] STABLE Build completed successfully in compressed\
)
pause