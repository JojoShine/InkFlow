#!/usr/bin/env bash
set -euo pipefail
mkdir -p dist
python3 tool/release/sign_macos_app.py
if [ "$1" = universal ]; then
  # Flutter's macOS release bundle contains both CPU architectures. Verify the
  # runner, Dart AOT code, and engine before claiming either download target.
  app=build/macos/Build/Products/Release/inkflow.app
  for binary in "$app/Contents/MacOS/inkflow" "$app/Contents/Frameworks/App.framework/App" "$app/Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS"; do
    lipo "$binary" -verify_arch x86_64 arm64
  done
  python3 tool/release/sign_artifact.py macos arm64
  python3 tool/release/sign_artifact.py macos x64
else
  python3 tool/release/sign_artifact.py macos "$1"
fi
