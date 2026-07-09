#!/bin/zsh
set -euo pipefail

agent="$HOME/Library/LaunchAgents/com.local.auto-pause-cemu.plist"
install_dir="$HOME/Library/Application Support/AutoPauseCemu"

launchctl bootout "gui/$UID/com.local.auto-pause-cemu" 2>/dev/null || true
rm -f "$agent"
rm -rf "$install_dir"
print "已卸载 auto-pause-cemu"
