#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_DIR}/dist"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clipboardx-release.XXXXXX")"
trap 'rm -rf -- "$BUILD_DIR"' EXIT

rm -rf -- "$DIST_DIR"
mkdir -p "$DIST_DIR"

xcodebuild build \
  -project "$PROJECT_DIR/ClipboardX.xcodeproj" \
  -scheme ClipboardX \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/ClipboardX.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/ClipboardX"

test -d "$APP_PATH"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" = 'com.wkj01n.ClipboardX'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" = '2.1.2'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")" = '212'

ARCHITECTURES="$(lipo -archs "$EXECUTABLE_PATH")"
[[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]]
codesign --verify --deep --strict "$APP_PATH"

PAYLOAD_ROOT="$BUILD_DIR/PayloadRoot"
mkdir -p "$PAYLOAD_ROOT/Applications"
ditto --norsrc --noextattr "$APP_PATH" "$PAYLOAD_ROOT/Applications/ClipboardX.app"
xattr -cr "$PAYLOAD_ROOT/Applications/ClipboardX.app"
find "$PAYLOAD_ROOT/Applications/ClipboardX.app" -name '._*' -delete

COMPONENT_PLIST="$BUILD_DIR/components.plist"
pkgbuild --analyze --root "$PAYLOAD_ROOT" "$COMPONENT_PLIST"
COMPONENT_INDEX=0
while /usr/libexec/PlistBuddy -c "Print :$COMPONENT_INDEX" "$COMPONENT_PLIST" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Set :$COMPONENT_INDEX:BundleIsRelocatable false" "$COMPONENT_PLIST"
  /usr/libexec/PlistBuddy -c "Set :$COMPONENT_INDEX:BundleHasStrictIdentifier true" "$COMPONENT_PLIST"
  /usr/libexec/PlistBuddy -c "Set :$COMPONENT_INDEX:BundleIsVersionChecked true" "$COMPONENT_PLIST"
  /usr/libexec/PlistBuddy -c "Set :$COMPONENT_INDEX:BundleOverwriteAction upgrade" "$COMPONENT_PLIST"
  COMPONENT_INDEX=$((COMPONENT_INDEX + 1))
done

pkgbuild \
  --root "$PAYLOAD_ROOT" \
  --install-location / \
  --component-plist "$COMPONENT_PLIST" \
  --filter '(^|/)\.svn(/|$)' \
  --filter '(^|/)CVS(/|$)' \
  --filter '(^|/)\.DS_Store$' \
  --filter '(^|/)\._[^/]+$' \
  --identifier com.wkj01n.ClipboardX.installer \
  --version 2.1.2 \
  "$DIST_DIR/ClipboardX.pkg"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/ClipboardX.zip"

pkgutil --payload-files "$DIST_DIR/ClipboardX.pkg" | grep -q '^./Applications/ClipboardX.app/'
shasum -a 256 "$DIST_DIR/ClipboardX.pkg" "$DIST_DIR/ClipboardX.zip" > "$DIST_DIR/SHA256SUMS.txt"

echo "Release artifacts written to $DIST_DIR"
