@echo off
setlocal enabledelayedexpansion

echo Checking for OpenSSL...
where openssl >nul 2>nul
if %errorlevel% neq 0 (
    echo OpenSSL not found in PATH. Checking common Git locations...
    if exist "C:\Program Files\Git\usr\bin\openssl.exe" (
        set "OPENSSL_PATH=C:\Program Files\Git\usr\bin\openssl.exe"
    ) else if exist "C:\Program Files\Git\bin\openssl.exe" (
        set "OPENSSL_PATH=C:\Program Files\Git\bin\openssl.exe"
    ) else (
        echo OpenSSL was not found. Please install Git or OpenSSL and ensure it is in your PATH.
        exit /b 1
    )
) else (
    set "OPENSSL_PATH=openssl"
)

echo Using OpenSSL: !OPENSSL_PATH!

set "SSL_DIR=%~dp0..\nginx\ssl"
if not exist "!SSL_DIR!" mkdir "!SSL_DIR!"

echo Generating self-signed certificate...
"!OPENSSL_PATH!" req -x509 -nodes -days 365 -newkey rsa:2048 ^
  -keyout "!SSL_DIR!\privkey.pem" ^
  -out "!SSL_DIR!\fullchain.pem" ^
  -subj "/CN=localhost/O=Local Trivia/C=US" ^
  -addext "subjectAltName=DNS:localhost,DNS:trivia.local,IP:127.0.0.1"

if %errorlevel% equ 0 (
    echo Certificates generated successfully in !SSL_DIR!
) else (
    echo Certificate generation failed.
    exit /b 1
)
