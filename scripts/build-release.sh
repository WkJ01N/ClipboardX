#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PROJECT_DIR}/dist"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clipboardx-release.XXXXXX")"
trap 'rm -rf -- "$BUILD_DIR"' EXIT

EXPECTED_SIGNING_IDENTITY='Apple Development: walkersj01n@outlook.com (DQHW8H93B2)'
EXPECTED_TEAM_IDENTIFIER='Z2PR2J9A3W'
if [[ "${ALLOW_ADHOC_RELEASE:-0}" == '1' ]]; then
  SIGNING_IDENTITY='-'
  XCODE_SIGNING_IDENTITY='-'
  STABLE_SIGNING=0
else
  SIGNING_IDENTITY="${RELEASE_SIGNING_IDENTITY:-$EXPECTED_SIGNING_IDENTITY}"
  XCODE_SIGNING_IDENTITY='Apple Development'
  STABLE_SIGNING=1
  security find-identity -v -p codesigning | grep -Fq "\"$SIGNING_IDENTITY\""
fi

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
  CODE_SIGN_IDENTITY="$XCODE_SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$EXPECTED_TEAM_IDENTIFIER"

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/ClipboardX.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/ClipboardX"

test -d "$APP_PATH"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" = 'com.wkj01n.ClipboardX'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" = '2.1.2'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")" = '213'

ARCHITECTURES="$(lipo -archs "$EXECUTABLE_PATH")"
[[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]]
if strings "$EXECUTABLE_PATH" | grep -Fq 'ClipboardX UI Tests'; then
  echo 'Release binary unexpectedly contains the UI-testing window scene.' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
if [[ "$STABLE_SIGNING" == '1' ]]; then
  SIGNING_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
  DESIGNATED_REQUIREMENT="$(codesign -dr - "$APP_PATH" 2>&1)"
  [[ "$SIGNING_DETAILS" == *"TeamIdentifier=$EXPECTED_TEAM_IDENTIFIER"* ]]
  [[ "$SIGNING_DETAILS" == *"Authority=$SIGNING_IDENTITY"* ]]
  [[ "$DESIGNATED_REQUIREMENT" == *'anchor apple generic'* ]]
  [[ "$DESIGNATED_REQUIREMENT" != *'cdhash'* ]]
fi

PAYLOAD_ROOT="$BUILD_DIR/PayloadRoot"
mkdir -p "$PAYLOAD_ROOT/Applications"
ditto --norsrc --noextattr "$APP_PATH" "$PAYLOAD_ROOT/Applications/ClipboardX.app"
xattr -cr "$PAYLOAD_ROOT/Applications/ClipboardX.app"
find "$PAYLOAD_ROOT/Applications/ClipboardX.app" -name '._*' -delete
codesign --verify --deep --strict "$PAYLOAD_ROOT/Applications/ClipboardX.app"

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

ditto -c -k --norsrc --noextattr --keepParent "$PAYLOAD_ROOT/Applications/ClipboardX.app" "$DIST_DIR/ClipboardX.zip"

pkgutil --payload-files "$DIST_DIR/ClipboardX.pkg" | grep -q '^./Applications/ClipboardX.app/'

ARCHIVE_CHECK_ROOT="$BUILD_DIR/ArchiveCheck"
mkdir -p "$ARCHIVE_CHECK_ROOT/zip"
ditto -x -k "$DIST_DIR/ClipboardX.zip" "$ARCHIVE_CHECK_ROOT/zip"
codesign --verify --deep --strict "$ARCHIVE_CHECK_ROOT/zip/ClipboardX.app"

pkgutil --expand-full "$DIST_DIR/ClipboardX.pkg" "$ARCHIVE_CHECK_ROOT/pkg"
PKG_APP_PATH="$ARCHIVE_CHECK_ROOT/pkg/Payload/Applications/ClipboardX.app"
codesign --verify --deep --strict "$PKG_APP_PATH"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PKG_APP_PATH/Contents/Info.plist")" = 'com.wkj01n.ClipboardX'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PKG_APP_PATH/Contents/Info.plist")" = '2.1.2'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PKG_APP_PATH/Contents/Info.plist")" = '213'

pushd "$DIST_DIR" >/dev/null
shasum -a 256 ClipboardX.pkg ClipboardX.zip > SHA256SUMS.txt
popd >/dev/null

echo "Release artifacts written to $DIST_DIR"
