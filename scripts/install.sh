#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
binary_source="$project_dir/.build/release/auto-pause-cemu"
install_dir="$HOME/Library/Application Support/AutoPauseCemu"
binary_target="$install_dir/auto-pause-cemu"
log_dir="$HOME/Library/Logs/AutoPauseCemu"
agent="$HOME/Library/LaunchAgents/com.local.auto-pause-cemu.plist"

if [[ ! -x "$binary_source" ]]; then
  print -u2 "未找到 release 程序，请先运行 make build"
  exit 1
fi

mkdir -p "$install_dir" "$log_dir" "${agent:h}"
cp "$binary_source" "$binary_target"
chmod 755 "$binary_target"

escaped_binary=${binary_target//&/&amp;}
escaped_binary=${escaped_binary//</&lt;}
escaped_binary=${escaped_binary//>/&gt;}

plist=$'<?xml version="1.0" encoding="UTF-8"?>\n'
plist+=$'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
plist+=$'<plist version="1.0">\n<dict>\n'
plist+=$'  <key>Label</key>\n  <string>com.local.auto-pause-cemu</string>\n'
plist+=$'  <key>ProgramArguments</key>\n  <array>\n'
plist+="    <string>$escaped_binary</string>\n"
plist+=$'  </array>\n'
plist+=$'  <key>RunAtLoad</key>\n  <true/>\n'
plist+=$'  <key>KeepAlive</key>\n  <true/>\n'
plist+=$'  <key>ProcessType</key>\n  <string>Background</string>\n'
plist+="  <key>StandardOutPath</key>\n  <string>$log_dir/stdout.log</string>\n"
plist+="  <key>StandardErrorPath</key>\n  <string>$log_dir/stderr.log</string>\n"
plist+=$'</dict>\n</plist>\n'

print -rn -- "$plist" > "$agent"
plutil -lint "$agent"

launchctl bootout "gui/$UID/com.local.auto-pause-cemu" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$agent"
print "已安装并启动：$agent"
