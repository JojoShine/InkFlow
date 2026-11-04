#!/usr/bin/env bash
set -euo pipefail
mkdir -p dist
python3 tool/release/sign_macos_app.py
python3 tool/release/sign_artifact.py macos "$1"
