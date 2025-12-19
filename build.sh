#!/bin/bash

# Configuration
APP_NAME="Sharp Swift"
PROJECT_DIR="SharpConverter"
EXECUTABLE_NAME="SharpConverter"
SOURCE_PLIST="${PROJECT_DIR}/Sources/SharpConverter/Info.plist"
ICON_SOURCE="${PROJECT_DIR}/Sources/SharpConverter/Resources/icon.png" # Resources directory icon
BUILD_DIR="${PROJECT_DIR}/.build/release"
APP_BUNDLE="${APP_NAME}.app"

# Text Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Sharp Swift 빌드 시작...${NC}"

# 0. Build Rust Viewer (Brush) - SKIPPED (Now using MetalRenderer)
# echo -e "${GREEN}🦀 Rust Viewer build skipped...${NC}"

# 1. Swift Release Build
echo -e "${GREEN}📦 Swift 프로젝트 릴리즈 빌드 중...${NC}"
cd "${PROJECT_DIR}" || exit
swift build -c release --product SharpConverter -Xswiftc -DRELEASE
cd ..

# Check if build succeeded
if [ ! -f "${BUILD_DIR}/${EXECUTABLE_NAME}" ]; then
    echo "❌ 빌드 실패. 바이너리를 찾을 수 없습니다."
    exit 1
fi

# 2. Setup App Bundle Structure
echo -e "${GREEN}📂 앱 번들 구조 생성 중... (${APP_BUNDLE})${NC}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 3. Copy Executable/Binary
echo "   - 바이너리 복사"
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# 4. Copy Info.plist
if [ -f "${SOURCE_PLIST}" ]; then
    echo "   - Info.plist 설정"
    cp "${SOURCE_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"
else
    echo "⚠️  Info.plist를 찾을 수 없습니다. 기본값이 사용될 수 있습니다."
fi

# 5. Copy Shaders (Essential for Metal Renderer)
echo "   - Shaders.metal 복사"
cp "${PROJECT_DIR}/Sources/${PROJECT_DIR}/Renderer/Shaders.metal" "${APP_BUNDLE}/Contents/Resources/"

# 6. Generate App Icon (Requires iconutil)
if [ -f "${ICON_SOURCE}" ]; then
    echo "   - 앱 아이콘 생성 (icon.png -> AppIcon.icns)"
    ICONSET_DIR="AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"

    sips -z 16 16     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1

    iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    rm -rf "${ICONSET_DIR}"
else
    echo "⚠️  icon.png가 루트에 없습니다."
fi

# 7. Ad-hoc Signing
echo -e "${GREEN}🔏 앱 서명 (Ad-hoc)...${NC}"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo -e "${BLUE}🎉 빌드 완료! ./${APP_BUNDLE} 실행 가능${NC}"
