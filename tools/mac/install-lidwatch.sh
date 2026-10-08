#!/bin/sh
# install-lidwatch.sh [install|uninstall|status]  -  lidwatch.sh as a per-user login item (LaunchAgent).
# No sudo. Installs a copy of lidwatch.sh under ~/Library/Application Support/lidwatch and a LaunchAgent that keeps
# it running in the user's GUI session. Log: ~/Library/Logs/lidwatch.log (one line per lid event).
set -e
LABEL=local.lidwatch
HERE=$(cd "$(dirname "$0")" && pwd)
DIR="$HOME/Library/Application Support/lidwatch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

case "${1:-install}" in
  install)
    mkdir -p "$DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    cp "$HERE/lidwatch.sh" "$DIR/lidwatch.sh"; chmod 755 "$DIR/lidwatch.sh"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>$DIR/lidwatch.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Background</string>
	<key>StandardOutPath</key>
	<string>$HOME/Library/Logs/lidwatch.log</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/lidwatch.log</string>
</dict>
</plist>
PLIST
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "installed: $PLIST"
    ;;
  uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST" "$DIR/lidwatch.sh"; rmdir "$DIR" 2>/dev/null || true
    echo "removed"
    ;;
  status)
    launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E "state =|pid =|last exit" || echo "not loaded"
    ;;
  *) echo "usage: $0 [install|uninstall|status]"; exit 2;;
esac
