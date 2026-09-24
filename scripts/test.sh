#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --build-system native --scratch-path "${BUILD_DIR:-.build}"
