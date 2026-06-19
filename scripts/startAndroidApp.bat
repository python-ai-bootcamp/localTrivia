@echo off
SETLOCAL

:: Get the optional domain argument
set DOMAIN=%1
set DART_DEFINES=

if not "%DOMAIN%"=="" (
    :: Default assuming standard domain
    set BASE_URL=https://%DOMAIN%
    set WS_URL=wss://%DOMAIN%/ws

    :: Check if it starts with http
    echo %DOMAIN% | findstr /i "^http" >nul
    if %ERRORLEVEL% equ 0 (
        set BASE_URL=%DOMAIN%
        :: Fallback WS URL
        set WS_URL=%DOMAIN%/ws
    )

    :: Check if it contains a port (colon) but no http
    echo %DOMAIN% | findstr /c:":" >nul
    if %ERRORLEVEL% equ 0 (
        echo %DOMAIN% | findstr /i "http" >nul
        if %ERRORLEVEL% neq 0 (
            set BASE_URL=http://%DOMAIN%
            set WS_URL=ws://%DOMAIN%/ws
        )
    )

    set DART_DEFINES=--dart-define=BASE_URL=%BASE_URL% --dart-define=WS_URL=%WS_URL%
    echo Configured for server: BASE_URL=%BASE_URL%, WS_URL=%WS_URL%
) else (
    echo Configured for local dev fallback (localhost)
)

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
    echo WARNING: Failed to set up ADB port forwarding.
    if "%DOMAIN%"=="" (
        echo ERROR: Make sure your phone is connected and USB debugging is enabled.
        pause
        exit /b 1
    ) else (
        echo Continuing because a remote domain (%DOMAIN%) is specified.
    )
)

echo Starting Flutter application on connected device...
cd /d "%~dp0\..\frontend"
flutter run %DART_DEFINES%
