#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
make build
if [ -n "${HINGE_BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $HINGE_BUILD_NUMBER" build/Hinge.app/Contents/Info.plist
  identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
  codesign --force --sign "${identity:--}" build/Hinge.app
fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/hinge-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p dist
ditto build/Hinge.app "$stage/Hinge.app"
ln -s /Applications "$stage/Applications"
hdiutil create -ov -volname Hinge -srcfolder "$stage" -format UDZO dist/Hinge.dmg
codesign --verify --deep --strict build/Hinge.app
(cd dist && shasum -a 256 Hinge.dmg > Hinge.dmg.sha256)
