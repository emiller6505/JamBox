#!/usr/bin/env bash
#
# Build a universal (arm64 + x86_64) Release build of JamBox, package it
# as a DMG, and optionally publish a GitHub Release.
#
# Usage:
#   scripts/release.sh                # build DMG only
#   scripts/release.sh --publish      # also create a GitHub Release and upload
#   scripts/release.sh 1.2.0          # override version (default reads project.yml)
#   scripts/release.sh 1.2.0 --publish
#
# Output:
#   build/JamBox-<version>.dmg
#
# Requirements:
#   xcodegen, xcodebuild, hdiutil (built in), gh (only if --publish)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="JamBox"
SCHEME="JamBox"
PROJECT="JamBox.xcodeproj"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/derived"
STAGING="$BUILD_DIR/dmg-staging"

# --- parse args ---------------------------------------------------------------
VERSION=""
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) VERSION="$arg" ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | awk -F'"' '{print $2}')
  if [[ -z "$VERSION" ]]; then
    echo "error: could not read MARKETING_VERSION from project.yml" >&2
    exit 1
  fi
fi

DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"
echo "==> Building $APP_NAME $VERSION"

# --- regenerate xcode project so project.yml changes are picked up ------------
echo "==> xcodegen generate"
xcodegen generate >/dev/null

# --- clean previous build artifacts -------------------------------------------
rm -rf "$DERIVED_DATA" "$STAGING" "$DMG_PATH"
mkdir -p "$BUILD_DIR"

# --- build universal release binary -------------------------------------------
# ARCHS + ONLY_ACTIVE_ARCH=NO -> universal (arm64 + x86_64).
# CODE_SIGN_IDENTITY="-" -> ad-hoc sign so the binary actually launches on
# Apple Silicon. Without ANY signature, AS macOS kills the process on launch.
echo "==> xcodebuild (Release, universal, ad-hoc signed)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build | tail -20

APP_PATH="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: build did not produce $APP_PATH" >&2
  exit 1
fi

# --- verify the binary is universal -------------------------------------------
BIN="$APP_PATH/Contents/MacOS/$APP_NAME"
ARCHS_FOUND=$(lipo -archs "$BIN")
echo "==> Binary archs: $ARCHS_FOUND"
if [[ "$ARCHS_FOUND" != *"arm64"* || "$ARCHS_FOUND" != *"x86_64"* ]]; then
  echo "error: binary is not universal (got: $ARCHS_FOUND)" >&2
  exit 1
fi

# --- stage DMG contents -------------------------------------------------------
# Layout:
#   <volume>/READ ME FIRST.txt    (first-launch instructions)
#   <volume>/JamBox.app
#   <volume>/Applications -> /Applications  (drag target)
echo "==> Staging DMG contents"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "scripts/dmg_readme.txt" "$STAGING/READ ME FIRST.txt"

# --- build the DMG ------------------------------------------------------------
echo "==> Creating $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
echo "==> DMG ready: $DMG_PATH ($DMG_SIZE)"

# --- optional: publish to GitHub Releases -------------------------------------
if [[ "$PUBLISH" -eq 1 ]]; then
  if ! command -v gh >/dev/null; then
    echo "error: gh CLI not found, skipping publish" >&2
    exit 1
  fi
  TAG="v$VERSION"
  echo "==> Publishing GitHub Release $TAG"
  gh release create "$TAG" "$DMG_PATH" \
    --title "$APP_NAME $VERSION" \
    --notes "Universal macOS build (Apple Silicon + Intel).

**Install:** Open the DMG, drag JamBox.app to the Applications shortcut.

**First launch:** macOS will block the app because it is not signed by a paid Apple Developer account. The DMG includes a 'READ ME FIRST.txt' with full instructions. The fastest fix is to open Terminal and run:

    xattr -dr com.apple.quarantine /Applications/JamBox.app

Then double-click JamBox normally. You only need to do this once."
  echo "==> Done."
else
  echo
  echo "To publish:  scripts/release.sh $VERSION --publish"
  echo "Or manually: gh release create v$VERSION $DMG_PATH"
fi
