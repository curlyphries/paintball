#!/bin/bash
# Paintball Arena Launcher

cd /home/curlyphries/CascadeProjects/personal-fun/my-game

echo "=========================================="
echo "  Paintball Arena - 3D 1v3 Bots"
echo "=========================================="
echo ""
echo "1) Run Game (no editor)"
echo "2) Open in Godot Editor"
echo "3) Quit"
echo ""
read -p "Select option (1-3): " choice

case $choice in
    1)
        echo "Starting Paintball Arena..."
        flatpak run org.godotengine.Godot --path .
        ;;
    2)
        echo "Opening Godot Editor..."
        flatpak run org.godotengine.Godot --editor project.godot &
        ;;
    3)
        echo "Goodbye!"
        exit 0
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac
