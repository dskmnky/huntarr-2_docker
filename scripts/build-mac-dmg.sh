#!/bin/bash
set -e

# Build Huntarr-2 macOS DMG (Universal Binary: Intel + Apple Silicon)
# Requires: Python 3.12+, pip, create-dmg (brew install create-dmg)
#
# Code Signing & Notarization:
#   Set these environment variables (or use --sign/--notarize flags):
#     DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#     APPLE_ID="your@email.com"
#     APPLE_PASSWORD="app-specific-password"  # Generate at appleid.apple.com
#     TEAM_ID="XXXXXXXXXX"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
VERSION=$(cat "$PROJECT_DIR/version.txt")
APP_NAME="Huntarr-2"

# Parse arguments
BUILD_ARCH="universal"  # default to universal
DO_SIGN=false
DO_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --arm64) BUILD_ARCH="arm64"; shift ;;
        --x86_64|--intel) BUILD_ARCH="x86_64"; shift ;;
        --universal) BUILD_ARCH="universal"; shift ;;
        --sign) DO_SIGN=true; shift ;;
        --notarize) DO_SIGN=true; DO_NOTARIZE=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Check signing requirements
if [ "$DO_SIGN" = true ] && [ -z "$DEVELOPER_ID" ]; then
    echo "❌ DEVELOPER_ID environment variable required for signing"
    echo "   Example: export DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\""
    exit 1
fi

if [ "$DO_NOTARIZE" = true ]; then
    if [ -z "$APPLE_ID" ] || [ -z "$APPLE_PASSWORD" ] || [ -z "$TEAM_ID" ]; then
        echo "❌ Notarization requires APPLE_ID, APPLE_PASSWORD, and TEAM_ID environment variables"
        exit 1
    fi
fi

echo "🔨 Building $APP_NAME v$VERSION for macOS ($BUILD_ARCH)..."

cd "$PROJECT_DIR"

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required"
    exit 1
fi

if ! command -v create-dmg &> /dev/null; then
    echo "📦 Installing create-dmg..."
    brew install create-dmg
fi

# Function to build for a specific architecture
build_for_arch() {
    local ARCH=$1
    local VENV_DIR="$PROJECT_DIR/.venv-build-$ARCH"
    local ARCH_DIST="$DIST_DIR-$ARCH"
    
    echo ""
    echo "🏗️  Building for $ARCH..."
    
    # Remove old venv to ensure clean arch-specific build
    if [ -d "$VENV_DIR" ]; then
        echo "🧹 Removing old $ARCH venv..."
        rm -rf "$VENV_DIR"
    fi
    
    # Create arch-specific venv
    echo "🐍 Creating $ARCH virtual environment..."
    if [ "$ARCH" = "x86_64" ]; then
        arch -x86_64 /usr/bin/python3 -m venv "$VENV_DIR"
    else
        python3 -m venv "$VENV_DIR"
    fi
    
    source "$VENV_DIR/bin/activate"
    
    # Install dependencies - use arch command for x86_64 to ensure correct wheels
    echo "📦 Installing Python dependencies for $ARCH..."
    if [ "$ARCH" = "x86_64" ]; then
        arch -x86_64 pip install --upgrade pip -q
        arch -x86_64 pip install --no-cache-dir -r requirements.txt -q
        arch -x86_64 pip install --no-cache-dir pyinstaller rumps pyobjc-framework-ServiceManagement -q
    else
        pip install --upgrade pip -q
        pip install -r requirements.txt -q
        pip install pyinstaller rumps pyobjc-framework-ServiceManagement -q
    fi
    
    # Build with PyInstaller
    echo "🔨 Running PyInstaller for $ARCH..."
    if [ "$ARCH" = "x86_64" ]; then
        arch -x86_64 python3 -m PyInstaller Huntarr2.spec --clean --noconfirm --distpath "$ARCH_DIST" --workpath "$BUILD_DIR-$ARCH" 2>&1 | tail -5
    else
        python3 -m PyInstaller Huntarr2.spec --clean --noconfirm --distpath "$ARCH_DIST" --workpath "$BUILD_DIR-$ARCH" 2>&1 | tail -5
    fi
    
    deactivate
    
    if [ ! -d "$ARCH_DIST/Huntarr-2.app" ]; then
        echo "❌ Build failed for $ARCH"
        exit 1
    fi
    
    echo "✅ $ARCH build complete"
}

# Create icon
echo "🎨 Creating app icon..."
mkdir -p icon.iconset
for size in 16 32 64 128 256 512; do
    src="frontend/static/logo/${size}.png"
    if [ -f "$src" ]; then
        cp "$src" "icon.iconset/icon_${size}x${size}.png"
    fi
done
[ -f icon.iconset/icon_32x32.png ] && cp icon.iconset/icon_32x32.png icon.iconset/icon_16x16@2x.png
[ -f icon.iconset/icon_64x64.png ] && cp icon.iconset/icon_64x64.png icon.iconset/icon_32x32@2x.png
[ -f icon.iconset/icon_256x256.png ] && cp icon.iconset/icon_256x256.png icon.iconset/icon_128x128@2x.png
[ -f icon.iconset/icon_512x512.png ] && cp icon.iconset/icon_512x512.png icon.iconset/icon_256x256@2x.png
iconutil -c icns icon.iconset -o app_icon.icns 2>/dev/null || cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns app_icon.icns

# Create PyInstaller spec
echo "📝 Creating PyInstaller spec..."
cat > Huntarr2.spec << 'SPECEOF'
# -*- mode: python ; coding: utf-8 -*-
import sys
import os
from PyInstaller.building.api import PYZ, EXE, COLLECT
from PyInstaller.building.build_main import Analysis
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

if sys.platform == 'darwin':
    try:
        from PyInstaller.building.api import BUNDLE
    except ImportError:
        try:
            from PyInstaller.building.osx import BUNDLE
        except ImportError:
            from PyInstaller.utils.osx import BUNDLE

# Collect apprise data files (attachment, plugins, assets, config, etc.)
apprise_datas = collect_data_files('apprise')
apprise_hiddenimports = collect_submodules('apprise')

# Read version from file
version = '1.0.0'
if os.path.exists('version.txt'):
    with open('version.txt', 'r') as f:
        version = f.read().strip()

a = Analysis(
    ['src/app_launcher.py'],
    pathex=['.'],
    datas=[
        ('frontend', 'frontend'),
        ('version.txt', '.'),
        ('LICENSE', '.'),
        ('src', 'src'),
        ('resources', 'resources'),
    ] + apprise_datas,
    hiddenimports=[
        'flask', 'flask.json', 'requests', 'waitress', 'bcrypt',
        'qrcode', 'PIL', 'pyotp', 'rumps', 'Foundation', 'AppKit',
        'ServiceManagement', 'objc', 'apprise', 'markdown', 'yaml',
        'src.primary.desktop_tray', 'src.primary.macos_menubar',
        'src.primary.utils.api_helpers',
        # apprise plugin submodules
        'apprise.plugins', 'apprise.attachment', 'apprise.config',
        'apprise.decorators', 'apprise.conversion',
    ] + apprise_hiddenimports,
    hookspath=[],
    runtime_hooks=[],
)

pyz = PYZ(a.pure, a.zipped_data)

exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name='Huntarr-2',
    debug=False,
    strip=False,
    upx=True,
    console=False,
    icon='app_icon.icns',
)

coll = COLLECT(
    exe, a.binaries, a.zipfiles, a.datas,
    strip=False, upx=True, name='Huntarr-2',
)

app = BUNDLE(
    coll,
    name='Huntarr-2.app',
    icon='app_icon.icns',
    bundle_identifier='io.huntarr2.app',
    info_plist={
        'CFBundleShortVersionString': version,
        'CFBundleVersion': version,
        'NSHighResolutionCapable': True,
        'LSUIElement': False,
    },
)
SPECEOF

# Build based on architecture choice
if [ "$BUILD_ARCH" = "universal" ]; then
    # Build for both architectures
    build_for_arch "arm64"
    build_for_arch "x86_64"
    
    echo ""
    echo "🔗 Creating universal binary..."
    
    # Start with arm64 as base
    rm -rf "$DIST_DIR/Huntarr-2.app"
    cp -R "$DIST_DIR-arm64/Huntarr-2.app" "$DIST_DIR/"
    
    # Find and merge all Mach-O binaries
    ARM_APP="$DIST_DIR-arm64/Huntarr-2.app"
    X86_APP="$DIST_DIR-x86_64/Huntarr-2.app"
    UNIVERSAL_APP="$DIST_DIR/Huntarr-2.app"
    
    # Merge main executable
    lipo -create \
        "$ARM_APP/Contents/MacOS/Huntarr-2" \
        "$X86_APP/Contents/MacOS/Huntarr-2" \
        -output "$UNIVERSAL_APP/Contents/MacOS/Huntarr-2"
    
    # Merge all .so and .dylib files
    find "$ARM_APP/Contents/MacOS" -type f \( -name "*.so" -o -name "*.dylib" \) | while read arm_lib; do
        rel_path="${arm_lib#$ARM_APP/}"
        x86_lib="$X86_APP/$rel_path"
        universal_lib="$UNIVERSAL_APP/$rel_path"
        
        if [ -f "$x86_lib" ]; then
            # Check if both are Mach-O
            if file "$arm_lib" | grep -q "Mach-O" && file "$x86_lib" | grep -q "Mach-O"; then
                lipo -create "$arm_lib" "$x86_lib" -output "$universal_lib" 2>/dev/null || cp "$arm_lib" "$universal_lib"
            fi
        fi
    done
    
    echo "✅ Universal binary created"
    
    # Verify
    echo ""
    echo "📋 Architecture verification:"
    file "$UNIVERSAL_APP/Contents/MacOS/Huntarr-2"
    
