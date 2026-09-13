#!/bin/zsh
set -euo pipefail

APP_BIN="/Applications/QuickElevate.app/Contents/MacOS/QuickElevateApp"
HELPER_LABEL="com.quickelevate.helper"
SOCKET_DIR="/var/run/quickelevate"

if [[ ! -x "$APP_BIN" ]]; then
  echo "QuickElevate app binary missing"
  exit 1
fi

if ! /bin/launchctl print "system/$HELPER_LABEL" >/dev/null 2>&1; then
  echo "Helper launchd service missing"
  exit 1
fi

if [[ ! -d "$SOCKET_DIR" ]]; then
  echo "Socket directory missing"
  exit 1
fi

echo "QuickElevate OK"
exit 0
