#!/usr/bin/env sh
# Reset to a clean slate for testing first-run setup.

echo "[reset] stopping daemon..."
pkill -x harp 2>/dev/null

echo "[reset] unloading launchd agent..."
launchctl unload ~/Library/LaunchAgents/com.mr_robot.harp.plist 2>/dev/null

echo "[reset] removing installed files..."
rm -f /usr/local/bin/harp
rm -f ~/Library/LaunchAgents/com.mr_robot.harp.plist

echo "[reset] re-enabling stage manager..."
defaults write com.apple.WindowManager GloballyEnabled -bool true

echo "[reset] removing harp config..."
rm -rf ~/.config/harp

echo "[reset] clearing logs..."
rm -f /tmp/harp.log

echo "[reset] done — run ./harp from the project dir to simulate first-run"
