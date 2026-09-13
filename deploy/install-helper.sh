#!/bin/zsh
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
CONFIG_SRC="$ROOT_DIR/Infrastructure/azure/QuickElevate-Configuration.generated.json"
HELPER_SRC="$ROOT_DIR/.build/arm64-apple-macosx/release/QuickElevateHelper"
APP_SRC="$ROOT_DIR/.build/arm64-apple-macosx/release/QuickElevateApp"
MSAL_FRAMEWORK_SRC="$ROOT_DIR/.build/arm64-apple-macosx/release/MSAL.framework"
PIN_SCRIPT_SRC="$ROOT_DIR/deploy/pin-to-dock.sh"

if [[ ! -x "$HELPER_SRC" ]]; then
  echo "QuickElevateHelper bulunamadi: $HELPER_SRC"
  exit 1
fi

if [[ ! -x "$APP_SRC" ]]; then
  echo "QuickElevateApp bulunamadi: $APP_SRC"
  exit 1
fi

if [[ ! -d "$MSAL_FRAMEWORK_SRC" ]]; then
  echo "MSAL.framework bulunamadi: $MSAL_FRAMEWORK_SRC"
  exit 1
fi

if [[ ! -f "$CONFIG_SRC" ]]; then
  echo "Generated Azure config bulunamadi: $CONFIG_SRC"
  exit 1
fi

sudo install -d -m 755 /usr/local/libexec
sudo install -m 755 "$HELPER_SRC" /usr/local/libexec/QuickElevateHelper

# App bundle once kullanici olarak staging dizininde hazirlanir ve imzalanir.
# Sebep: Apple Development sertifikasi kullanicinin login Keychain'indedir;
# sudo ile root olarak codesign calisirsa kimlik bulunamaz.
STAGE_DIR="$(mktemp -d -t quickelevate-app)"
trap 'rm -rf "$STAGE_DIR"' EXIT
mkdir -p "$STAGE_DIR/QuickElevate.app/Contents/MacOS" "$STAGE_DIR/QuickElevate.app/Contents/Resources" "$STAGE_DIR/QuickElevate.app/Contents/Frameworks"
install -m 755 "$APP_SRC" "$STAGE_DIR/QuickElevate.app/Contents/MacOS/QuickElevateApp"
install -m 644 "$ROOT_DIR/deploy/QuickElevate.Info.plist" "$STAGE_DIR/QuickElevate.app/Contents/Info.plist"
rm -rf "$STAGE_DIR/QuickElevate.app/Contents/Frameworks/MSAL.framework"
cp -R "$MSAL_FRAMEWORK_SRC" "$STAGE_DIR/QuickElevate.app/Contents/Frameworks/MSAL.framework"
if ! otool -l "$STAGE_DIR/QuickElevate.app/Contents/MacOS/QuickElevateApp" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$STAGE_DIR/QuickElevate.app/Contents/MacOS/QuickElevateApp"
fi
APPLE_TEAM_ID="${2:-${APPLE_TEAM_ID:-}}"
if [[ -n "$APPLE_TEAM_ID" ]]; then
  echo "Apple Development signing aktif (Team ID: $APPLE_TEAM_ID)"
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep "($APPLE_TEAM_ID)" | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) ([A-F0-9]+) "(.*)".*/\2/')"
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "HATA: Team ID $APPLE_TEAM_ID icin codesigning kimligi bulunamadi."
    echo "Xcode > Settings > Accounts altinda Apple ID ile giris yapildigini dogrulayin."
    exit 1
  fi
  echo "Imza kimligi: $SIGN_IDENTITY"
  ENTITLEMENTS_TMP="$(mktemp -t quickelevate-entitlements).plist"
  # Entitlement öneki, sertifika adındaki parantez içi değer DEĞİL, sertifikanın
  # OU alanındaki gerçek Team ID olmalıdır (codesign TeamIdentifier buradan gelir).
  CERT_TEAM_ID="$(security find-certificate -c "$SIGN_IDENTITY" -p 2>/dev/null | openssl x509 -noout -subject -nameopt sep_multiline 2>/dev/null | grep -m1 'OU=' | sed 's/^ *OU=//')"
  if [[ -z "$CERT_TEAM_ID" ]]; then
    echo "UYARI: sertifikadan Team ID okunamadi, verilen deger kullaniliyor."
    CERT_TEAM_ID="$APPLE_TEAM_ID"
  fi
  echo "Entitlement Team ID: $CERT_TEAM_ID"
  sed "s/@APPLE_TEAM_ID@/$CERT_TEAM_ID/g" "$ROOT_DIR/deploy/QuickElevate.entitlements.template" > "$ENTITLEMENTS_TMP"
  if ! plutil -lint "$ENTITLEMENTS_TMP" >/dev/null; then
    echo "HATA: uretilen entitlements dosyasi gecersiz:"
    plutil -lint "$ENTITLEMENTS_TMP" || true
    rm -f "$ENTITLEMENTS_TMP"
    exit 1
  fi
  echo "Not: Keychain erisim sorusu cikarsa 'Always Allow' secin."
  codesign --force --sign "$SIGN_IDENTITY" "$STAGE_DIR/QuickElevate.app/Contents/Frameworks/MSAL.framework"
  codesign --force --entitlements "$ENTITLEMENTS_TMP" --sign "$SIGN_IDENTITY" "$STAGE_DIR/QuickElevate.app/Contents/MacOS/QuickElevateApp"
  codesign --force --entitlements "$ENTITLEMENTS_TMP" --sign "$SIGN_IDENTITY" "$STAGE_DIR/QuickElevate.app"
  rm -f "$ENTITLEMENTS_TMP"
  echo "Keychain entitlement dogrulamasi:"
  codesign -d --entitlements :- "$STAGE_DIR/QuickElevate.app" 2>/dev/null | grep -A3 keychain-access-groups || echo "UYARI: entitlement imzaya gomulmemis gorunuyor."
