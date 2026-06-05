#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT}/Vendor/mediaremote-adapter"

if [[ ! -d "${VENDOR}" ]]; then
  echo "error: ${VENDOR} not found."
  echo "Clone upstream with:"
  echo "  git clone https://github.com/ungive/mediaremote-adapter.git \"${VENDOR}\""
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake not found. Install it first, e.g.: brew install cmake"
  exit 1
fi

cmake -S "${VENDOR}" -B "${VENDOR}/build"
cmake --build "${VENDOR}/build" --config Release

echo "Built:"
echo "  ${VENDOR}/build/MediaRemoteAdapter.framework"
echo "  ${VENDOR}/build/MediaRemoteAdapterTestClient"
echo ""
echo "Next: open BeatBar.xcodeproj in Xcode and build (Run Script copies these into the app bundle)."
