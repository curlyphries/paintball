#!/usr/bin/env bash
set -euo pipefail

# Paintball Arena — one-command deploy
# Usage: ./deploy.sh
#
# Exports the game to HTML5 and starts the Docker stack.
# Requires: Godot 4.6+, Docker, Docker Compose

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Find Godot binary ---
GODOT=""
if command -v godot &>/dev/null; then
    GODOT="godot"
elif command -v godot4 &>/dev/null; then
    GODOT="godot4"
elif flatpak list 2>/dev/null | grep -q org.godotengine.Godot; then
    GODOT="flatpak run org.godotengine.Godot"
fi

if [ -z "$GODOT" ]; then
    echo "ERROR: Godot 4.6+ not found."
    echo "Install via: https://godotengine.org/download"
    echo "  or: flatpak install org.godotengine.Godot"
    exit 1
fi

echo "Using Godot: $GODOT"

# --- Check export templates ---
echo "Checking export templates..."
TEMPLATES_DIR=""
# Check common locations
for dir in \
    "$HOME/.local/share/godot/export_templates/4.6.2.stable" \
    "$HOME/.var/app/org.godotengine.Godot/data/godot/export_templates/4.6.2.stable" \
    "$HOME/Library/Application Support/Godot/export_templates/4.6.2.stable" \
    "${APPDATA:-}/Godot/export_templates/4.6.2.stable"; do
    if [ -d "$dir" ] && ls "$dir"/web_nothreads_release.zip &>/dev/null; then
        TEMPLATES_DIR="$dir"
        break
    fi
done

if [ -z "$TEMPLATES_DIR" ]; then
    echo ""
    echo "WARNING: Web export templates not found."
    echo "To install them:"
    echo "  1. Open Godot Editor"
    echo "  2. Editor → Manage Export Templates → Download and Install"
    echo "  Or download from: https://github.com/godotengine/godot/releases"
    echo ""
    echo "Looking for templates in:"
    echo "  ~/.local/share/godot/export_templates/4.6.2.stable/"
    echo "  ~/.var/app/org.godotengine.Godot/data/godot/export_templates/4.6.2.stable/"
    exit 1
fi

echo "Found templates: $TEMPLATES_DIR"

# --- Export game ---
echo ""
echo "Exporting game to HTML5..."
mkdir -p export/web
$GODOT --headless --path . --export-release "Web" export/web/index.html

if [ ! -f export/web/index.html ]; then
    echo "ERROR: Export failed. Check Godot output above."
    exit 1
fi

echo "Export complete: $(du -sh export/web/ | cut -f1) total"

# --- .env check ---
if [ ! -f .env ]; then
    echo ""
    echo "Creating .env from template..."
    cp .env.example .env
    echo "IMPORTANT: Edit .env and set RELAY_URL to your public address"
    echo "  e.g., RELAY_URL=wss://yourdomain.com:9090"
fi

# --- Docker ---
echo ""
echo "Starting Docker stack..."
if command -v docker-compose &>/dev/null; then
    docker-compose up -d --build
elif docker compose version &>/dev/null 2>&1; then
    docker compose up -d --build
else
    echo "ERROR: Docker Compose not found."
    echo "You can also run without Docker:"
    echo "  cd server && npm install && npm start"
    echo "  # Then serve export/web/ with any static file server"
    exit 1
fi

echo ""
echo "============================================"
echo "  Paintball Arena is running!"
echo "============================================"
echo ""
echo "  Game:  http://localhost:${WEB_PORT:-8080}"
echo "  Relay: ws://localhost:${RELAY_PORT:-9090}"
echo ""
echo "  Share the URL with friends to play!"
echo "  Stop with: docker-compose down"
echo ""
