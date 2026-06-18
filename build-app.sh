#!/bin/bash
# Build "Snail Lock.app" + an installer .command, package into SnailLock.zip.
#
# Usage:
#   ./build-app.sh
#
# Attach the resulting SnailLock.zip to a GitHub release so people can install
# without building it themselves (see remote-install.sh).

set -e
cd "$(dirname "$0")"

# --- Build a universal (arm64 + x86_64) binary so both Apple Silicon and
# Intel recipients can launch it without "missing executable" errors.
if [ ! -f lock.swift ]; then
    echo "lock.swift not found; can't build."
    exit 1
fi
echo "Building universal binary…"
swiftc -target arm64-apple-macos13 lock.swift -o snail-lock-arm64
swiftc -target x86_64-apple-macos13 lock.swift -o snail-lock-x86
lipo -create snail-lock-arm64 snail-lock-x86 -output snail-lock
rm -f snail-lock-arm64 snail-lock-x86
file snail-lock | sed 's/^/  /'

if [ ! -x ./snail-lock ]; then
    echo "snail-lock binary unexpectedly missing after build."
    exit 1
fi

APP="Snail Lock.app"
STAGING="SnailLock"

# --- Clean ---
rm -rf "$APP" "$STAGING" SnailLock.zip

# --- Build the .app bundle ---
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp ./snail-lock "$APP/Contents/MacOS/snail-lock"
chmod +x "$APP/Contents/MacOS/snail-lock"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Snail Lock</string>
  <key>CFBundleDisplayName</key><string>Snail Lock</string>
  <key>CFBundleIdentifier</key><string>com.snail-lock.app</string>
  <key>CFBundleExecutable</key><string>snail-lock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP"
xattr -cr "$APP" 2>/dev/null || true

# --- Build the installer staging folder ---
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
cp snail_lock.conf.example "$STAGING/" 2>/dev/null || true

cat > "$STAGING/Install.command" <<'EOF'
#!/bin/bash
# Double-click this to install Snail Lock.

set -e
cd "$(dirname "$0")"

APP="Snail Lock.app"
if [ ! -d "$APP" ]; then
    echo "Couldn't find $APP next to this installer."
    echo "Make sure you unzipped everything before double-clicking."
    read -n 1 -s -r -p "Press any key to close."
    exit 1
fi

echo "🐌 Snail Lock installer"
echo

echo "Removing quarantine attributes..."
xattr -cr "$APP"

DEST="/Applications/$APP"
if cp -R "$APP" /Applications/ 2>/dev/null; then
    echo "Installed: $DEST"
else
    mkdir -p "$HOME/Applications"
    DEST="$HOME/Applications/$APP"
    rm -rf "$DEST"
    cp -R "$APP" "$HOME/Applications/"
    echo "No admin access to /Applications; installed to: $DEST"
fi

CFG="$HOME/.snail_lock.conf"
if [ ! -f "$CFG" ]; then
    if [ -f snail_lock.conf.example ]; then
        cp snail_lock.conf.example "$CFG"
        chmod 600 "$CFG"
        echo "Config created at $CFG"
        echo "  -> edit it to set your password and on-screen message."
    fi
else
    echo "Existing config at $CFG kept as-is."
fi

echo
echo "Launching Snail Lock..."
open "$DEST"

echo
echo "Done. You can close this window."
EOF
chmod +x "$STAGING/Install.command"

# --- Package ---
ditto -c -k --sequesterRsrc --keepParent "$STAGING" SnailLock.zip

echo
echo "Built:"
echo "  $APP"
echo "  $STAGING/  (with Install.command + app + config example)"
echo "  SnailLock.zip"
echo
echo "Publish it: attach SnailLock.zip to a GitHub release so remote-install.sh"
echo "(curl one-liner) and the manual flow can both grab it. The manual flow is:"
echo "unzip SnailLock.zip, then double-click Install.command."
