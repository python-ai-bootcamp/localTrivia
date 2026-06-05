@echo off
SETLOCAL

:: Find ADB executable
where adb >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set ADB_CMD=adb
) else (
    if exist "C:\Android\Sdk\platform-tools\adb.exe" (
        set ADB_CMD="C:\Android\Sdk\platform-tools\adb.exe"
    ) else (
        echo WARNING: adb command not found in PATH or at C:\Android\Sdk\platform-tools\adb.exe
        set ADB_CMD=adb
    )
)

echo Setting up ADB Reverse Port Forwarding for port 8080...
%ADB_CMD% reverse tcp:8080 tcp:8080
if %ERRORLEVEL% EQU 0 (
    echo ADB port forwarding set up successfully!
) else (
    echo ERROR: Failed to set up ADB port forwarding. Make sure your phone is connected and USB debugging is enabled.
    pause
    exit /b 1
)

echo Starting Flutter application on connected device...
cd /d "%~dp0\..\frontend"
flutter run
