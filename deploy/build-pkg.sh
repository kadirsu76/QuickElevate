#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Kullanim: $0 <version>"
  exit 1
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PAYLOAD_ROOT="$DIST_DIR/payload"
PKG_BUILD_DIR="$DIST_DIR/pkgbuild"
PRODUCT_BUILD_DIR="$DIST_DIR/productbuild"

APP_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/QuickElevateApp"
HELPER_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/QuickElevateHelper"

if [[ ! -x "$APP_BIN" || ! -x "$HELPER_BIN" ]]; then
  echo "Release build yok. once 'swift build -c release' calistirin."
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$PAYLOAD_ROOT/Applications/QuickElevate.app/Contents/MacOS"
mkdir -p "$PAYLOAD_ROOT/Applications/QuickElevate.app/Contents/Resources"
mkdir -p "$PAYLOAD_ROOT/usr/local/libexec"
mkdir -p "$PAYLOAD_ROOT/Library/LaunchDaemons"
mkdir -p "$PKG_BUILD_DIR"
mkdir -p "$PRODUCT_BUILD_DIR"

install -m 755 "$APP_BIN" "$PAYLOAD_ROOT/Applications/QuickElevate.app/Contents/MacOS/QuickElevateApp"
install -m 644 "$ROOT_DIR/deploy/QuickElevate.Info.plist" "$PAYLOAD_ROOT/Applications/QuickElevate.app/Contents/Info.plist"
install -m 755 "$HELPER_BIN" "$PAYLOAD_ROOT/usr/local/libexec/QuickElevateHelper"
install -m 644 "$ROOT_DIR/deploy/com.quickelevate.helper.plist" "$PAYLOAD_ROOT/Library/LaunchDaemons/com.quickelevate.helper.plist"

chmod 755 "$ROOT_DIR/deploy/pkg-scripts/preinstall"
chmod 755 "$ROOT_DIR/deploy/pkg-scripts/postinstall"

COMPONENT_PKG="$PKG_BUILD_DIR/QuickElevate-component.pkg"
pkgbuild \
  --root "$PAYLOAD_ROOT" \
  --identifier "com.quickelevate.pkg" \
  --version "$VERSION" \
  --install-location "/" \
  --scripts "$ROOT_DIR/deploy/pkg-scripts" \
  "$COMPONENT_PKG"

cp "$ROOT_DIR/deploy/pkg/Distribution.xml" "$PRODUCT_BUILD_DIR/Distribution.xml"
cp "$ROOT_DIR/deploy/pkg/welcome.html" "$PRODUCT_BUILD_DIR/welcome.html"
cp "$COMPONENT_PKG" "$PRODUCT_BUILD_DIR/QuickElevate-component.pkg"

FINAL_UNSIGNED="$DIST_DIR/QuickElevate-$VERSION-unsigned.pkg"
productbuild \
  --distribution "$PRODUCT_BUILD_DIR/Distribution.xml" \
  --resources "$PRODUCT_BUILD_DIR" \
  --package-path "$PRODUCT_BUILD_DIR" \
  "$FINAL_UNSIGNED"

echo "Unsigned package hazir: $FINAL_UNSIGNED"

if [[ -n "${DEVELOPER_ID_INSTALLER:-}" ]]; then
  FINAL_SIGNED="$DIST_DIR/QuickElevate-$VERSION.pkg"
  productsign --sign "$DEVELOPER_ID_INSTALLER" "$FINAL_UNSIGNED" "$FINAL_SIGNED"
  pkgutil --check-signature "$FINAL_SIGNED"
  echo "Signed package hazir: $FINAL_SIGNED"
else
  echo "DEVELOPER_ID_INSTALLER tanimli degil, imzalama atlandi."
fi
