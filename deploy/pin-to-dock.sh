#!/bin/zsh
set -euo pipefail

APP_PATH="/Applications/QuickElevate.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "QuickElevate.app bulunamadi: $APP_PATH"
  exit 1
fi

/usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
    tell dock preferences
        set persistentApps to persistent applications
        set appAlreadyPinned to false
        repeat with oneApp in persistentApps
            try
                if POSIX path of (oneApp's properties's path) is "/Applications/QuickElevate.app" then
                    set appAlreadyPinned to true
                    exit repeat
                end if
            end try
        end repeat

        if appAlreadyPinned is false then
            make new persistent application with properties {path:"/Applications/QuickElevate.app"}
        end if
    end tell
end tell
APPLESCRIPT

/usr/bin/killall Dock >/dev/null 2>&1 || true
echo "QuickElevate Dock'a eklendi."
