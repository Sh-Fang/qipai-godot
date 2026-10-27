#!/usr/bin/env bash
# Download the core's third-party dependencies into core/third_party/.
# (nlohmann/json is small and vendored directly.)
set -euo pipefail
cd "$(dirname "$0")/third_party"

ORT_VERSION=1.31.0
GODOT_CPP_COMMIT=8070599885b6df675fcad033dd032ce44be2b850  # master, ships extension_api-4-7.json

if [ ! -d onnxruntime/linux-x64 ]; then
    mkdir -p onnxruntime
    curl -fsSL "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-linux-x64-${ORT_VERSION}.tgz" \
        | tar xz -C onnxruntime
    mv "onnxruntime/onnxruntime-linux-x64-${ORT_VERSION}" onnxruntime/linux-x64
fi

# Android arm64: the official AAR, re-laid out as include/ + lib/ like the desktop release.
if [ ! -d onnxruntime/android-arm64 ]; then
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/ort.aar" \
        "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${ORT_VERSION}/onnxruntime-android-${ORT_VERSION}.aar"
    unzip -q "$tmp/ort.aar" 'headers/*' 'jni/arm64-v8a/*' -d "$tmp"
    mkdir -p onnxruntime/android-arm64
    mv "$tmp/headers" onnxruntime/android-arm64/include
    mv "$tmp/jni/arm64-v8a" onnxruntime/android-arm64/lib
    rm -rf "$tmp"
fi

if [ ! -d godot-cpp ]; then
    git init -q godot-cpp
    git -C godot-cpp fetch -q --depth 1 https://github.com/godotengine/godot-cpp.git "$GODOT_CPP_COMMIT"
    git -C godot-cpp checkout -q FETCH_HEAD
fi

echo "deps ready in $(pwd)"
