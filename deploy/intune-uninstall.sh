#!/bin/zsh
set -euo pipefail

PLIST="/Library/LaunchDaemons/com.quickelevate.helper.plist"

/bin/launchctl bootout system "$PLIST" >/dev/null 2>&1 || true

/bin/rm -f "$PLIST"
/bin/rm -f /usr/local/libexec/QuickElevateHelper
/bin/rm -rf /usr/local/libexec/quickelevate
/bin/rm -rf /Applications/QuickElevate.app
/bin/rm -rf /var/run/quickelevate
/bin/rm -f /var/run/quickelevate-state.json

echo "QuickElevate uninstall tamamlandi"