else
    # Single architecture build
    build_for_arch "$BUILD_ARCH"
    rm -rf "$DIST_DIR/Huntarr-2.app"
    cp -R "$DIST_DIR-$BUILD_ARCH/Huntarr-2.app" "$DIST_DIR/"
fi

# Code signing
FINAL_APP="$DIST_DIR/Huntarr-2.app"

if [ "$DO_SIGN" = true ]; then
    echo ""
    echo "🔏 Signing app with Developer ID..."
    
    # Sign all nested binaries first (inside out)
    find "$FINAL_APP" -type f \( -name "*.dylib" -o -name "*.so" \) -exec \
        codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp {} \;
    
    # Sign frameworks
    find "$FINAL_APP/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null | while read fw; do
        codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp "$fw"
    done
    
    # Sign the main executable
    codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp "$FINAL_APP/Contents/MacOS/Huntarr-2"
    
    # Sign the app bundle
    codesign --force --options runtime --sign "$DEVELOPER_ID" --timestamp "$FINAL_APP"
    
    # Verify signature
    echo "✅ Verifying signature..."
    codesign --verify --deep --strict "$FINAL_APP"
    spctl --assess --type execute "$FINAL_APP" && echo "✅ Gatekeeper will accept this app" || echo "⚠️  Gatekeeper assessment failed (may need notarization)"
else
    echo ""
    echo "🔏 Ad-hoc signing (use --sign for distribution)..."
    codesign --force --deep --sign - "$FINAL_APP"
fi

# Create DMG
echo ""
echo "💿 Creating DMG..."

if [ "$BUILD_ARCH" = "universal" ]; then
    DMG_NAME="Huntarr-2-${VERSION}-mac-universal.dmg"
else
    DMG_NAME="Huntarr-2-${VERSION}-mac-${BUILD_ARCH}.dmg"
fi

DMG_PATH="$PROJECT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

create-dmg \
    --volname "Huntarr-2" \
    --volicon "app_icon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Huntarr-2.app" 150 185 \
    --app-drop-link 450 185 \
    --hide-extension "Huntarr-2.app" \
    "$DMG_PATH" \
    "$DIST_DIR/Huntarr-2.app"

# Sign the DMG
if [ "$DO_SIGN" = true ]; then
    echo ""
    echo "🔏 Signing DMG..."
    codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
fi

# Notarization
if [ "$DO_NOTARIZE" = true ]; then
    echo ""
    echo "📤 Submitting for notarization..."
    echo "   This may take several minutes..."
    
    # Submit for notarization and wait
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    
    if [ $? -eq 0 ]; then
        echo "✅ Notarization successful!"
        
        # Staple the notarization ticket
        echo "📎 Stapling notarization ticket..."
        xcrun stapler staple "$DMG_PATH"
        
        echo "✅ DMG is now signed and notarized!"
    else
        echo "❌ Notarization failed. Check the submission log."
        exit 1
    fi
fi

echo ""
echo "✅ DMG created: $DMG_PATH"
echo ""

if [ "$DO_SIGN" = true ] && [ "$DO_NOTARIZE" = true ]; then
    echo "🎉 Ready for distribution! No Gatekeeper warnings."
elif [ "$DO_SIGN" = true ]; then
    echo "⚠️  Signed but not notarized. Run with --notarize for full Gatekeeper compatibility."
else
    echo "To install:"
    echo "  1. Open the DMG"
    echo "  2. Drag Huntarr-2 to Applications"
    echo "  3. If macOS blocks it: right-click → Open, or System Settings → Privacy & Security → Allow"
    echo ""
    echo "💡 For distribution without warnings, rebuild with:"
    echo "   ./scripts/build-mac-dmg.sh --notarize"
fi
