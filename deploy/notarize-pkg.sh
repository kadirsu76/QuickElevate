#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Kullanim: $0 <signed-pkg-path>"
  exit 1
fi

PKG_PATH="$1"

if [[ ! -f "$PKG_PATH" ]]; then
  echo "Dosya bulunamadi: $PKG_PATH"
  exit 1
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "NOTARY_PROFILE ortam degiskeni gerekli."
  echo "Ornek: xcrun notarytool store-credentials quickelevate-notary --apple-id ... --team-id ... --password ..."
  exit 1
fi

xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PKG_PATH"

spctl -a -vv -t install "$PKG_PATH"
echo "Notarization tamamlandi: $PKG_PATH"
