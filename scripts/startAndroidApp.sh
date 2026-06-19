#!/bin/bash

# Get the directory of the script and resolve project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$( dirname "$SCRIPT_DIR" )"

DOMAIN="$1"
DART_DEFINES=""

if [ -n "$DOMAIN" ]; then
    # Parse domain parameter to build BASE_URL and WS_URL
    if [[ "$DOMAIN" == http* ]]; then
        BASE_URL="$DOMAIN"
        # Substitute http protocol for ws protocol in WS_URL
        WS_URL=$(echo "$BASE_URL/ws" | sed -e 's/^https/wss/' -e 's/^http/ws/')
    elif [[ "$DOMAIN" == *":"* ]]; then
        # Contains a port, e.g. 192.168.1.50:8080, assume http
        BASE_URL="http://$DOMAIN"
        WS_URL="ws://$DOMAIN/ws"
    else
        # Standard domain, e.g. zerodaybootcamp.xyz, assume secure https
        BASE_URL="https://$DOMAIN"
        WS_URL="wss://$DOMAIN/ws"
    fi
    DART_DEFINES="--dart-define=BASE_URL=$BASE_URL --dart-define=WS_URL=$WS_URL"
    echo "Configured for server: BASE_URL=$BASE_URL, WS_URL=$WS_URL"
else
    echo "Configured for local dev fallback (localhost)"
fi

# Find ADB executable
ADB_CMD="adb"
if ! command -v adb &> /dev/null; then
    if [ -f "/c/Android/Sdk/platform-tools/adb.exe" ]; then
        ADB_CMD="/c/Android/Sdk/platform-tools/adb.exe"
    elif [ -f "C:\\Android\\Sdk\\platform-tools\\adb.exe" ]; then
        ADB_CMD="C:\\Android\\Sdk\\platform-tools\\adb.exe"
    else
        echo "WARNING: adb command not found in PATH or at C:\\Android\\Sdk\\platform-tools\\adb.exe"
    fi
fi

echo "Setting up ADB Reverse Port Forwarding for port 8080..."
$ADB_CMD reverse tcp:8080 tcp:8080

if [ $? -eq 0 ]; then
    echo "ADB port forwarding set up successfully!"
else
    echo "WARNING: Failed to set up ADB port forwarding."
    if [ -z "$DOMAIN" ]; then
        echo "ERROR: Make sure your phone is connected and USB debugging is enabled."
        exit 1
    else
        echo "Continuing because a remote domain ($DOMAIN) is specified."
    fi
fi

echo "Starting Flutter application on connected device..."
cd "$PROJECT_ROOT/frontend"
flutter run $DART_DEFINES
