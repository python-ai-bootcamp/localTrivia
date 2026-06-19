#!/usr/bin/env bash
# ==============================================================================
# deploymentScript.sh
# Production Deployment Automation Script
# ==============================================================================
set -e

# Configured variables (filled by configureDeploymentScript.sh)
DOMAIN="__DOMAIN_PLACEHOLDER__"
EMAIL="__EMAIL_PLACEHOLDER__"
PROJECT_DIR="__PROJECT_DIR_PLACEHOLDER__"
GIT_REPO_URL="__GIT_REPO_URL_PLACEHOLDER__"

# 1. Check if placeholders have been configured
if [[ "$DOMAIN" == *"PLACEHOLDER"* || "$EMAIL" == *"PLACEHOLDER"* || "$PROJECT_DIR" == *"PLACEHOLDER"* || "$GIT_REPO_URL" == *"PLACEHOLDER"* ]]; then
    echo "ERROR: The script is not configured yet."
    echo "Please run './configureDeploymentScript.sh -d <domain> -e <email> [-p <project_dir>] [-g <git_repo_url>]' first."
    exit 1
fi

# 2. Validate that the script is NOT running from inside the project directory
NORM_PROJECT_DIR=$(readlink -f "$PROJECT_DIR" 2>/dev/null || echo "$PROJECT_DIR")
SCRIPT_REAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORM_SCRIPT_DIR=$(readlink -f "$SCRIPT_REAL_DIR" 2>/dev/null || echo "$SCRIPT_REAL_DIR")

if [[ "$NORM_SCRIPT_DIR" == "$NORM_PROJECT_DIR"* ]]; then
    echo "ERROR: deploymentScript.sh cannot be run from inside the project directory ($PROJECT_DIR)."
    echo "Please copy this script outside of the project directory (e.g., to /tmp or your home folder) before running it."
    exit 1
fi

# Function to execute install routine
run_install() {
    echo "=================================================="
    echo "Starting Installation Process..."
    echo "=================================================="

    echo "1. Installing OS dependencies..."
    sudo apt update
    sudo apt install -y git certbot podman podman-compose

    echo "2. Setting up project directory at $PROJECT_DIR..."
    sudo mkdir -p "$PROJECT_DIR"
    sudo chown -R $USER:$USER "$PROJECT_DIR"

    echo "3. Cloning repository..."
    git clone "$GIT_REPO_URL" "$PROJECT_DIR"

    echo "4. Creating production .env configuration..."
    cd "$PROJECT_DIR"
    echo "BASE_URL=https://$DOMAIN" > .env

    echo "5. Generating SSL Certificates..."
    mkdir -p "$PROJECT_DIR/nginx/ssl"
    sudo certbot certonly --standalone \
      -d "$DOMAIN" \
      -d "www.$DOMAIN" \
      --agree-tos \
      --email "$EMAIL" \
      --non-interactive \
      --deploy-hook "cd $PROJECT_DIR && cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem nginx/ssl/ && cp /etc/letsencrypt/live/$DOMAIN/privkey.pem nginx/ssl/ && (podman ps --format '{{.Names}}' | grep -q nginx && podman-compose exec -T nginx nginx -s reload || true)"

    echo "6. Configuring unprivileged port binding limits..."
    sudo sysctl net.ipv4.ip_unprivileged_port_start=80

    echo "7. Starting backend container stack..."
    podman-compose up -d

    echo "=================================================="
    echo "Installation Completed Successfully!"
    echo "Web App URL: https://$DOMAIN"
    echo "API Docs:    https://$DOMAIN/docs"
    echo "=================================================="
}

# Function to execute uninstall routine
run_uninstall() {
    echo "=================================================="
    echo "Starting Uninstall Process..."
    echo "=================================================="

    echo "1. Stopping container stack..."
    if [ -d "$PROJECT_DIR" ]; then
        cd "$PROJECT_DIR"
        podman-compose down || true
    fi

    echo "2. Deleting SSL Certificates from Certbot..."
    sudo certbot delete --cert-name "$DOMAIN" || true

    echo "3. Removing project files..."
    if [[ -n "$PROJECT_DIR" && "$PROJECT_DIR" != "/" && "$PROJECT_DIR" != "/opt" && "$PROJECT_DIR" != "/home"* ]]; then
        sudo rm -rf "$PROJECT_DIR"
        echo "Project files deleted."
    else
        echo "WARNING: Safety guard prevented deleting root/system directory '$PROJECT_DIR'."
    fi

    echo "4. Uninstalling OS packages..."
    sudo apt remove -y --purge certbot podman podman-compose git || true
    sudo apt autoremove -y || true

    echo "=================================================="
    echo "Uninstall Completed."
    echo "=================================================="
}

# Positional arguments parser
case "$1" in
    install)
        run_install
        ;;
    uninstall)
        run_uninstall
        ;;
    reinstall)
        echo "Initiating self-healing reinstall..."
        # Copy current script to temp directory and execute from there 
        # to prevent script crash if it gets deleted from under us
        TEMP_SCRIPT="/tmp/deploymentScript.sh"
        cp "$0" "$TEMP_SCRIPT"
        chmod +x "$TEMP_SCRIPT"
        exec "$TEMP_SCRIPT" reinstall_internal
        ;;
    reinstall_internal)
        run_uninstall
        run_install
        # Cleanup the temp script
        rm -f "$0"
        ;;
    update)
        echo "=================================================="
        echo "Updating Deployment..."
        echo "=================================================="
        if [ ! -d "$PROJECT_DIR" ]; then
            echo "ERROR: Project directory '$PROJECT_DIR' not found. Run install first."
            exit 1
        fi
        cd "$PROJECT_DIR"
        echo "Pulling latest changes from Git..."
        git pull
        echo "Rebuilding and starting containers..."
        podman-compose up -d --build
        echo "Update Completed."
        ;;
    start)
        echo "Starting project..."
        if [ ! -d "$PROJECT_DIR" ]; then
            echo "ERROR: Project directory '$PROJECT_DIR' not found."
            exit 1
        fi
        cd "$PROJECT_DIR"
        if [ "$2" == "--build" ]; then
            echo "Starting with build flag..."
            podman-compose up -d --build
        else
            podman-compose up -d
        fi
        echo "Project started."
        ;;
    stop)
        echo "Stopping project..."
        if [ ! -d "$PROJECT_DIR" ]; then
            echo "ERROR: Project directory '$PROJECT_DIR' not found."
            exit 1
        fi
        cd "$PROJECT_DIR"
        podman-compose down
        echo "Project stopped."
        ;;
    *)
        echo "Usage: $0 {install|uninstall|reinstall|update|start|stop}"
        exit 1
        ;;
esac
