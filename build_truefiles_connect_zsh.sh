#!/usr/bin/env zsh
set -euo pipefail

# =======================
# Truefiles Connect Builder (zsh)
# - Converts PNG -> ICNS
# - Compiles AppleScript -> .app
# - Bundles icon
# - Ad-hoc codesigns by default
# - Creates a distributable .zip
# =======================

# ---- CONFIG (edit as needed) ----
APP_NAME="Truefiles Connect"
SRC="Truefiles Connect.applescript"     # AppleScript source file
PNG_ICON="icon.png"                     # Source PNG icon (512x512+ recommended, transparent)
BUNDLE_ID="com.truelogik.truefilesconnect"
SIGN_ID=""                              # e.g., "Developer ID Application: Your Org (TEAMID)" or leave empty to skip
OUT_DIR="./dist"

# Derived paths
APP_PATH="$OUT_DIR/$APP_NAME.app"
ICONSET_DIR="./build/icon/TL.iconset"
ICNS_PATH="./build/icon/TL.icns"
ZIP_PATH="$OUT_DIR/Truefiles_Connect.zip"

# ---- Functions ----
die() { echo "Error: $*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing tool '$1'. Install or ensure it is on PATH."
}

png_to_icns() {
  local png="$1"
  local iconset="$2"
  local icns="$3"

  mkdir -p "$iconset"

  # Sizes required for macOS iconset
  local sizes=(16 32 128 256 512)
  for s in "${sizes[@]}"; do
    sips -z "$s" "$s" "$png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
  done

  iconutil -c icns "$iconset" -o "$icns"
}

bundle_icon() {
  local app="$1"; local icns="$2"
  cp "$icns" "$app/Contents/Resources/applet.icns"
  plutil -replace CFBundleIconFile -string "applet" "$app/Contents/Info.plist"
}

# Always ad-hoc sign; upgrade to Developer ID if SIGN_ID is set
sign_app() {
  local app="$1"; local id="$2"
  echo "🔏 Applying ad-hoc signature…"
  codesign -s - --force "$app"
  if [[ -n "$id" ]]; then
    echo "🔏 Re-signing with Developer ID: $id…"
    codesign --force --options runtime --timestamp -s "$id" "$app"
  fi
}

zip_app() {
  local app="$1"; local zip="$2"
  rm -f "$zip"
  # Use ditto to preserve macOS metadata and keep parent folder name
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
}

# ---- Checks ----
need osacompile
need sips
need iconutil
need plutil
need ditto
[[ -f "$SRC" ]] || die "Source AppleScript not found: $SRC"
[[ -f "$PNG_ICON" ]] || die "PNG icon not found: $PNG_ICON"

# ---- Build ----
rm -rf "$OUT_DIR" ./build
mkdir -p "$OUT_DIR" ./build/icon

echo "🎨 Converting PNG → ICNS…"
png_to_icns "$PNG_ICON" "$ICONSET_DIR" "$ICNS_PATH"
echo "   Created: $ICNS_PATH"

echo "🔨 Compiling AppleScript → app…"
osacompile -o "$APP_PATH" "$SRC"

echo "🎯 Bundling icon into app…"
bundle_icon "$APP_PATH" "$ICNS_PATH"

echo "🆔 Setting bundle identifier…"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_PATH/Contents/Info.plist" || true

# Remove quarantine bit (if any)
xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true

# Sign (ad-hoc always, Developer ID if provided)
sign_app "$APP_PATH" "$SIGN_ID"

echo "📦 Creating ZIP…"
zip_app "$APP_PATH" "$ZIP_PATH"

echo "✅ Built: $APP_PATH"
echo "✅ ZIP:   $ZIP_PATH"
open -R "$ZIP_PATH"
