#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="iManager"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
# Собираем во временный бандл и подменяем готовый в самом конце, чтобы
# запущенное приложение не теряло ресурсы (например, ipatool) во время сборки.
STAGE_DIR="$BUILD_DIR/$APP_NAME.app.staging"
MACOS_DIR="$STAGE_DIR/Contents/MacOS"
RESOURCES_DIR="$STAGE_DIR/Contents/Resources"
SDK_PATH="$(xcrun --show-sdk-path)"
SOURCES=$(find Sources/iManager -name '*.swift' | sort)

rm -rf "$STAGE_DIR"
trap 'rm -rf "$STAGE_DIR"' EXIT
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> SDK: $SDK_PATH"
echo "==> Исходники: $(echo "$SOURCES" | wc -l | tr -d ' ') файлов"

build_arch() {
    local arch="$1"
    local output="$2"

    swiftc \
        -O \
        -parse-as-library \
        -target "${arch}-apple-macos12.0" \
        -sdk "$SDK_PATH" \
        -framework SwiftUI \
        -framework AppKit \
        $SOURCES \
        -o "$output"
}

X86_BIN=""
ARM_BIN=""

if build_arch x86_64 "$BUILD_DIR/iManager-x86_64"; then
    X86_BIN="$BUILD_DIR/iManager-x86_64"
    echo "==> x86_64: готово"
fi

if build_arch arm64 "$BUILD_DIR/iManager-arm64"; then
    ARM_BIN="$BUILD_DIR/iManager-arm64"
    echo "==> arm64: готово"
fi

if [ -n "$X86_BIN" ] && [ -n "$ARM_BIN" ]; then
    echo "==> Universal binary"
    lipo -create "$X86_BIN" "$ARM_BIN" -output "$MACOS_DIR/$APP_NAME"
elif [ -n "$X86_BIN" ]; then
    cp "$X86_BIN" "$MACOS_DIR/$APP_NAME"
elif [ -n "$ARM_BIN" ]; then
    cp "$ARM_BIN" "$MACOS_DIR/$APP_NAME"
else
    echo "Ошибка: не удалось собрать ни одну архитектуру" >&2
    exit 1
fi

chmod +x "$MACOS_DIR/$APP_NAME"

cp Resources/Info.plist "$STAGE_DIR/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f Resources/bin/ipatool ]; then
    mkdir -p "$RESOURCES_DIR/bin"
    cp Resources/bin/ipatool "$RESOURCES_DIR/bin/ipatool"
    chmod +x "$RESOURCES_DIR/bin/ipatool"
    if codesign --force --sign - "$RESOURCES_DIR/bin/ipatool" >/dev/null 2>&1; then
        echo "==> ipatool: ad-hoc подпись"
    else
        echo "==> Предупреждение: не удалось подписать ipatool"
    fi
fi
if [ -f Resources/ipatool-shim.c ]; then
    echo "==> ipatool-shim: сборка"
    clang -dynamiclib -O2 \
        -arch x86_64 -arch arm64 \
        -isysroot "$SDK_PATH" \
        -mmacosx-version-min=12.0 \
        -framework CoreFoundation \
        -framework IOKit \
        Resources/ipatool-shim.c \
        -o "$RESOURCES_DIR/bin/ipatool-shim.dylib"
    chmod +x "$RESOURCES_DIR/bin/ipatool-shim.dylib"
    if codesign --force --sign - "$RESOURCES_DIR/bin/ipatool-shim.dylib" >/dev/null 2>&1; then
        echo "==> ipatool-shim: ad-hoc подпись"
    else
        echo "==> Предупреждение: не удалось подписать ipatool-shim"
    fi
fi
printf 'APPL????' > "$STAGE_DIR/Contents/PkgInfo"

if codesign --force --sign - "$STAGE_DIR" >/dev/null 2>&1; then
    echo "==> Подпись: ad-hoc"
else
    echo "==> Предупреждение: ad-hoc подпись не удалась"
fi

rm -rf "$APP_DIR"
mv "$STAGE_DIR" "$APP_DIR"

echo
echo "Готово: $APP_DIR"
echo "Запуск: open \"$APP_DIR\""
