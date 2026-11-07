#!/bin/bash
# Builds build/macos/Build/Products/Release/Amuse.app (signed ad hoc, for this Mac).
#   tool/build_macos.sh            # build only
#   tool/build_macos.sh --install  # build, then replace /Applications/Amuse.app
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build macos --release --dart-define-from-file=config/app_config.json

app=build/macos/Build/Products/Release/Amuse.app
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Amuse.app
  cp -R "$app" /Applications/
  echo "Installed /Applications/Amuse.app"
else
  echo "Built $app"
fi
