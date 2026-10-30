#!/usr/bin/env bash
#
# build-and-deploy.sh — FORK tooling
#
# Release-archive Neon Vision Editor, then hash-verify-copy the .app into /Applications so the
# fork is always tested from /Applications/nve.app. Does NOT commit or push — that is a separate,
# explicit step.
#
# Usage: scripts/fork/build-and-deploy.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROJECT="Neon Vision Editor.xcodeproj"
SCHEME="Neon Vision Editor"
APP_NAME="Neon Vision Editor.app"          # bundle name inside the archive (upstream product name)
DEPLOY_APP_NAME="nve.app"                  # FORK: deploy under this shorter name in /Applications
EXECUTABLE_NAME="Neon Vision Editor"       # CFBundleExecutable — unchanged; bundle rename is outer-only
ARCHIVE_PATH="${ARCHIVE_PATH:-/tmp/NeonVisionEditor-fork.xcarchive}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
BUILD_LOG="${BUILD_LOG:-/tmp/nve_fork_archive.log}"
# Optional: build in a dedicated DerivedData dir. Set DERIVED_DATA_PATH to dodge a corrupted
# default DerivedData (e.g. the stale macro cache behind 'swift-plugin-server produced
# malformed response') without deleting anything.
DERIVED_DATA_ARGS=()
if [[ -n "${DERIVED_DATA_PATH:-}" ]]; then
  DERIVED_DATA_ARGS=(-derivedDataPath "$DERIVED_DATA_PATH")
fi

echo "==> [1/4] Release archive (signing disabled)…"
# Signing off matches release.sh; a locally-archived app is unsigned but runnable locally.
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  ${DERIVED_DATA_ARGS[@]+"${DERIVED_DATA_ARGS[@]}"} \
  MACOSX_DEPLOYMENT_TARGET=15.5 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  archive > "$BUILD_LOG" 2>&1

if ! grep -q "ARCHIVE SUCCEEDED" "$BUILD_LOG"; then
  echo "!! ARCHIVE FAILED — see $BUILD_LOG" >&2
  grep -E "error:" "$BUILD_LOG" | grep -viE "provisioning|profiles" | sort -u | head -20 >&2
  exit 1
fi

SRC_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$SRC_APP" ]]; then
  echo "!! Archived app not found at: $SRC_APP" >&2
  exit 1
fi
echo "    archived: $SRC_APP"

echo "==> [2/4] Hashing archived binary…"
SRC_BIN="$SRC_APP/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -f "$SRC_BIN" ]]; then
  echo "!! Executable not found in archived app: $SRC_BIN" >&2
  exit 1
fi
SRC_HASH="$(shasum -a 256 "$SRC_BIN" | awk '{print $1}')"
echo "    source sha256: $SRC_HASH"

echo "==> [3/4] Clean copy to ${INSTALL_DIR}/${DEPLOY_APP_NAME} …"
DEST_APP="$INSTALL_DIR/$DEPLOY_APP_NAME"
# Remove any stale copy first (both the fork name AND the old upstream-named bundle) so we never
# leave two copies behind and cp can't silently merge into an old bundle.
rm -rf "$DEST_APP" "$INSTALL_DIR/$APP_NAME"
# Outer-bundle rename only: copy the archived .app to nve.app. CFBundleExecutable is unchanged,
# so macOS still launches Contents/MacOS/$EXECUTABLE_NAME correctly — no Info.plist edit needed.
cp -R "$SRC_APP" "$DEST_APP"
# Defensively strip the quarantine flag from the freshly-copied bundle (locally built, but be safe).
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "==> [4/4] Verifying deployed binary hash…"
DEST_BIN="$DEST_APP/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -f "$DEST_BIN" ]]; then
  echo "!! Deploy FAILED — executable missing at $DEST_BIN (permission or copy failure)" >&2
  exit 1
fi
DEST_HASH="$(shasum -a 256 "$DEST_BIN" | awk '{print $1}')"
echo "    deployed sha256: $DEST_HASH"

if [[ "$SRC_HASH" != "$DEST_HASH" ]]; then
  echo "!! HASH MISMATCH — /Applications copy does NOT match the fresh archive." >&2
  echo "   Likely a permission or silent-copy failure. NOT deployed cleanly." >&2
  exit 1
fi

echo ""
echo "✅ Deployed clean to $DEST_APP"
echo "   sha256 verified: $DEST_HASH"
echo "   Launch from /Applications/nve.app to test the fork build."
