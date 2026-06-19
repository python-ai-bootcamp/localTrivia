#!/usr/bin/env bash
# ==============================================================================
# configureDeploymentScript.sh
# Configuration Helper for deploymentScript.sh
# ==============================================================================
set -e

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --domain <domain>         Production domain name (required, e.g. notarealdomain.io)"
    echo "  -e, --email <email>           Certbot administrator email (required, e.g. sheker.kolsheu@david.com)"
    echo "  -p, --project-dir <path>      Project directory path on host (optional, default: /opt/localTrivia)"
    echo "  -g, --git-repo-url <url>      Git repository URL to clone (optional, default: https://github.com/python-ai-bootcamp/localTrivia.git)"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -d zerodaybootcamp.xyz -e python.ai.bootcamp@outlook.com"
    exit 0
}

# Default values
PROJECT_DIR="/opt/localTrivia"
GIT_REPO_URL="https://github.com/python-ai-bootcamp/localTrivia.git"
DOMAIN=""
EMAIL=""

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -p|--project-dir)
            PROJECT_DIR="$2"
            shift 2
            ;;
        -g|--git-repo-url)
            GIT_REPO_URL="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            show_help
            ;;
    esac
done

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "ERROR: Domain (-d/--domain) and Email (-e/--email) are required parameters."
    echo ""
    show_help
fi

# Detect current script folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/deploymentScript.sh"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "ERROR: Target script '$TARGET_SCRIPT' not found."
    exit 1
fi

# Replace configurations using sed (safely handles repeated calls)
echo "Configuring deploymentScript.sh with:"
echo "  Domain:      $DOMAIN"
echo "  Email:       $EMAIL"
echo "  Project Dir: $PROJECT_DIR"
echo "  Git Repo:    $GIT_REPO_URL"

sed -i "s|^DOMAIN=.*|DOMAIN=\"$DOMAIN\"|g" "$TARGET_SCRIPT"
sed -i "s|^EMAIL=.*|EMAIL=\"$EMAIL\"|g" "$TARGET_SCRIPT"
sed -i "s|^PROJECT_DIR=.*|PROJECT_DIR=\"$PROJECT_DIR\"|g" "$TARGET_SCRIPT"
sed -i "s|^GIT_REPO_URL=.*|GIT_REPO_URL=\"$GIT_REPO_URL\"|g" "$TARGET_SCRIPT"

echo "Configuration completed! You can now copy deploymentScript.sh outside of the project folder and run:"
echo "  ./deploymentScript.sh install"
