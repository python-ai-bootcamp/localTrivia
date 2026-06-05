#!/bin/bash

# Get the directory of the script and resolve project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$( dirname "$SCRIPT_DIR" )"

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
    echo "ERROR: Failed to set up ADB port forwarding. Make sure your phone is connected and USB debugging is enabled."
    exit 1
fi

echo "Starting Flutter application on connected device..."
cd "$PROJECT_ROOT/frontend"
flutter run
