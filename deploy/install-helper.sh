#!/bin/zsh
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
HELPER_SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/QuickElevateHelper"
APP_SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/QuickElevateApp"
PIN_SCRIPT_SRC="$ROOT_DIR/deploy/pin-to-dock.sh"

if [[ ! -x "$HELPER_SRC" ]]; then
  echo "QuickElevateHelper bulunamadi: $HELPER_SRC"
  exit 1
fi

if [[ ! -x "$APP_SRC" ]]; then
  echo "QuickElevateApp bulunamadi: $APP_SRC"
  exit 1
fi

sudo install -d -m 755 /usr/local/libexec
sudo install -m 755 "$HELPER_SRC" /usr/local/libexec/QuickElevateHelper

sudo install -d -m 755 /Applications/QuickElevate.app/Contents/MacOS
sudo install -d -m 755 /Applications/QuickElevate.app/Contents/Resources
sudo install -m 755 "$APP_SRC" /Applications/QuickElevate.app/Contents/MacOS/QuickElevateApp
sudo install -m 644 "$ROOT_DIR/deploy/QuickElevate.Info.plist" /Applications/QuickElevate.app/Contents/Info.plist
sudo chown -R root:wheel /Applications/QuickElevate.app

sudo install -d -m 755 /usr/local/libexec/quickelevate
sudo install -m 755 "$PIN_SCRIPT_SRC" /usr/local/libexec/quickelevate/pin-to-dock.sh

sudo install -d -m 755 /Library/LaunchDaemons
sudo install -m 644 "$ROOT_DIR/deploy/com.quickelevate.helper.plist" /Library/LaunchDaemons/com.quickelevate.helper.plist

sudo launchctl bootout system /Library/LaunchDaemons/com.quickelevate.helper.plist >/dev/null 2>&1 || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.quickelevate.helper.plist
sudo launchctl enable system/com.quickelevate.helper
sudo launchctl kickstart -k system/com.quickelevate.helper

CONSOLE_USER="$(stat -f%Su /dev/console)"
if [[ "$CONSOLE_USER" != "root" && -n "$CONSOLE_USER" ]]; then
  CONSOLE_UID="$(id -u "$CONSOLE_USER")"
  sudo launchctl asuser "$CONSOLE_UID" /usr/local/libexec/quickelevate/pin-to-dock.sh >/dev/null 2>&1 || true
fi

echo "Kurulum tamamlandi. Uygulamayi /Applications/QuickElevate.app/Contents/MacOS/QuickElevateApp ile calistirabilirsiniz."