else
  echo "UYARI: APPLE_TEAM_ID verilmedi, ad-hoc imza kullaniliyor. MSAL/PSSO Keychain erisimi (-34018) calismaz."
  codesign --force --deep --sign - "$STAGE_DIR/QuickElevate.app"
fi
sudo rm -rf /Applications/QuickElevate.app
sudo cp -R "$STAGE_DIR/QuickElevate.app" /Applications/QuickElevate.app
sudo chown -R root:wheel /Applications/QuickElevate.app

sudo install -d -m 755 /usr/local/libexec/quickelevate
sudo install -m 755 "$PIN_SCRIPT_SRC" /usr/local/libexec/quickelevate/pin-to-dock.sh

sudo install -d -m 700 "/Library/Application Support/QuickElevate"
sudo /usr/bin/python3 - "$CONFIG_SRC" <<'PY'
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text())
helper = {
    "grantIssuer": source["GrantIssuer"],
    "grantAudience": source["GrantAudience"],
    "signingKeyModulus": source["SigningKeyModulus"],
    "signingKeyExponent": source["SigningKeyExponent"],
}
Path("/Library/Application Support/QuickElevate/grant-verifier.json").write_text(json.dumps(helper, separators=(",", ":")))
PY
sudo chown root:wheel "/Library/Application Support/QuickElevate/grant-verifier.json"
sudo chmod 600 "/Library/Application Support/QuickElevate/grant-verifier.json"

CONSOLE_USER="$(stat -f%Su /dev/console)"
if [[ "$CONSOLE_USER" != "root" && -n "$CONSOLE_USER" ]]; then
  CONSOLE_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')"
  sudo install -d -m 755 "$CONSOLE_HOME/Library/Preferences"
  sudo /usr/bin/defaults write "$CONSOLE_HOME/Library/Preferences/com.quickelevate.app" TenantId -string "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["TenantId"])' "$CONFIG_SRC")"
  sudo /usr/bin/defaults write "$CONSOLE_HOME/Library/Preferences/com.quickelevate.app" NativeClientId -string "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["NativeClientId"])' "$CONFIG_SRC")"
  sudo /usr/bin/defaults write "$CONSOLE_HOME/Library/Preferences/com.quickelevate.app" ApiAudience -string "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ApiAudience"])' "$CONFIG_SRC")"
  sudo /usr/bin/defaults write "$CONSOLE_HOME/Library/Preferences/com.quickelevate.app" ApiBaseUrl -string "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ApiBaseUrl"])' "$CONFIG_SRC")"
  sudo chown "$CONSOLE_USER":staff "$CONSOLE_HOME/Library/Preferences/com.quickelevate.app.plist"
fi

sudo install -d -m 755 /Library/LaunchDaemons
sudo install -m 644 "$ROOT_DIR/deploy/com.quickelevate.helper.plist" /Library/LaunchDaemons/com.quickelevate.helper.plist

sudo launchctl bootout system /Library/LaunchDaemons/com.quickelevate.helper.plist >/dev/null 2>&1 || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.quickelevate.helper.plist
sudo launchctl enable system/com.quickelevate.helper
sudo launchctl kickstart -k system/com.quickelevate.helper

if [[ "$CONSOLE_USER" != "root" && -n "$CONSOLE_USER" ]]; then
  CONSOLE_UID="$(id -u "$CONSOLE_USER")"
  sudo launchctl asuser "$CONSOLE_UID" /usr/local/libexec/quickelevate/pin-to-dock.sh >/dev/null 2>&1 || true
fi

echo "Kurulum tamamlandi. Uygulamayi /Applications/QuickElevate.app/Contents/MacOS/QuickElevateApp ile calistirabilirsiniz."
echo "Apple Development imzali kurulum icin: APPLE_TEAM_ID=<TEAM_ID> ./deploy/install-helper.sh"
